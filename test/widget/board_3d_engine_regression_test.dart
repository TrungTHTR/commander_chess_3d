import 'dart:math' as math;

import 'package:commander_chess_3d/core/time/clock.dart';
import 'package:commander_chess_3d/features/game/engine/animation/camera_rig_3d.dart';
import 'package:commander_chess_3d/features/game/engine/assets/piece_asset_provider.dart';
import 'package:commander_chess_3d/features/game/engine/loop/board_3d_scene_controller.dart';
import 'package:commander_chess_3d/features/game/engine/render/placeholder_3d_board_renderer.dart';
import 'package:commander_chess_3d/features/game/engine/shaders/board_shader_handle.dart';
import 'package:commander_chess_3d/features/game/engine/world/board_3d_scene_state.dart';
import 'package:commander_chess_3d/features/game/models/asset_manifest_model.dart';
import 'package:commander_chess_3d/features/game/models/board_coord.dart';
import 'package:commander_chess_3d/features/game/models/game_state_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:commander_chess_3d/features/game/presentation/screens/commander_game_screen.dart';
import 'package:commander_chess_3d/features/game/presentation/theme/commander_theme.dart';
import 'package:commander_chess_3d/features/game/presentation/widgets/board_3d_viewport.dart';
import 'package:commander_chess_3d/features/game/state/game_hud_snapshot.dart';
import 'package:commander_chess_3d/features/game/state/game_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3, Vector4;

Offset _projectWorldWithTarget({
  required CameraViewTarget target,
  required BoardCoord coord,
  required Size viewportSize,
}) {
  const mapper = BoardCoordinateMapper();
  final camera = SpringOrbitCamera3D(
    yaw: target.yaw,
    pitch: target.pitch,
    distance: target.distance,
    target: target.target,
  );
  final world = mapper.coordToWorld(coord);
  final vp = camera.viewProjectionMatrix(viewportSize);
  final clip = Vector4(world.x, world.y, world.z, 1.0);
  vp.transform(clip);
  final invW = 1.0 / clip.w;
  return Offset(
    (clip.x * invW * 0.5 + 0.5) * viewportSize.width,
    (0.5 - clip.y * invW * 0.5) * viewportSize.height,
  );
}

