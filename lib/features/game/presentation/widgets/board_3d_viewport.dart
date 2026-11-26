import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../../../core/result/result.dart';
import '../../engine/animation/camera_rig_3d.dart';
import '../../engine/assets/piece_asset_provider.dart';
import '../../engine/loop/board_3d_scene_controller.dart';
import '../../engine/render/board_scene_renderer.dart';
import '../../engine/render/placeholder_3d_board_renderer.dart';
import '../../engine/shaders/board_shader_handle.dart';
import '../../models/asset_manifest_model.dart';
import '../../models/board_coord.dart';
import '../../state/game_hud_snapshot.dart';
import '../../state/game_providers.dart';

/// Factory signature for constructing a [BoardSceneRenderer] (supports
/// swapping `Placeholder3DBoardRenderer` for future `.glb` or test renderers).
typedef BoardSceneRendererFactory = BoardSceneRenderer Function(
  PieceAssetProvider assetProvider,
  BoardShaderHandle shaderHandle,
);

/// Interactive 60/120Hz 3D Commander Chess viewport isolated inside a
/// [RepaintBoundary] so camera orbits and piece animations trigger zero HUD rebuilds.
final class Board3DViewport extends ConsumerStatefulWidget {
  const Board3DViewport({
    super.key,
    required this.onCoordTapped,
    this.assetProviderFactory,
    this.rendererFactory,
    this.shaderHandleFactory,
    this.onControllerCreated,
  });

  final ValueChanged<BoardCoord> onCoordTapped;
  final PieceAssetProvider Function()? assetProviderFactory;
  final BoardSceneRendererFactory? rendererFactory;
  final BoardShaderHandle Function()? shaderHandleFactory;
  final ValueChanged<Board3DSceneController>? onControllerCreated;

  /// Maps discrete HUD [OrbitCameraPreset] choices to 3D orbital coordinates,
  /// applying aspect-ratio framing compensation on portrait [viewportSize]s so
  /// all 132 board intersections remain visible within the viewport.
  static CameraViewTarget cameraTargetForPreset(
    OrbitCameraPreset preset, {
    Size? viewportSize,
  }) {
    final (double yaw, double pitch, double baseDistance) = switch (preset) {
      OrbitCameraPreset.redCommander => (0.0, 0.86, 16.2),
      OrbitCameraPreset.blueCommander => (math.pi, 0.86, 16.2),
      OrbitCameraPreset.tacticalTop => (0.0, 1.42, 17.5),
      OrbitCameraPreset.sideOverview => (-math.pi / 2.6, 0.72, 17.8),
    };

    var distance = baseDistance;
    if (viewportSize != null &&
        viewportSize.width.isFinite &&
        viewportSize.height.isFinite &&
        viewportSize.width > 0.0 &&
        viewportSize.height > 0.0) {
      distance = SpringOrbitCamera3D.computeBoardFitDistance(
        baseDistance: baseDistance,
        aspectRatio: viewportSize.width / viewportSize.height,
        yaw: yaw,
        pitch: pitch,
      );
    }

    return CameraViewTarget(
      yaw: yaw,
      pitch: pitch,
      distance: distance,
      target: Vector3.zero(),
    );
  }

  @override
  ConsumerState<Board3DViewport> createState() => _Board3DViewportState();
}

