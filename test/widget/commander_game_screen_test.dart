import 'package:commander_chess_3d/app.dart';
import 'package:commander_chess_3d/core/time/clock.dart';
import 'package:commander_chess_3d/features/game/engine/animation/camera_rig_3d.dart';
import 'package:commander_chess_3d/features/game/engine/assets/piece_asset_provider.dart';
import 'package:commander_chess_3d/features/game/engine/loop/board_3d_scene_controller.dart';
import 'package:commander_chess_3d/features/game/engine/render/placeholder_3d_board_renderer.dart';
import 'package:commander_chess_3d/features/game/engine/shaders/board_shader_handle.dart';
import 'package:commander_chess_3d/features/game/engine/world/board_3d_scene_state.dart';
import 'package:commander_chess_3d/features/game/models/asset_manifest_model.dart';
import 'package:commander_chess_3d/features/game/models/board_coord.dart';
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

Offset _projectBoardCoordToScreen({
  required BoardCoord coord,
  required Size viewportSize,
}) {
  const mapper = BoardCoordinateMapper();
  // Matches OrbitCameraPreset.redCommander defaults in Board3DViewport.
  final camera = SpringOrbitCamera3D(
    yaw: 0.0,
    pitch: 0.86,
    distance: 16.2,
    target: Vector3.zero(),
  );
  final world = mapper.coordToWorld(coord);
  final vp = camera.viewProjectionMatrix(viewportSize);
  final clip = Vector4(world.x, world.y, world.z, 1.0);
  vp.transform(clip);
  final invW = 1.0 / clip.w;
  final ndcX = clip.x * invW;
  final ndcY = clip.y * invW;
  return Offset(
    (ndcX * 0.5 + 0.5) * viewportSize.width,
    (0.5 - ndcY * 0.5) * viewportSize.height,
  );
}

