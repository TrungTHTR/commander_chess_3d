import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../models/action_model.dart';
import '../../models/asset_manifest_model.dart';
import '../../models/board_coord.dart';
import '../../models/game_state_model.dart';
import '../../models/piece_model.dart';
import '../animation/camera_rig_3d.dart';
import '../assets/piece_asset_provider.dart';
import '../render/board_scene_renderer.dart';
import '../shaders/board_shader_handle.dart';
import '../world/board_3d_scene_state.dart';

/// Camera orbital view parameters decouple `engine/` from Riverpod `state/`.
@immutable
final class CameraViewTarget {
  const CameraViewTarget({
    required this.yaw,
    required this.pitch,
    required this.distance,
    this.target,
  });

  final double yaw;
  final double pitch;
  final double distance;
  final Vector3? target;
}

/// Fixed-timestep `Ticker` driver with `AppLifecycleListener` background pause.
final class FixedTimestepDriver {
  FixedTimestepDriver({
    required TickerProvider vsync,
    required this.onFixedStep,
    required this.onRenderFrame,
    this.fixedStepSeconds = 1.0 / 60.0,
    this.maxFrameDeltaSeconds = 0.05,
  }) {
    _ticker = vsync.createTicker(_onTick);
    _lifecycle = AppLifecycleListener(
      onPause: pause,
      onHide: pause,
      onResume: resume,
    );
  }

  final void Function(double fixedDt) onFixedStep;
  final void Function(double interpolationAlpha) onRenderFrame;
  final double fixedStepSeconds;
  final double maxFrameDeltaSeconds;

  late final Ticker _ticker;
  late final AppLifecycleListener _lifecycle;

  Duration? _lastElapsed;
  double _accumulator = 0.0;
  bool _paused = false;
  bool _disposed = false;

  bool get isPaused => _paused;
  bool get isActive => _ticker.isActive;

  void start() {
    if (_disposed || _ticker.isActive) return;
    _lastElapsed = null;
    _ticker.start();
  }

  void pause() {
    if (_disposed) return;
    _paused = true;
    _lastElapsed = null;
    _ticker.muted = true;
  }

  void resume() {
    if (_disposed) return;
    _paused = false;
    _lastElapsed = null;
    _ticker.muted = false;
  }

  void _onTick(Duration elapsed) {
    if (_paused || _disposed) return;
    final previousElapsed = _lastElapsed;
    if (previousElapsed == null) {
      _lastElapsed = elapsed;
      return;
    }

    final rawDt = (elapsed - previousElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    final clampedDt = math.min(math.max(rawDt, 0.0), maxFrameDeltaSeconds);

    _accumulator += clampedDt;
    var steps = 0;
    while (_accumulator >= fixedStepSeconds && steps < 4) {
      onFixedStep(fixedStepSeconds);
      _accumulator -= fixedStepSeconds;
      steps++;
    }

    onRenderFrame((_accumulator / fixedStepSeconds).clamp(0.0, 1.0));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lastElapsed = null;
    _lifecycle.dispose();
    _ticker.dispose();
  }
}

final class _PieceMotionState {
  _PieceMotionState({
    required this.pieceId,
    required this.visualKey,
    required this.currentCoord,
    required this.startWorld,
    required this.targetWorld,
    required this.currentWorld,
    required this.yawRadians,
    required this.stackCount,
    required this.carriedVisualKeys,
    required this.phaseSeed,
  });

  final String pieceId;
  PieceVisualKey visualKey;
  BoardCoord currentCoord;
  final Vector3 startWorld;
  final Vector3 targetWorld;
  final Vector3 currentWorld;
  double yawRadians;
  int stackCount;
  List<PieceVisualKey> carriedVisualKeys;
  final double phaseSeed;

  double moveProgress = 1.0;
  bool isAnimatingMove = false;
  double promoteTimer = 0.0;
  double movePitchRadians = 0.0;
  double moveRollRadians = 0.0;
  double moveLateralSign = 1.0;
}

/// 60/120Hz 3D scene controller driving camera spring physics, piece arc
/// animations, and shader uniform time completely outside Riverpod rebuilds.
final class Board3DSceneController extends ChangeNotifier {
  Board3DSceneController({
    required TickerProvider vsync,
    required this.renderer,
    required this.assetProvider,
    required this.shaderHandle,
    SpringOrbitCamera3D? camera,
    this.mapper = const BoardCoordinateMapper(),
    this.moveTweenDurationSeconds = 0.28,
  }) : camera = camera ?? SpringOrbitCamera3D() {
    _defaultTiles = mapper.buildDefaultTiles();
    _snapshot = RenderBoardSnapshot(tiles: _defaultTiles);
    _driver = FixedTimestepDriver(
      vsync: vsync,
      onFixedStep: _handleFixedStep,
      onRenderFrame: _handleRenderFrame,
    );
  }