final class _Board3DViewportState extends ConsumerState<Board3DViewport>
    with SingleTickerProviderStateMixin {
  late final PieceAssetProvider _assetProvider;
  late final BoardShaderHandle _shaderHandle;
  late final BoardSceneRenderer _renderer;
  late final Board3DSceneController _controller;
  late final List<BoardTileSpec> _boardTiles;

  AssetManifest? _preloadedManifest;
  double _lastPinchScale = 1.0;
  Size? _lastViewportSize;

  @override
  void initState() {
    super.initState();

    final topology = ref.read(boardTopologyProvider);
    _boardTiles = topology.buildAllTiles();

    _assetProvider =
        widget.assetProviderFactory?.call() ?? ProceduralPieceAssetProvider();
    _shaderHandle = widget.shaderHandleFactory?.call() ?? BoardShaderHandle();
    _renderer =
        widget.rendererFactory?.call(_assetProvider, _shaderHandle) ??
        Placeholder3DBoardRenderer(
          assetProvider: _assetProvider,
          shaderHandle: _shaderHandle,
        );

    _controller = Board3DSceneController(
      vsync: this,
      renderer: _renderer,
      assetProvider: _assetProvider,
      shaderHandle: _shaderHandle,
    );
    widget.onControllerCreated?.call(_controller);

    final initialHud = ref.read(gameSessionNotifierProvider);
    _syncHudToController(initialHud, animateCamera: false);

    // Render procedural 3D geometry immediately on frame 1; manifest preloading
    // upgrades asset descriptors asynchronously when available.
    unawaited(_controller.initialize());
    ref.read(assetManifestProvider).whenData(_onManifestResult);
  }

  void _syncHudToController(
    GameHudSnapshot hud, {
    required bool animateCamera,
  }) {
    if (hud.session.pieces.isEmpty) {
      _controller.updateSnapshot(
        _controller.snapshot.copyWith(
          ranks: hud.session.boardRanks,
          files: hud.session.boardFiles,
          tiles: _boardTiles,
          pieces: const [],
          legalHints: hud.legalHints,
          selectedCoord: hud.selectedCoord,
          clearSelectedCoord: hud.selectedCoord == null,
        ),
      );
    } else {
      _controller.syncFromGameState(
        session: hud.session,
        selectedCoord: hud.selectedCoord,
        legalHints: hud.legalHints,
        tiles: _boardTiles,
      );
    }

    _controller.setCameraTarget(
      cameraTargetForPreset(hud.cameraPreset, viewportSize: _lastViewportSize),
      animate: animateCamera,
    );
  }

  void _onManifestResult(Result<AssetManifest> result) {
    result.when(
      ok: (manifest) {
        if (!mounted || _preloadedManifest == manifest) return;
        _preloadedManifest = manifest;
        unawaited(_preloadManifestAssets(manifest));
      },
      err: (_) {
        // Keep procedural geometry active when manifest loading fails.
      },
    );
  }

  Future<void> _preloadManifestAssets(AssetManifest manifest) async {
    await _assetProvider.preloadAll(manifest);
    if (!mounted) return;
    _controller.requestRepaint();
  }

  static CameraViewTarget cameraTargetForPreset(
    OrbitCameraPreset preset, {
    Size? viewportSize,
  }) {
    return Board3DViewport.cameraTargetForPreset(
      preset,
      viewportSize: viewportSize,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && event.scrollDelta.dy != 0.0) {
      _controller.zoom(event.scrollDelta.dy * 0.012);
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _lastPinchScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount <= 1) {
      final delta = details.focalPointDelta;
      if (delta != Offset.zero) {
        _controller.orbit(delta.dx, delta.dy);
      }
      return;
    }

    final scaleDelta = details.scale - _lastPinchScale;
    if (scaleDelta.abs() > 0.0005) {
      _controller.zoom(-scaleDelta * 12.0);
      _lastPinchScale = details.scale;
    }
    final delta = details.focalPointDelta;
    if (delta != Offset.zero) {
      _controller.orbit(delta.dx * 0.6, delta.dy * 0.6);
    }
  }

  void _handleTapUp(TapUpDetails details, Size viewportSize) {
    final coord = _controller.hitTestBoardCoord(
      details.localPosition,
      viewportSize,
    );
    if (coord != null) {
      widget.onCoordTapped(coord);
    }
  }

  @override
  void dispose() {
    // Disposes FixedTimestepDriver, BoardShaderHandle, BoardSceneRenderer,
    // and PieceAssetProvider cleanly in a single deterministic lifecycle pass.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<GameHudSnapshot>(gameSessionNotifierProvider, (previous, next) {
      final discreteStateChanged =
          previous == null ||
          previous.session != next.session ||
          previous.selectedCoord != next.selectedCoord ||
          previous.legalHints != next.legalHints;
      if (discreteStateChanged) {
        if (next.session.pieces.isEmpty) {
          _controller.updateSnapshot(
            _controller.snapshot.copyWith(
              ranks: next.session.boardRanks,
              files: next.session.boardFiles,
              tiles: _boardTiles,
              pieces: const [],
              legalHints: next.legalHints,
              selectedCoord: next.selectedCoord,
              clearSelectedCoord: next.selectedCoord == null,
            ),
          );
        } else {
          _controller.syncFromGameState(
            session: next.session,
            selectedCoord: next.selectedCoord,
            legalHints: next.legalHints,
            tiles: _boardTiles,
          );
        }
      }

      if (previous?.cameraPreset != next.cameraPreset) {
        _controller.setCameraTarget(
          cameraTargetForPreset(
            next.cameraPreset,
            viewportSize: _lastViewportSize,
          ),
          animate: true,
        );
      }
    });

    ref.listen<AsyncValue<Result<AssetManifest>>>(
      assetManifestProvider,
      (_, next) => next.whenData(_onManifestResult),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        if (viewportSize.width.isFinite &&
            viewportSize.height.isFinite &&
            viewportSize.width > 0.0 &&
            viewportSize.height > 0.0) {
          final previousSize = _lastViewportSize;
          if (previousSize == null) {
            _lastViewportSize = viewportSize;
            final fitted = cameraTargetForPreset(
              ref.read(gameSessionNotifierProvider).cameraPreset,
              viewportSize: viewportSize,
            );
            _controller.camera.snapToPreset(
              yaw: fitted.yaw,
              pitch: fitted.pitch,
              distance: fitted.distance,
              target: fitted.target,
            );
          } else if (previousSize != viewportSize) {
            _lastViewportSize = viewportSize;
            if ((previousSize.aspectRatio - viewportSize.aspectRatio).abs() >
                0.01) {
              final fitted = cameraTargetForPreset(
                ref.read(gameSessionNotifierProvider).cameraPreset,
                viewportSize: viewportSize,
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _controller.isDisposed) return;
                _controller.setCameraTarget(fitted, animate: false);
              });
            }
          }
        }
        return Listener(
          onPointerSignal: _handlePointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTapUp(details, viewportSize),
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: Board3DCustomPainter(controller: _controller),
                isComplex: true,
                willChange: true,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}