void main() {
  final fixedClock = FixedClock(DateTime.utc(2026, 11, 20, 17, 0, 0));

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

  group('CommanderGameScreen responsive & theme matrix', () {
    for (final entry in <String, Size>{
      'mobile 390x844': const Size(390, 844),
      'desktop 1280x800': const Size(1280, 800),
    }.entries) {
      for (final themeEntry in <String, ThemeMode>{
        'light': ThemeMode.light,
        'dark': ThemeMode.dark,
      }.entries) {
        testWidgets(
          'renders ${entry.key} in ${themeEntry.key} theme with RepaintBoundary + CustomPaint and zero overflow',
          (tester) async {
            await configureViewport(tester, entry.value);

            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  clockProvider.overrideWithValue(fixedClock),
                ],
                child: MaterialApp(
                  themeMode: themeEntry.value,
                  theme: CommanderTheme.light(),
                  darkTheme: CommanderTheme.dark(),
                  home: CommanderGameScreen(themeMode: themeEntry.value),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 32));

            expect(tester.takeException(), isNull);
            expect(find.byType(CommanderGameScreen), findsOneWidget);
            expect(find.byKey(CommanderGameScreen.viewportKey), findsOneWidget);
            expect(find.text('Commander Chess 3D • Cờ Tư Lệnh'), findsOneWidget);
            expect(find.text('Red • Turn 1'), findsOneWidget);

            // Verify RepaintBoundary + CustomPaint(Board3DCustomPainter) inside Board3DViewport.
            final viewportFinder = find.byKey(CommanderGameScreen.viewportKey);
            final customPaintFinder = find.descendant(
              of: viewportFinder,
              matching: find.byType(CustomPaint),
            );
            expect(customPaintFinder, findsOneWidget);

            final customPaint = tester.widget<CustomPaint>(customPaintFinder);
            expect(customPaint.painter, isA<Board3DCustomPainter>());

            final repaintBoundaryFinder = find.ancestor(
              of: customPaintFinder,
              matching: find.byType(RepaintBoundary),
            );
            expect(repaintBoundaryFinder, findsWidgets);

            await unmountTree(tester);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('CommanderChessApp HUD controls & 3D viewport interactions', () {
    testWidgets('supports theme toggle, camera presets, 3D tap selection/move, Undo, and New Match', (tester) async {
      const viewportSize = Size(1280, 800);
      await configureViewport(tester, viewportSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [clockProvider.overrideWithValue(fixedClock)],
          child: const CommanderChessApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      expect(tester.takeException(), isNull);

      // Initially Dark mode in CommanderChessApp.
      var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);

      // Toggle theme -> Light mode.
      await tester.tap(find.byKey(CommanderGameScreen.themeToggleButtonKey));
      await tester.pump();
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.light);

      // Switch camera presets and verify ChoiceChip selection state.
      for (final preset in <OrbitCameraPreset>[
        OrbitCameraPreset.tacticalTop,
        OrbitCameraPreset.blueCommander,
        OrbitCameraPreset.sideOverview,
        OrbitCameraPreset.redCommander,
      ]) {
        await tester.tap(find.byKey(CommanderGameScreen.cameraPresetKey(preset)));
        await tester.pump();
        final chip = tester.widget<ChoiceChip>(
          find.byKey(CommanderGameScreen.cameraPresetKey(preset)),
        );
        expect(chip.selected, isTrue);
      }

      // Tap Red Militia at g5 projected in 3D viewport -> selects g5 & shows HUD info.
      final g5Screen = _projectBoardCoordToScreen(
        coord: BoardCoord.fromAlgebraic('g5'),
        viewportSize: viewportSize,
      );
      await tester.tapAt(g5Screen);
      await tester.pump();

      expect(find.textContaining('Dân quân • Militia'), findsOneWidget);
      expect(find.text('g5'), findsOneWidget);

      // Tap legal destination g6 projected in 3D viewport -> executes move!
      final g6Screen = _projectBoardCoordToScreen(
        coord: BoardCoord.fromAlgebraic('g6'),
        viewportSize: viewportSize,
      );
      await tester.tapAt(g6Screen);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      expect(find.text('Blue • Turn 2'), findsOneWidget);
      expect(find.text('Blue to move'), findsOneWidget);

      // Tap Undo -> rolls back to Red Turn 1.
      await tester.tap(find.byKey(CommanderGameScreen.undoButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.text('Red • Turn 1'), findsOneWidget);

      // Make move again, then tap New Match -> resets to fresh Turn 1.
      await tester.tapAt(g5Screen);
      await tester.pump();
      await tester.tapAt(g6Screen);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.text('Blue • Turn 2'), findsOneWidget);

      await tester.tap(find.byKey(CommanderGameScreen.newMatchButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.text('Red • Turn 1'), findsOneWidget);
      expect(find.text('Red to move'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmountTree(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('integrates ProceduralPieceAssetProvider + Placeholder3DBoardRenderer and disposes controller cleanly on unmount', (tester) async {
      const viewportSize = Size(1280, 800);
      await configureViewport(tester, viewportSize);

      late Board3DSceneController capturedController;
      final provider = ProceduralPieceAssetProvider();
      final shaderHandle = BoardShaderHandle();
      final renderer = Placeholder3DBoardRenderer(
        assetProvider: provider,
        shaderHandle: shaderHandle,
      );
      final tappedCoords = <BoardCoord>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [clockProvider.overrideWithValue(fixedClock)],
          child: MaterialApp(
            theme: CommanderTheme.dark(),
            home: Scaffold(
              body: Board3DViewport(
                onCoordTapped: tappedCoords.add,
                assetProviderFactory: () => provider,
                shaderHandleFactory: () => shaderHandle,
                rendererFactory: (_, _) => renderer,
                onControllerCreated: (controller) {
                  capturedController = controller;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      expect(capturedController.isDisposed, isFalse);
      expect(capturedController.snapshot.tiles, hasLength(132));
      expect(capturedController.snapshot.pieces, hasLength(38));

      final resolvedHandle = provider.resolvePiece(
        const PieceVisualKey(
          type: PieceType.commander,
          side: PlayerSide.red,
          isHero: true,
        ),
      );
      expect(resolvedHandle.isGlbBacked, isFalse);
      expect(resolvedHandle, isA<ProceduralPieceVisualHandle>());

      // Verify tap hit-test delivers exact BoardCoord through Board3DViewport.
      final g5Screen = _projectBoardCoordToScreen(
        coord: BoardCoord.fromAlgebraic('g5'),
        viewportSize: viewportSize,
      );
      await tester.tapAt(g5Screen);
      await tester.pump();
      expect(tappedCoords, <BoardCoord>[BoardCoord.fromAlgebraic('g5')]);

      // Unmount widget tree and verify deterministic controller disposal.
      await unmountTree(tester);
      expect(capturedController.isDisposed, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