  final BoardSceneRenderer renderer;
  final PieceAssetProvider assetProvider;
  final BoardShaderHandle shaderHandle;
  final SpringOrbitCamera3D camera;
  final BoardCoordinateMapper mapper;
  final double moveTweenDurationSeconds;

  late final FixedTimestepDriver _driver;
  late final List<BoardTileSpec> _defaultTiles;

  final Map<String, _PieceMotionState> _pieceMotions =
      <String, _PieceMotionState>{};
  final List<RenderPieceNode> _renderNodesScratch = <RenderPieceNode>[];
  final Vector3 _worldScratch = Vector3.zero();

  RenderBoardSnapshot _snapshot = const RenderBoardSnapshot();
  BoardCoord? _selectedCoord;
  List<LegalActionHint> _legalHints = const <LegalActionHint>[];
  List<BoardTileSpec> _activeTiles = const <BoardTileSpec>[];
  int _boardRanks = BoardCoord.rankCount;
  int _boardFiles = BoardCoord.fileCount;

  double _elapsedSeconds = 0.0;
  bool _initialized = false;
  bool _disposed = false;
  bool _usingExternalSnapshot = false;

  RenderBoardSnapshot get snapshot => _snapshot;
  double get elapsedSeconds => _elapsedSeconds;
  bool get isInitialized => _initialized;
  bool get isDisposed => _disposed;

  /// Initializes shader, optional manifest assets, and renderer, then starts
  /// the fixed-timestep loop.
  Future<void> initialize({AssetManifest? manifest}) async {
    if (_disposed || _initialized) return;
    await shaderHandle.initialize();
    if (_disposed) return;
    if (manifest != null) {
      await assetProvider.preloadAll(manifest);
      if (_disposed) return;
    }
    await renderer.initialize();
    if (_disposed) return;
    _initialized = true;
    _driver.start();
    notifyListeners();
  }

  void start() {
    if (_disposed) return;
    _driver.start();
  }

  void pause() {
    if (_disposed) return;
    _driver.pause();
  }

  void resume() {
    if (_disposed) return;
    _driver.resume();
  }

  /// Synchronizes discrete game state into the engine's continuous 3D motion
  /// buffers without triggering widget rebuilds.
  void syncFromGameState({
    required GameSessionState session,
    BoardCoord? selectedCoord,
    List<LegalActionHint> legalHints = const <LegalActionHint>[],
    List<BoardTileSpec>? tiles,
  }) {
    if (_disposed) return;

    _usingExternalSnapshot = false;
    _boardRanks = session.boardRanks;
    _boardFiles = session.boardFiles;
    _selectedCoord = selectedCoord;
    _legalHints = List<LegalActionHint>.unmodifiable(legalHints);
    _activeTiles = tiles ?? _defaultTiles;

    final seenIds = <String>{};
    for (final piece in session.pieces) {
      if (!piece.isAlive) continue;
      seenIds.add(piece.id);

      final visualKey = PieceVisualKey(
        type: piece.type,
        side: piece.side,
        isHero: piece.isHero,
        faction: session.factionFor(piece.side),
      );
      // Local piece forward is +Z (`docs/BLENDER_ASSET_CONTRACT.md`);
      // Red sits at +Z (rank 0 => Z=+5.5) and rotates π to face -Z toward Blue,
      // while Blue sits at -Z (rank 11 => Z=-5.5) with yaw 0.0 to face +Z.
      final targetYaw = piece.side == PlayerSide.red ? math.pi : 0.0;
      final stackCount = 1 + piece.carriedPieces.length;
      final carriedVisualKeys = piece.carriedPieces.isEmpty
          ? const <PieceVisualKey>[]
          : List<PieceVisualKey>.unmodifiable(
              piece.carriedPieces.map(
                (carried) => PieceVisualKey(
                  type: carried.type,
                  side: carried.side,
                  isHero: carried.isHero,
                ),
              ),
            );
      final existing = _pieceMotions[piece.id];

      if (existing == null) {
        final initialWorld = mapper.coordToWorld(piece.position);
        _pieceMotions[piece.id] = _PieceMotionState(
          pieceId: piece.id,
          visualKey: visualKey,
          currentCoord: piece.position,
          startWorld: initialWorld.clone(),
          targetWorld: initialWorld.clone(),
          currentWorld: initialWorld,
          yawRadians: targetYaw,
          stackCount: stackCount,
          carriedVisualKeys: carriedVisualKeys,
          phaseSeed: (piece.id.hashCode & 0xFF) * 0.05,
        );
      } else {
        if (!existing.visualKey.isHero && visualKey.isHero) {
          existing.promoteTimer = 0.85;
        } else if (!visualKey.isHero) {
          existing.promoteTimer = 0.0;
        }
        existing.visualKey = visualKey;
        existing.yawRadians = targetYaw;
        existing.stackCount = stackCount;
        existing.carriedVisualKeys = carriedVisualKeys;

        if (existing.currentCoord != piece.position) {
          existing.currentCoord = piece.position;
          existing.startWorld.setFrom(existing.currentWorld);
          mapper.coordToWorldInto(piece.position, existing.targetWorld);
          final dx = existing.targetWorld.x - existing.startWorld.x;
          final dz = existing.targetWorld.z - existing.startWorld.z;
          final localRight = dx * math.cos(targetYaw) - dz * math.sin(targetYaw);
          existing.moveLateralSign = localRight >= 0.0 ? 1.0 : -1.0;
          existing.moveProgress = 0.0;
          existing.isAnimatingMove = true;
        }
      }
    }

    _pieceMotions.removeWhere((id, _) => !seenIds.contains(id));
    _rebuildSnapshot();
    notifyListeners();
  }

