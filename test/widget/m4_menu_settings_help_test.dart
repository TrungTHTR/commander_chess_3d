import 'package:commander_chess_3d/app.dart';
import 'package:commander_chess_3d/core/time/clock.dart';
import 'package:commander_chess_3d/features/game/engine/animation/camera_rig_3d.dart';
import 'package:commander_chess_3d/features/game/engine/world/board_3d_scene_state.dart';
import 'package:commander_chess_3d/features/game/models/board_coord.dart';
import 'package:commander_chess_3d/features/game/models/faction_model.dart';
import 'package:commander_chess_3d/features/game/models/game_state_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:commander_chess_3d/features/game/presentation/screens/commander_game_screen.dart';
import 'package:commander_chess_3d/features/game/presentation/screens/help_screen.dart';
import 'package:commander_chess_3d/features/game/presentation/screens/main_menu_screen.dart';
import 'package:commander_chess_3d/features/game/presentation/screens/settings_screen.dart';
import 'package:commander_chess_3d/features/game/presentation/theme/commander_theme.dart';
import 'package:commander_chess_3d/features/game/presentation/widgets/game_hud_overlay.dart';
import 'package:commander_chess_3d/features/game/repositories/settings_repository.dart';
import 'package:commander_chess_3d/features/game/state/game_hud_snapshot.dart';
import 'package:commander_chess_3d/features/game/state/game_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3, Vector4;