void main() {
  final fixedClock = FixedClock(DateTime.utc(2026, 11, 20, 18, 0, 0));

  Future<void> configureViewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> unmountTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('3D Engine orientation, passenger sockets, NaN guards, and FixedTimestepDriver', () {
    testWidgets('syncFromGameState assigns yaw=pi for Red, yaw=0.0 for Blue, and populates carriedVisualKeys', (tester) async {
      final provider = ProceduralPieceAssetProvider();
      final shaderHandle = BoardShaderHandle();
      final renderer = Placeholder3DBoardRenderer(
        assetProvider: provider,
        shaderHandle: shaderHandle,
      );
      final controller = Board3DSceneController(
        vsync: tester,
        renderer: renderer,
        assetProvider: provider,
        shaderHandle: shaderHandle,
      );
      try {
        final session = GameSessionState(
          matchId: 'yaw_and_sockets',
          mode: GameMode.localPassAndPlay,
          currentTurn: PlayerSide.red,
          phase: MatchPhase.playing,
          pieces: <PieceEntity>[
            PieceEntity(
              id: 'red_navy_carrier',
              side: PlayerSide.red,
              type: PieceType.navy,
              position: BoardCoord.fromAlgebraic('b2'),
              carriedPieces: <PieceEntity>[
                PieceEntity(
                  id: 'red_infantry_passenger',
                  side: PlayerSide.red,
                  type: PieceType.infantry,
                  position: BoardCoord.fromAlgebraic('b2'),
                  isHero: true,
                ),
                PieceEntity(
                  id: 'red_militia_passenger',
                  side: PlayerSide.red,
                  type: PieceType.militia,
                  position: BoardCoord.fromAlgebraic('b2'),
                ),
              ],
            ),
            PieceEntity(
              id: 'blue_tank_solo',
              side: PlayerSide.blue,
              type: PieceType.tank,
              position: BoardCoord.fromAlgebraic('g9'),
            ),
          ],
        );

        controller.syncFromGameState(session: session);

        final nodesById = <String, RenderPieceNode>{
          for (final node in controller.snapshot.pieces) node.pieceId: node,
        };
        final redNode = nodesById['red_navy_carrier']!;
        final blueNode = nodesById['blue_tank_solo']!;

        expect(redNode.yawRadians, closeTo(math.pi, 1e-9));
        expect(blueNode.yawRadians, closeTo(0.0, 1e-9));
        expect(redNode.stackCount, 3);
        expect(
          redNode.carriedVisualKeys,
          equals(const <PieceVisualKey>[
            PieceVisualKey(
              type: PieceType.infantry,
              side: PlayerSide.red,
              isHero: true,
            ),
            PieceVisualKey(
              type: PieceType.militia,
              side: PlayerSide.red,
              isHero: false,
            ),
          ]),
        );
        expect(blueNode.stackCount, 1);
        expect(blueNode.carriedVisualKeys, isEmpty);
      } finally {
        controller.dispose();
      }
    });

    test('BoardCoordinateMapper.worldToCoord and SpringOrbitCamera3D guard NaN and Infinity safely', () {
      const mapper = BoardCoordinateMapper();
      expect(mapper.worldToCoord(Vector3(double.nan, 0.0, 0.0)), isNull);
      expect(mapper.worldToCoord(Vector3(0.0, double.nan, 0.0)), isNull);
      expect(mapper.worldToCoord(Vector3(0.0, 0.0, double.infinity)), isNull);
      expect(
        mapper.worldToCoord(Vector3(double.negativeInfinity, 0.0, 0.0)),
        isNull,
      );
      expect(
        mapper.worldToCoord(Vector3.zero(), pickMargin: double.nan),
        isNull,
      );
      expect(
        const BoardCoordinateMapper(tileSize: 0.0).worldToCoord(Vector3.zero()),
        isNull,
      );
      expect(
        const BoardCoordinateMapper(tileSize: double.nan)
            .worldToCoord(Vector3.zero()),
        isNull,
      );

      final camera = SpringOrbitCamera3D(
        yaw: 0.25,
        pitch: 0.86,
        distance: 16.2,
      );

      camera.orbitBy(double.nan, 10.0);
      camera.orbitBy(10.0, double.infinity);
      camera.orbitBy(5.0, 5.0, sensitivity: double.nan);
      camera.zoomBy(double.nan);
      camera.zoomBy(double.infinity);
      camera.zoomBy(double.negativeInfinity);
      camera.snapToPreset(
        yaw: double.nan,
        pitch: 0.8,
        distance: 16.0,
      );
      camera.animateToPreset(
        yaw: 0.0,
        pitch: double.infinity,
        distance: 16.0,
      );
      camera.animateToPreset(
        yaw: 0.0,
        pitch: 0.8,
        distance: 16.0,
        target: Vector3(double.nan, 0.0, 0.0),
      );

      expect(camera.step(double.nan), isFalse);
      expect(camera.step(double.infinity), isFalse);
      expect(camera.step(-0.1), isFalse);
      expect(camera.step(0.016), isFalse);

      expect(camera.yaw, closeTo(0.25, 1e-9));
      expect(camera.pitch, closeTo(0.86, 1e-9));
      expect(camera.distance, closeTo(16.2, 1e-9));
      expect(camera.target.x, 0.0);
      expect(camera.target.y, 0.0);
      expect(camera.target.z, 0.0);

      expect(
        camera.unprojectRayToGroundPlane(
          const Offset(double.nan, 100),
          const Size(800, 600),
        ),
        isNull,
      );
      expect(
        camera.unprojectRayToGroundPlane(
          const Offset(400, 300),
          const Size(double.infinity, 600),
        ),
        isNull,
      );
    });

    testWidgets('FixedTimestepDriver advances elapsedSeconds on tick 2 even when tick 1 fires at Duration.zero', (tester) async {
      final fixedSteps = <double>[];
      var renderFrames = 0;

      final driver = FixedTimestepDriver(
        vsync: tester,
        onFixedStep: fixedSteps.add,
        onRenderFrame: (_) => renderFrames++,
      );
      try {
        driver.start();
        // Tick 1 at Duration.zero initializes _lastElapsed without throwing or dropping tick 2.
        await tester.pump(Duration.zero);
        expect(fixedSteps, isEmpty);

        // Tick 2 at +20ms (> 16.67ms fixedStepSeconds) executes one fixed step.
        await tester.pump(const Duration(milliseconds: 20));
        expect(fixedSteps, hasLength(1));
        expect(renderFrames, 1);
      } finally {
        driver.dispose();
      }

      // Also verify end-to-end on Board3DSceneController.
      final provider = ProceduralPieceAssetProvider();
      final shaderHandle = BoardShaderHandle();
      final renderer = Placeholder3DBoardRenderer(
        assetProvider: provider,
        shaderHandle: shaderHandle,
      );
      final controller = Board3DSceneController(
        vsync: tester,
        renderer: renderer,
        assetProvider: provider,
        shaderHandle: shaderHandle,
      );
      try {
        await controller.initialize();
        await tester.pump(Duration.zero);
        expect(controller.elapsedSeconds, 0.0);

        await tester.pump(const Duration(milliseconds: 20));
        expect(controller.elapsedSeconds, greaterThan(0.0));
        expect(controller.snapshot.elapsedSeconds, controller.elapsedSeconds);
      } finally {
        controller.dispose();
      }
    });
  });

  group('Portrait, square, near-square, ultra-narrow & landscape 132/132 board framing', () {
    test('Board3DViewport.cameraTargetForPreset keeps all 132 intersections strictly inside viewport across all 4 presets and 8 sizes while preserving widescreen distances', () {
      const mapper = BoardCoordinateMapper();
      final sizes = <Size>[
        const Size(320, 568),
        const Size(390, 844),
        const Size(300, 800),
        const Size(600, 600),
        const Size(840, 800),
        const Size(900, 800),
        const Size(1280, 800),
        const Size(1920, 1080),
      ];

      final expectedWidescreenDistances = <OrbitCameraPreset, double>{
        OrbitCameraPreset.redCommander: 16.2,
        OrbitCameraPreset.blueCommander: 16.2,
        OrbitCameraPreset.tacticalTop: 17.5,
        OrbitCameraPreset.sideOverview: 17.8,
      };

      for (final size in sizes) {
        for (final preset in OrbitCameraPreset.values) {
          final target = Board3DViewport.cameraTargetForPreset(
            preset,
            viewportSize: size,
          );
          expect(target.distance.isFinite, isTrue);

          if (size == const Size(1280, 800) || size == const Size(1920, 1080)) {
            expect(
              target.distance,
              closeTo(expectedWidescreenDistances[preset]!, 1e-9),
              reason:
                  'Expected widescreen distance preserved at $size for ${preset.name}',
            );
          }

          final camera = SpringOrbitCamera3D(
            yaw: target.yaw,
            pitch: target.pitch,
            distance: target.distance,
            target: target.target,
          );
          final vp = camera.viewProjectionMatrix(size);

          var strictlyInsideCount = 0;
          for (var file = 0; file < BoardCoord.fileCount; file++) {
            for (var rank = 0; rank < BoardCoord.rankCount; rank++) {
              final world = mapper.coordToWorld(
                BoardCoord(file: file, rank: rank),
              );
              final clip = Vector4(world.x, world.y, world.z, 1.0);
              vp.transform(clip);
              expect(clip.w, greaterThan(0.0));
              final ndcX = clip.x / clip.w;
              final ndcY = clip.y / clip.w;
              final screenX = (ndcX * 0.5 + 0.5) * size.width;
              final screenY = (0.5 - ndcY * 0.5) * size.height;
              if (ndcX.abs() < 1.0 &&
                  ndcY.abs() < 1.0 &&
                  screenX > 0.0 &&
                  screenX < size.width &&
                  screenY > 0.0 &&
                  screenY < size.height) {
                strictlyInsideCount++;
              }
            }
          }
          expect(
            strictlyInsideCount,
            132,
            reason:
                'Expected all 132 intersections strictly inside $size for preset=${preset.name} (dist=${target.distance})',
          );
        }
      }
    });

    test('SpringOrbitCamera3D constructor sanitizes NaN, Infinity, and out-of-range parameters into finite viewProjectionMatrix and step()', () {
      final camera = SpringOrbitCamera3D(
        fovDegrees: double.nan,
        stiffness: double.nan,
        nearPlane: -1,
        farPlane: double.infinity,
        minDistance: 0,
        maxDistance: double.nan,
      );

      expect(camera.fovDegrees.isFinite, isTrue);
      expect(camera.fovDegrees, greaterThan(5.0));
      expect(camera.fovDegrees, lessThan(165.0));
      expect(camera.stiffness.isFinite, isTrue);
      expect(camera.stiffness, greaterThan(0.0));
      expect(camera.nearPlane.isFinite, isTrue);
      expect(camera.nearPlane, greaterThan(0.0));
      expect(camera.farPlane.isFinite, isTrue);
      expect(camera.farPlane, greaterThan(camera.nearPlane));
      expect(camera.minDistance.isFinite, isTrue);
      expect(camera.minDistance, greaterThan(0.0));
      expect(camera.maxDistance.isFinite, isTrue);
      expect(camera.maxDistance, greaterThanOrEqualTo(camera.minDistance));

      final initialVp = camera.viewProjectionMatrix(const Size(800, 600));
      for (var i = 0; i < 16; i++) {
        expect(
          initialVp.storage[i].isFinite,
          isTrue,
          reason: 'Initial viewProjectionMatrix[$i] must be finite',
        );
      }

      // Drive an active spring interpolation and verify step(0.016) remains finite.
      camera.animateToPreset(yaw: 0.5, pitch: 1.1, distance: 22.0);
      expect(camera.step(0.016), isTrue);
      expect(camera.yaw.isFinite, isTrue);
      expect(camera.pitch.isFinite, isTrue);
      expect(camera.distance.isFinite, isTrue);
      final eye = camera.eyePosition;
      expect(eye.x.isFinite && eye.y.isFinite && eye.z.isFinite, isTrue);

      final steppedVp = camera.viewProjectionMatrix(const Size(800, 600));
      for (var i = 0; i < 16; i++) {
        expect(
          steppedVp.storage[i].isFinite,
          isTrue,
          reason: 'Stepped viewProjectionMatrix[$i] must be finite',
        );
      }

      final groundHit = camera.unprojectRayToGroundPlane(
        const Offset(400, 300),
        const Size(800, 600),
      );
      expect(groundHit, isNotNull);
      expect(
        groundHit!.x.isFinite && groundHit.y.isFinite && groundHit.z.isFinite,
        isTrue,
      );

      // Also guard non-finite initial yaw/pitch/distance/target/pitch bounds.
      final extremeCamera = SpringOrbitCamera3D(
        yaw: double.nan,
        pitch: double.infinity,
        distance: double.negativeInfinity,
        target: Vector3(double.nan, double.infinity, double.negativeInfinity),
        minPitch: 0.0,
        maxPitch: 2.0,
      );
      expect(extremeCamera.step(0.016), isFalse);
      final extremeVp = extremeCamera.viewProjectionMatrix(const Size(600, 600));
      for (var i = 0; i < 16; i++) {
        expect(extremeVp.storage[i].isFinite, isTrue);
      }
    });

    for (final sizeEntry in <String, Size>{
      'small portrait 320x568': const Size(320, 568),
      'mobile portrait 390x844': const Size(390, 844),
    }.entries) {
      testWidgets('CommanderGameScreen renders cleanly at ${sizeEntry.key} and Board3DViewport picks corners a1 and k12', (tester) async {
        await configureViewport(tester, sizeEntry.value);

        // 1. Full CommanderGameScreen renders with zero layout overflow / exceptions.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [clockProvider.overrideWithValue(fixedClock)],
            child: MaterialApp(
              themeMode: ThemeMode.dark,
              theme: CommanderTheme.light(),
              darkTheme: CommanderTheme.dark(),
              home: const CommanderGameScreen(themeMode: ThemeMode.dark),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.takeException(), isNull);
        expect(find.byKey(CommanderGameScreen.viewportKey), findsOneWidget);

        await unmountTree(tester);

        // 2. Standalone Board3DViewport fits and picks extreme corners a1 & k12.
        late Board3DSceneController controller;
        final tapped = <BoardCoord>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [clockProvider.overrideWithValue(fixedClock)],
            child: MaterialApp(
              theme: CommanderTheme.dark(),
              home: Scaffold(
                body: Board3DViewport(
                  onCoordTapped: tapped.add,
                  onControllerCreated: (c) => controller = c,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.takeException(), isNull);

        final fittedTarget = Board3DViewport.cameraTargetForPreset(
          OrbitCameraPreset.redCommander,
          viewportSize: sizeEntry.value,
        );
        expect(controller.camera.distance, closeTo(fittedTarget.distance, 0.05));

        final a1 = BoardCoord.fromAlgebraic('a1');
        final k12 = BoardCoord.fromAlgebraic('k12');

        final a1Offset = _projectWorldWithTarget(
          target: fittedTarget,
          coord: a1,
          viewportSize: sizeEntry.value,
        );
        final k12Offset = _projectWorldWithTarget(
          target: fittedTarget,
          coord: k12,
          viewportSize: sizeEntry.value,
        );

        expect(
          Rect.fromLTWH(0, 0, sizeEntry.value.width, sizeEntry.value.height)
              .contains(a1Offset),
          isTrue,
        );
        expect(
          Rect.fromLTWH(0, 0, sizeEntry.value.width, sizeEntry.value.height)
              .contains(k12Offset),
          isTrue,
        );

        await tester.tapAt(a1Offset);
        await tester.pump();
        await tester.tapAt(k12Offset);
        await tester.pump();

        expect(tapped, <BoardCoord>[a1, k12]);

        await unmountTree(tester);
        expect(controller.isDisposed, isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('CommanderGameScreen at 320x568 has zero HUD occlusion across redCommander & tacticalTop and live tacticalTop g1 tap selects Red Commander', (tester) async {
      await configureViewport(tester, const Size(320, 568));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [clockProvider.overrideWithValue(fixedClock)],
          child: MaterialApp(
            themeMode: ThemeMode.dark,
            theme: CommanderTheme.light(),
            darkTheme: CommanderTheme.dark(),
            home: const CommanderGameScreen(themeMode: ThemeMode.dark),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);

      void expectZeroHudOcclusionForPreset(OrbitCameraPreset preset) {
        final viewportRect = tester.getRect(
          find.byKey(CommanderGameScreen.viewportKey),
        );
        expect(viewportRect.height, greaterThanOrEqualTo(180.0));

        final cardFinders = find.byType(Card);
        expect(cardFinders, findsNWidgets(2));
        final cardRects = <Rect>[
          for (var i = 0; i < 2; i++) tester.getRect(cardFinders.at(i)),
        ];
        for (final cardRect in cardRects) {
          expect(
            viewportRect.overlaps(cardRect),
            isFalse,
            reason:
                'Viewport $viewportRect must not overlap HUD card $cardRect in ${preset.name}',
          );
        }

        final target = Board3DViewport.cameraTargetForPreset(
          preset,
          viewportSize: viewportRect.size,
        );
        for (var file = 0; file < BoardCoord.fileCount; file++) {
          for (var rank = 0; rank < BoardCoord.rankCount; rank++) {
            final coord = BoardCoord(file: file, rank: rank);
            final screenPt = viewportRect.topLeft +
                _projectWorldWithTarget(
                  target: target,
                  coord: coord,
                  viewportSize: viewportRect.size,
                );
            expect(
              screenPt.dx > viewportRect.left &&
                  screenPt.dx < viewportRect.right &&
                  screenPt.dy > viewportRect.top &&
                  screenPt.dy < viewportRect.bottom,
              isTrue,
              reason:
                  'Intersection ${coord.toAlgebraic()} at $screenPt must lie strictly inside $viewportRect for ${preset.name}',
            );
            for (final cardRect in cardRects) {
              expect(
                cardRect.contains(screenPt),
                isFalse,
                reason:
                    'Intersection ${coord.toAlgebraic()} at $screenPt must not be occluded by $cardRect for ${preset.name}',
              );
            }
          }
        }
      }

      // 1. Verify initial redCommander preset has 0/132 HUD occlusion.
      expectZeroHudOcclusionForPreset(OrbitCameraPreset.redCommander);

      // 2. Switch live to tacticalTop and advance spring camera to settle.
      await tester.tap(
        find.byKey(CommanderGameScreen.cameraPresetKey(OrbitCameraPreset.tacticalTop)),
      );
      await tester.pump();
      final topChip = tester.widget<ChoiceChip>(
        find.byKey(CommanderGameScreen.cameraPresetKey(OrbitCameraPreset.tacticalTop)),
      );
      expect(topChip.selected, isTrue);

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expectZeroHudOcclusionForPreset(OrbitCameraPreset.tacticalTop);

      // 3. Tap projected g1 inside Board3DViewport (offset by viewport topLeft).
      final viewportRect = tester.getRect(
        find.byKey(CommanderGameScreen.viewportKey),
      );
      final tacticalTarget = Board3DViewport.cameraTargetForPreset(
        OrbitCameraPreset.tacticalTop,
        viewportSize: viewportRect.size,
      );
      final g1Coord = BoardCoord.fromAlgebraic('g1');
      final g1Screen = viewportRect.topLeft +
          _projectWorldWithTarget(
            target: tacticalTarget,
            coord: g1Coord,
            viewportSize: viewportRect.size,
          );
      expect(viewportRect.contains(g1Screen), isTrue);

      await tester.tapAt(g1Screen);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CommanderGameScreen)),
      );
      expect(container.read(gameSessionNotifierProvider).selectedCoord, g1Coord);
      expect(find.textContaining('Tư lệnh • Commander'), findsOneWidget);
      expect(find.text('g1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmountTree(tester);
      expect(tester.takeException(), isNull);
    });

    for (final themeEntry in <String, ThemeMode>{
      'light': ThemeMode.light,
      'dark': ThemeMode.dark,
    }.entries) {
      testWidgets('CommanderGameScreen at 320x568 with textScaler 1.4 renders in ${themeEntry.key} theme with zero RenderFlex overflow', (tester) async {
        await configureViewport(tester, const Size(320, 568));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [clockProvider.overrideWithValue(fixedClock)],
            child: MaterialApp(
              themeMode: themeEntry.value,
              theme: CommanderTheme.light(),
              darkTheme: CommanderTheme.dark(),
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.4),
                  ),
                  child: child!,
                );
              },
              home: CommanderGameScreen(themeMode: themeEntry.value),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.takeException(), isNull);

        final initialViewportRect = tester.getRect(
          find.byKey(CommanderGameScreen.viewportKey),
        );
        expect(initialViewportRect.height, greaterThanOrEqualTo(180.0));

        // Switch to tacticalTop and select g1 so both idle and selected HUD states
        // are exercised at textScaler 1.4x without RenderFlex overflow.
        await tester.tap(
          find.byKey(
            CommanderGameScreen.cameraPresetKey(OrbitCameraPreset.tacticalTop),
          ),
        );
        await tester.pump();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final viewportRect = tester.getRect(
          find.byKey(CommanderGameScreen.viewportKey),
        );
        final g1Coord = BoardCoord.fromAlgebraic('g1');
        final g1Screen = viewportRect.topLeft +
            _projectWorldWithTarget(
              target: Board3DViewport.cameraTargetForPreset(
                OrbitCameraPreset.tacticalTop,
                viewportSize: viewportRect.size,
              ),
              coord: g1Coord,
              viewportSize: viewportRect.size,
            );
        await tester.tapAt(g1Screen);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));

        expect(find.textContaining('Tư lệnh • Commander'), findsOneWidget);
        expect(find.text('g1'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await unmountTree(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