  /// Directly replaces the current render snapshot (useful for standalone tests
  /// or pre-assembled engine scenes).
  void updateSnapshot(RenderBoardSnapshot snapshot) {
    if (_disposed) return;
    _usingExternalSnapshot = true;
    _boardRanks = snapshot.ranks;
    _boardFiles = snapshot.files;
    _selectedCoord = snapshot.selectedCoord;
    _legalHints = snapshot.legalHints;
    _activeTiles = snapshot.tiles.isEmpty ? _defaultTiles : snapshot.tiles;
    _snapshot = snapshot;
    notifyListeners();
  }

  void setCameraTarget(CameraViewTarget target, {bool animate = true}) {
    setCameraPreset(
      yaw: target.yaw,
      pitch: target.pitch,
      distance: target.distance,
      target: target.target,
      animate: animate,
    );
  }

  void setCameraPreset({
    required double yaw,
    required double pitch,
    required double distance,
    Vector3? target,
    bool animate = true,
  }) {
    if (_disposed) return;
    if (animate) {
      camera.animateToPreset(
        yaw: yaw,
        pitch: pitch,
        distance: distance,
        target: target,
      );
    } else {
      camera.snapToPreset(
        yaw: yaw,
        pitch: pitch,
        distance: distance,
        target: target,
      );
      notifyListeners();
    }
  }

  void orbit(double dx, double dy) {
    if (_disposed) return;
    camera.orbitBy(dx, dy);
    notifyListeners();
  }

  void zoom(double delta) {
    if (_disposed) return;
    camera.zoomBy(delta);
    notifyListeners();
  }

  BoardCoord? hitTestBoardCoord(Offset localPosition, Size viewportSize) {
    if (_disposed) return null;
    return renderer.hitTestBoardCoord(
      localPosition: localPosition,
      viewportSize: viewportSize,
      camera: camera,
      files: _boardFiles,
      ranks: _boardRanks,
    );
  }

  void render(Canvas canvas, Size size) {
    if (_disposed) return;
    renderer.render(canvas, size, _snapshot, camera);
  }