Offset _projectBoardCoordToScreen({
  required BoardCoord coord,
  required Size viewportSize,
  OrbitCameraPreset preset = OrbitCameraPreset.redCommander,
}) {
  const mapper = BoardCoordinateMapper();
  final target = switch (preset) {
    OrbitCameraPreset.redCommander => (yaw: 0.0, pitch: 0.86, distance: 16.2),
    OrbitCameraPreset.blueCommander => (
      yaw: 3.141592653589793,
      pitch: 0.86,
      distance: 16.2,
    ),
    OrbitCameraPreset.tacticalTop => (yaw: 0.0, pitch: 1.42, distance: 17.5),
    OrbitCameraPreset.sideOverview => (
      yaw: -3.141592653589793 / 2.6,
      pitch: 0.72,
      distance: 17.8,
    ),
  };
  final camera = SpringOrbitCamera3D(
    yaw: target.yaw,
    pitch: target.pitch,
    distance: target.distance,
    target: Vector3.zero(),
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
  final fixedClock = FixedClock(DateTime.utc(2026, 11, 22, 12, 0, 0));

  Future<void> configureViewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpRouteWith3DViewport(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 32));
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  Future<void> unmountTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('MainMenuScreen, Navigation & Platform-Safe Exit', () {
    testWidgets(
      'MainMenuScreen displays 4 core actions, matchup summary, and navigates Start -> Back to Menu',
      (tester) async {
        await configureViewport(tester, const Size(1280, 800));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [clockProvider.overrideWithValue(fixedClock)],
            child: const CommanderChessApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(MainMenuScreen), findsOneWidget);
        expect(find.byKey(MainMenuScreen.startButtonKey), findsOneWidget);
        expect(find.byKey(MainMenuScreen.settingsButtonKey), findsOneWidget);
        expect(find.byKey(MainMenuScreen.helpButtonKey), findsOneWidget);
        expect(find.byKey(MainMenuScreen.exitButtonKey), findsOneWidget);
        expect(find.textContaining('Vietnam (VN)'), findsOneWidget);
        expect(find.textContaining('United States (USA)'), findsOneWidget);
        expect(find.byKey(MainMenuScreen.mirrorMatchBadgeKey), findsNothing);

        // Start match -> CommanderGameScreen (avoid pumpAndSettle while 3D Ticker runs)
        await tester.tap(find.byKey(MainMenuScreen.startButtonKey));
        await pumpRouteWith3DViewport(tester);
        expect(find.byType(CommanderGameScreen), findsOneWidget);
        expect(find.text('Red (VN) • Turn 1'), findsOneWidget);

        // Back to Menu immediately when no moves have been made
        await tester.tap(find.byKey(CommanderGameScreen.backToMenuButtonKey));
        await tester.pumpAndSettle();
        expect(find.byType(MainMenuScreen), findsOneWidget);
        expect(find.byType(CommanderGameScreen), findsNothing);

        await unmountTree(tester);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Web-safe Exit shows confirmation, transitions to Session Ended, and Return to Menu restores menu',
      (tester) async {
        await configureViewport(tester, const Size(390, 844));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [clockProvider.overrideWithValue(fixedClock)],
            child: MaterialApp(
              theme: CommanderTheme.dark(),
              home: const MainMenuScreen(isWebPlatform: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Exit -> Cancel keeps menu
        await tapVisible(tester, find.byKey(MainMenuScreen.exitButtonKey));
        await tester.pumpAndSettle();
        expect(find.text('Exit Commander Chess 3D?'), findsOneWidget);
        await tester.tap(find.byKey(MainMenuScreen.cancelExitButtonKey));
        await tester.pumpAndSettle();
        expect(find.text('Session Ended'), findsNothing);
        expect(find.byKey(MainMenuScreen.startButtonKey), findsOneWidget);

        // Tap Exit -> Confirm transitions to Session Ended -> Return to Menu
        await tapVisible(tester, find.byKey(MainMenuScreen.exitButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(MainMenuScreen.confirmExitButtonKey));
        await tester.pumpAndSettle();

        expect(find.text('Session Ended'), findsOneWidget);
        expect(find.byKey(MainMenuScreen.returnToMenuButtonKey), findsOneWidget);

        await tester.tap(find.byKey(MainMenuScreen.returnToMenuButtonKey));
        await tester.pumpAndSettle();

        expect(find.text('Session Ended'), findsNothing);
        expect(find.byKey(MainMenuScreen.startButtonKey), findsOneWidget);

        await unmountTree(tester);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Non-Web Exit invokes injected exit callback after confirmation',
      (tester) async {
        await configureViewport(tester, const Size(390, 844));
        var exitCallCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [clockProvider.overrideWithValue(fixedClock)],
            child: MaterialApp(
              theme: CommanderTheme.dark(),
              home: MainMenuScreen(
                isWebPlatform: false,
                onExitApp: () async {
                  exitCallCount++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tapVisible(tester, find.byKey(MainMenuScreen.exitButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(MainMenuScreen.confirmExitButtonKey));
        await tester.pumpAndSettle();

        expect(exitCallCount, 1);

        await unmountTree(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('SettingsScreen, Faction Selection, Mirror Match & Theme Sync', () {
    testWidgets(
      'selects opposing factions across all 11 nations, supports Mirror Match, Swap Sides, hardware preview, camera preset & applies on Start',
      (tester) async {
        await configureViewport(tester, const Size(1280, 800));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [clockProvider.overrideWithValue(fixedClock)],
            child: const CommanderChessApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Open Settings
        await tester.tap(find.byKey(MainMenuScreen.settingsButtonKey));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);

        // Verify all 11 factions are present for both Red and Blue
        for (final faction in FactionId.values) {
          expect(
            find.byKey(SettingsScreen.redFactionChipKey(faction)),
            findsOneWidget,
          );
          expect(
            find.byKey(SettingsScreen.blueFactionChipKey(faction)),
            findsOneWidget,
          );
        }

        // Select Japan for Red and Germany for Blue
        await tapVisible(
          tester,
          find.byKey(SettingsScreen.redFactionChipKey(FactionId.japan)),
        );
        await tester.pump();

        await tapVisible(
          tester,
          find.byKey(SettingsScreen.blueFactionChipKey(FactionId.germany)),
        );
        await tester.pump();

        expect(find.textContaining('Type 10 Hitomaru'), findsOneWidget);
        expect(find.textContaining('Leopard 2A7'), findsOneWidget);
        expect(find.byKey(SettingsScreen.mirrorMatchBadgeKey), findsNothing);

        // Swap Sides -> Red=Germany, Blue=Japan
        await tapVisible(
          tester,
          find.byKey(SettingsScreen.swapFactionsButtonKey),
        );
        await tester.pump();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsScreen)),
        );
        expect(container.read(gameSettingsProvider).redFaction, FactionId.germany);
        expect(container.read(gameSettingsProvider).blueFaction, FactionId.japan);

        // Enable Mirror Match (Blue=Germany)
        await tapVisible(
          tester,
          find.byKey(SettingsScreen.blueFactionChipKey(FactionId.germany)),
        );
        await tester.pump();
        expect(find.byKey(SettingsScreen.mirrorMatchBadgeKey), findsOneWidget);

        // Change default camera preset to 'high' (tacticalTop)
        await tapVisible(
          tester,
          find.byKey(SettingsScreen.cameraPresetChipKey('high')),
        );
        await tester.pump();

        // Back to Main Menu -> verify Mirror Match badge & Start uses Germany vs Germany + tacticalTop
        await tester.tap(find.byKey(SettingsScreen.backButtonKey));
        await tester.pumpAndSettle();

        expect(find.byKey(MainMenuScreen.mirrorMatchBadgeKey), findsOneWidget);
        expect(find.textContaining('Germany (DE)'), findsNWidgets(2));

        await tester.tap(find.byKey(MainMenuScreen.startButtonKey));
        await pumpRouteWith3DViewport(tester);

        expect(find.text('Red (DE) • Turn 1'), findsOneWidget);
        expect(find.textContaining('Germany vs Germany (Mirror)'), findsOneWidget);
        final topChip = tester.widget<ChoiceChip>(
          find.byKey(
            CommanderGameScreen.cameraPresetKey(OrbitCameraPreset.tacticalTop),
          ),
        );
        expect(topChip.selected, isTrue);

        // Settle camera spring if animating and tap g1 on tacticalTop
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final viewportRect = tester.getRect(
          find.byKey(CommanderGameScreen.viewportKey),
        );
        final g1Screen = viewportRect.topLeft +
            _projectBoardCoordToScreen(
              coord: BoardCoord.fromAlgebraic('g1'),
              viewportSize: viewportRect.size,
              preset: OrbitCameraPreset.tacticalTop,
            );
        await tester.tapAt(g1Screen);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(
          find.textContaining('Generalinspekteur • Tư lệnh • Commander'),
          findsOneWidget,
        );
        expect(find.text('g1'), findsOneWidget);

        // Back to Menu, reset defaults in Settings, and verify defaults restored
        await tester.tap(find.byKey(CommanderGameScreen.backToMenuButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(MainMenuScreen.settingsButtonKey));
        await tester.pumpAndSettle();
        await tapVisible(
          tester,
          find.byKey(SettingsScreen.resetDefaultsButtonKey),
        );
        await tester.pumpAndSettle();

        expect(container.read(gameSettingsProvider), const GameSettings());

        await unmountTree(tester);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Bidirectional theme sync between SettingsScreen, CommanderGameScreen HUD, and async SettingsRepository hydration',
      (tester) async {
        await configureViewport(tester, const Size(1280, 800));
        final repo = InMemorySettingsRepository(
          initialSettings: const GameSettings(isDarkMode: false),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clockProvider.overrideWithValue(fixedClock),
              settingsRepositoryProvider.overrideWithValue(repo),
            ],
            child: const CommanderChessApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Hydrated from repository -> ThemeMode.light
        var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.themeMode, ThemeMode.light);

        // Toggle via SettingsScreen -> Dark mode
        await tester.tap(find.byKey(MainMenuScreen.settingsButtonKey));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byKey(SettingsScreen.darkModeSwitchKey));
        await tester.pumpAndSettle();

        app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.themeMode, ThemeMode.dark);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsScreen)),
        );
        expect(container.read(gameSettingsProvider).isDarkMode, isTrue);

        // Return and enter game -> toggle via HUD -> persists back to gameSettingsProvider & repo
        await tester.tap(find.byKey(SettingsScreen.backButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(MainMenuScreen.startButtonKey));
        await pumpRouteWith3DViewport(tester);

        await tester.tap(find.byKey(CommanderGameScreen.themeToggleButtonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));

        app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.themeMode, ThemeMode.light);
        expect(container.read(gameSettingsProvider).isDarkMode, isFalse);

        final persisted = await repo.loadSettings();
        expect(persisted.valueOrNull?.isDarkMode, isFalse);

        await unmountTree(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('HelpScreen Documentation & Navigation', () {
    testWidgets(
      'HelpScreen displays all 5 tabs including 11x12 terrain, 19/side units, LoS rules, 3D controls, and 11-faction catalog',
      (tester) async {
        await configureViewport(tester, const Size(1280, 800));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [clockProvider.overrideWithValue(fixedClock)],
            child: const CommanderChessApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(MainMenuScreen.helpButtonKey));
        await tester.pumpAndSettle();
        expect(find.byType(HelpScreen), findsOneWidget);

        // Tab 1: Board & Terrain
        expect(find.textContaining('11×12 Tactical Grid'), findsOneWidget);
        expect(
          find.text('River (Sông) & Shallow Fords (Ngầm)'),
          findsOneWidget,
        );
        expect(find.textContaining('f6↔f7'), findsOneWidget);

        // Tab 2: Units (19/Side)
        await tester.tap(find.byKey(HelpScreen.unitsTabKey));
        await tester.pumpAndSettle();
        expect(find.textContaining('19 Pieces per Side'), findsOneWidget);
        expect(find.textContaining('Tư lệnh • Commander'), findsOneWidget);

        // Tab 3: Rules & Victory
        await tester.tap(find.byKey(HelpScreen.rulesTabKey));
        await tester.pumpAndSettle();
        expect(find.textContaining('Commander Capture'), findsOneWidget);
        expect(find.textContaining('Flying General'), findsOneWidget);

        // Tab 4: 3D Controls
        await tester.tap(find.byKey(HelpScreen.controlsTabKey));
        await tester.pumpAndSettle();
        expect(find.textContaining('3D Tabletop Interaction'), findsOneWidget);
        expect(find.textContaining('Camera Presets'), findsOneWidget);

        // Tab 5: 11 Factions
        await tester.tap(find.byKey(HelpScreen.factionsTabKey));
        await tester.pumpAndSettle();
        expect(find.textContaining('United States (USA)'), findsOneWidget);

        final factionsScrollable = find
            .descendant(
              of: find.byType(TabBarView),
              matching: find.byType(Scrollable),
            )
            .last;

        await tester.scrollUntilVisible(
          find.textContaining('Vietnam (VN)'),
          300,
          scrollable: factionsScrollable,
        );
        expect(find.textContaining('Vietnam (VN)'), findsOneWidget);

        // Scroll to verify bottom faction in catalog
        await tester.scrollUntilVisible(
          find.textContaining('Israel (IL)'),
          300,
          scrollable: factionsScrollable,
        );
        expect(find.textContaining('Israel (IL)'), findsOneWidget);

        // Back returns to MainMenuScreen
        await tester.tap(find.byKey(HelpScreen.backButtonKey));
        await tester.pumpAndSettle();
        expect(find.byType(MainMenuScreen), findsOneWidget);

        await unmountTree(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('In-Game Back to Menu Confirmation & Rematch Flow', () {
    testWidgets(
      'prompts Leave Active Match confirmation when moves exist and returns cleanly after confirm or idle',
      (tester) async {
        const viewportSize = Size(1280, 800);
        await configureViewport(tester, viewportSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [clockProvider.overrideWithValue(fixedClock)],
            child: const CommanderChessApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(MainMenuScreen.startButtonKey));
        await pumpRouteWith3DViewport(tester);

        // Execute g5 -> g6 move so moveHistory is non-empty
        final viewportRect = tester.getRect(
          find.byKey(CommanderGameScreen.viewportKey),
        );
        await tester.tapAt(
          viewportRect.topLeft +
              _projectBoardCoordToScreen(
                coord: BoardCoord.fromAlgebraic('g5'),
                viewportSize: viewportRect.size,
              ),
        );
        await tester.pump();
        await tester.tapAt(
          viewportRect.topLeft +
              _projectBoardCoordToScreen(
                coord: BoardCoord.fromAlgebraic('g6'),
                viewportSize: viewportRect.size,
              ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(find.text('Blue (USA) • Turn 2'), findsOneWidget);

        // Back to Menu prompts confirmation -> Cancel stays on game screen
        await tester.tap(find.byKey(CommanderGameScreen.backToMenuButtonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Leave Active Match?'), findsOneWidget);
        await tester.tap(
          find.byKey(CommanderGameScreen.cancelBackToMenuButtonKey),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(CommanderGameScreen), findsOneWidget);

        // Back to Menu -> Confirm returns to MainMenuScreen
        await tester.tap(find.byKey(CommanderGameScreen.backToMenuButtonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Leave Active Match?'), findsOneWidget);
        await tester.tap(
          find.byKey(CommanderGameScreen.confirmBackToMenuButtonKey),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MainMenuScreen), findsOneWidget);

        // Start a fresh match -> moveHistory empty -> Back to Menu pops immediately
        await tester.tap(find.byKey(MainMenuScreen.startButtonKey));
        await pumpRouteWith3DViewport(tester);
        await tester.tap(find.byKey(CommanderGameScreen.backToMenuButtonKey));
        await tester.pumpAndSettle();
        expect(find.byType(MainMenuScreen), findsOneWidget);

        await unmountTree(tester);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'GameHudOverlay displays Rematch when MatchPhase.finished and invokes onNewMatch',
      (tester) async {
        await configureViewport(tester, const Size(1280, 800));
        var rematchCount = 0;

        final finishedSession = GameSessionState(
          matchId: 'finished_match',
          mode: GameMode.localPassAndPlay,
          currentTurn: PlayerSide.red,
          phase: MatchPhase.finished,
          winner: PlayerSide.red,
          victoryReason: VictoryReason.commanderCaptured,
          redFaction: FactionId.usa,
          blueFaction: FactionId.israel,
          pieces: <PieceEntity>[
            PieceEntity(
              id: 'red_commander',
              side: PlayerSide.red,
              type: PieceType.commander,
              position: BoardCoord.fromAlgebraic('g1'),
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: CommanderTheme.dark(),
            home: Scaffold(
              body: GameHudOverlay(
                hud: GameHudSnapshot(
                  session: finishedSession,
                  statusMessage: 'Victory: Red wins!',
                ),
                themeMode: ThemeMode.dark,
                onUndo: () {},
                onNewMatch: () {
                  rematchCount++;
                },
                onToggleTheme: () {},
                onSelectCameraPreset: (_) {},
                onDismissError: () {},
                onBackToMenu: () {},
                viewport: const SizedBox.expand(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Rematch'), findsOneWidget);
        expect(find.text('Red (USA) • Turn 1'), findsOneWidget);
        expect(find.textContaining('United States vs Israel'), findsOneWidget);

        await tester.tap(find.byKey(GameHudOverlay.newMatchButtonKey));
        await tester.pump();
        expect(rematchCount, 1);

        await unmountTree(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Compact 320x568 @ 1.4x TextScaler Light & Dark Responsiveness', () {
    for (final themeEntry in <String, ThemeMode>{
      'light': ThemeMode.light,
      'dark': ThemeMode.dark,
    }.entries) {
      testWidgets(
        'MainMenuScreen, Session Ended, SettingsScreen, and all 5 HelpScreen tabs render with zero overflow at 320x568 @ 1.4x in ${themeEntry.key} theme',
        (tester) async {
          await configureViewport(tester, const Size(320, 568));
          final isDark = themeEntry.value == ThemeMode.dark;
          final repo = InMemorySettingsRepository(
            initialSettings: GameSettings(
              isDarkMode: isDark,
              redFaction: FactionId.sovietUnion,
              blueFaction: FactionId.sovietUnion,
            ),
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                clockProvider.overrideWithValue(fixedClock),
                settingsRepositoryProvider.overrideWithValue(repo),
              ],
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
                home: const MainMenuScreen(isWebPlatform: true),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Open Settings at 320x568 @ 1.4x
          await tapVisible(
            tester,
            find.byKey(MainMenuScreen.settingsButtonKey),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SettingsScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(SettingsScreen.backButtonKey));
          await tester.pumpAndSettle();

          // Open Help and visit all 5 tabs at 320x568 @ 1.4x
          await tapVisible(tester, find.byKey(MainMenuScreen.helpButtonKey));
          await tester.pumpAndSettle();
          expect(find.byType(HelpScreen), findsOneWidget);
          expect(tester.takeException(), isNull);

          for (final tabKey in <Key>[
            HelpScreen.unitsTabKey,
            HelpScreen.rulesTabKey,
            HelpScreen.controlsTabKey,
            HelpScreen.factionsTabKey,
          ]) {
            await tapVisible(tester, find.byKey(tabKey));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }

          await tester.tap(find.byKey(HelpScreen.backButtonKey));
          await tester.pumpAndSettle();

          // Web Exit dialog & Session Ended at 320x568 @ 1.4x
          await tapVisible(tester, find.byKey(MainMenuScreen.exitButtonKey));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.tap(find.byKey(MainMenuScreen.confirmExitButtonKey));
          await tester.pumpAndSettle();
          expect(find.text('Session Ended'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await unmountTree(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final themeEntry in <String, ThemeMode>{
      'light': ThemeMode.light,
      'dark': ThemeMode.dark,
    }.entries) {
      testWidgets(
        'SettingsScreen full-scroll Unit Hardware Preview has zero RenderFlex overflow at 320x568 @ 1.6x in ${themeEntry.key} theme',
        (tester) async {
          await configureViewport(tester, const Size(320, 568));
          final isDark = themeEntry.value == ThemeMode.dark;
          final repo = InMemorySettingsRepository(
            initialSettings: GameSettings(
              isDarkMode: isDark,
              redFaction: FactionId.southKorea,
              blueFaction: FactionId.sovietUnion,
            ),
          );

          final capturedErrors = <FlutterErrorDetails>[];
          final previousOnError = FlutterError.onError;
          FlutterError.onError = (details) {
            capturedErrors.add(details);
          };
          addTearDown(() {
            FlutterError.onError = previousOnError;
          });

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                clockProvider.overrideWithValue(fixedClock),
                settingsRepositoryProvider.overrideWithValue(repo),
              ],
              child: MaterialApp(
                themeMode: themeEntry.value,
                theme: CommanderTheme.light(),
                darkTheme: CommanderTheme.dark(),
                builder: (context, child) {
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(1.6),
                    ),
                    child: child!,
                  );
                },
                home: const SettingsScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final aaFinder = find.text('Anti-Aircraft');
          expect(aaFinder, findsNWidgets(2));
          for (var i = 0; i < 2; i++) {
            final aaSize = tester.getSize(aaFinder.at(i));
            expect(aaSize.width, greaterThan(0));
          }

          final settingsScrollable = find.byType(Scrollable).first;
          // Scroll incrementally through the entire ListView down to Done.
          for (var step = 0; step < 30; step++) {
            final scrollState = tester.state<ScrollableState>(
              settingsScrollable,
            );
            if (scrollState.position.pixels >=
                scrollState.position.maxScrollExtent) {
              break;
            }
            await tester.drag(settingsScrollable, const Offset(0, -250));
            await tester.pump();
          }

          await tester.ensureVisible(find.byKey(SettingsScreen.doneButtonKey));
          await tester.pumpAndSettle();

          expect(find.byKey(SettingsScreen.doneButtonKey), findsOneWidget);
          expect(
            capturedErrors,
            isEmpty,
            reason: capturedErrors
                .map((e) => e.exceptionAsString())
                .join('\n---\n'),
          );
          expect(tester.takeException(), isNull);

          await unmountTree(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