  void _handleFixedStep(double fixedDt) {
    _elapsedSeconds += fixedDt;
    camera.step(fixedDt);

    final duration =
        moveTweenDurationSeconds <= 0.001 ? 0.001 : moveTweenDurationSeconds;
    for (final motion in _pieceMotions.values) {
      if (motion.isAnimatingMove) {
        motion.moveProgress =
            (motion.moveProgress + fixedDt / duration).clamp(0.0, 1.0);
        final t = _easeInOutCubic(motion.moveProgress);
        final arcEnv = math.sin(motion.moveProgress * math.pi);
        final lift = arcEnv * 0.55;

        motion.currentWorld.setValues(
          motion.startWorld.x + (motion.targetWorld.x - motion.startWorld.x) * t,
          motion.startWorld.y +
              (motion.targetWorld.y - motion.startWorld.y) * t +
              lift,
          motion.startWorld.z + (motion.targetWorld.z - motion.startWorld.z) * t,
        );

        switch (motion.visualKey.type) {
          case PieceType.airForce:
            motion.movePitchRadians =
                -0.18 * math.cos(motion.moveProgress * math.pi);
            motion.moveRollRadians = 0.24 * arcEnv * motion.moveLateralSign;
          case PieceType.navy:
            motion.movePitchRadians = -0.09 * arcEnv;
            motion.moveRollRadians =
                0.06 * math.sin(motion.moveProgress * math.pi * 2.0) * motion.moveLateralSign;
          case PieceType.tank:
          case PieceType.artillery:
          case PieceType.antiAircraft:
          case PieceType.missile:
          case PieceType.engineer:
            motion.movePitchRadians =
                -0.08 * math.cos(motion.moveProgress * math.pi);
            motion.moveRollRadians = 0.0;
          case PieceType.commander:
          case PieceType.infantry:
          case PieceType.militia:
          case PieceType.headquarters:
            motion.movePitchRadians = 0.12 * arcEnv;
            motion.moveRollRadians = 0.0;
        }

        if (motion.moveProgress >= 1.0) {
          motion.currentWorld.setFrom(motion.targetWorld);
          motion.isAnimatingMove = false;
          motion.movePitchRadians = 0.0;
          motion.moveRollRadians = 0.0;
        }
      } else {
        if (motion.promoteTimer > 0.0) {
          motion.promoteTimer = math.max(0.0, motion.promoteTimer - fixedDt);
        }
        motion.movePitchRadians = 0.0;
        motion.moveRollRadians = 0.0;

        // Subtle alive float/idle elevation without mutating targetWorld.
        final isSelected =
            _selectedCoord != null && motion.currentCoord == _selectedCoord;
        var idleY = 0.0;
        if (isSelected) {
          idleY = 0.07 + 0.025 * math.sin(_elapsedSeconds * 4.5);
        } else if (motion.visualKey.type == PieceType.airForce) {
          idleY = 0.03 * math.sin(_elapsedSeconds * 2.6 + motion.phaseSeed);
        } else if (motion.visualKey.type == PieceType.navy) {
          idleY = 0.015 * math.sin(_elapsedSeconds * 2.1 + motion.phaseSeed);
        }
        if (motion.promoteTimer > 0.0) {
          final p = 1.0 - (motion.promoteTimer / 0.85);
          idleY += math.sin(p * math.pi) * 0.18;
        }
        motion.currentWorld.setValues(
          motion.targetWorld.x,
          motion.targetWorld.y + idleY,
          motion.targetWorld.z,
        );
      }
    }

    _rebuildSnapshot();
  }

  void _handleRenderFrame(double interpolationAlpha) {
    if (_disposed) return;
    notifyListeners();
  }

  void _rebuildSnapshot() {
    if (_usingExternalSnapshot &&
        _pieceMotions.isEmpty &&
        _snapshot.pieces.isNotEmpty) {
      _snapshot = _snapshot.copyWith(elapsedSeconds: _elapsedSeconds);
      return;
    }

    _renderNodesScratch.clear();
    for (final motion in _pieceMotions.values) {
      final isSelected =
          _selectedCoord != null && motion.currentCoord == _selectedCoord;
      final PieceAnimClip clip;
      final double animProgress;
      if (motion.isAnimatingMove) {
        clip = PieceAnimClip.move;
        animProgress = motion.moveProgress;
      } else if (motion.promoteTimer > 0.0) {
        clip = PieceAnimClip.promote;
        animProgress = (1.0 - motion.promoteTimer / 0.85).clamp(0.0, 1.0);
      } else if (isSelected) {
        clip = PieceAnimClip.select;
        animProgress = 0.0;
      } else {
        clip = PieceAnimClip.idle;
        animProgress = 0.0;
      }

      _worldScratch.setFrom(motion.currentWorld);
      _renderNodesScratch.add(
        RenderPieceNode(
          pieceId: motion.pieceId,
          visualKey: motion.visualKey,
          worldPosition: _worldScratch.clone(),
          yawRadians: motion.yawRadians,
          stackCount: motion.stackCount,
          carriedVisualKeys: motion.carriedVisualKeys,
          isSelected: isSelected,
          animClip: clip,
          animProgress: animProgress,
          phaseSeed: motion.phaseSeed,
          movePitchRadians: motion.movePitchRadians,
          moveRollRadians: motion.moveRollRadians,
        ),
      );
    }

    _snapshot = RenderBoardSnapshot(
      ranks: _boardRanks,
      files: _boardFiles,
      tiles: _activeTiles.isEmpty ? _defaultTiles : _activeTiles,
      pieces: List<RenderPieceNode>.unmodifiable(_renderNodesScratch),
      legalHints: _legalHints,
      selectedCoord: _selectedCoord,
      elapsedSeconds: _elapsedSeconds,
    );
  }

  static double _easeInOutCubic(double t) {
    return t < 0.5 ? 4.0 * t * t * t : 1.0 - math.pow(-2.0 * t + 2.0, 3) / 2.0;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _driver.dispose();
    shaderHandle.dispose();
    renderer.dispose();
    assetProvider.dispose();
    _pieceMotions.clear();
    _renderNodesScratch.clear();
    super.dispose();
  }
}
