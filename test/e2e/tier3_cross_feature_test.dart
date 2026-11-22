import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'e2e_test_helpers.dart';

void main() {
  String readPieceTitle(
    WidgetTester tester,
    Rect viewportRect,
    PieceType type,
  ) {
    return readPiecePanelSummaryFromBottomHud(tester, viewportRect, type);
  }

  group('Tier 3 — Cross-Feature Pairwise Workflows', () {
    testWidgets('T3-01: Settings -> Start -> HUD -> Move -> Undo -> Rematch preserves United Kingdom vs France', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'United Kingdom');
      await selectFactionForSide(tester, PlayerSide.blue, 'France');
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);
      final topBefore = readTopHudText(tester, viewportRect);
      expect(topBefore, anyOf(contains('United Kingdom'), contains('UK')));
      expect(topBefore, anyOf(contains('France'), contains('FR')));

      await tapBoardCoord(tester, 'g1');
      final ukCommander = readPieceTitle(
        tester,
        viewportRect,
        PieceType.commander,
      );
      expect(ukCommander, contains('Tư lệnh • Commander'));

      await playMove(tester, 'g5', 'g6');
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));

      await tapHudUndo(tester);
      expect(readTopHudText(tester, viewportRect), contains('Turn 1'));
      await tapBoardCoord(tester, 'g5');
      expect(readBottomHudText(tester, viewportRect), contains('g5'));

      await tapBoardCoord(tester, 'g6');
      await pumpFrames(tester, count: 6);
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));

      await tapHudRematch(tester);
      expect(readTopHudText(tester, viewportRect), contains('Turn 1'));
      final topAfterRematch = readTopHudText(tester, viewportRect);
      expect(
        topAfterRematch,
        anyOf(contains('United Kingdom'), contains('UK')),
      );
      expect(topAfterRematch, anyOf(contains('France'), contains('FR')));

      await unmountApp(tester);
    });

    testWidgets('T3-02: Swap Sides switches Side 1 and Side 2 unit designations accurately', (
      tester,
    ) async {
      await pumpApp(tester);

      // Baseline: Vietnam (Side 1) vs United States (Side 2).
      await tapMenuOption(tester, 'Start');
      final viewport1 = findBoardViewportRect(tester);
      await tapBoardCoord(tester, 'g1');
      final vnRedCommander = readPieceTitle(
        tester,
        viewport1,
        PieceType.commander,
      );
      await playMove(tester, 'g5', 'g6');
      await tapBoardCoord(tester, 'g12');
      final usBlueCommander = readPieceTitle(
        tester,
        viewport1,
        PieceType.commander,
      );
      expect(vnRedCommander, isNot(equals(usBlueCommander)));
      await navigateBackToMenuFromGame(tester, confirm: true);

      // Swap in Settings -> United States (Side 1) vs Vietnam (Side 2).
      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'Vietnam');
      await selectFactionForSide(tester, PlayerSide.blue, 'United States');
      await tapSwapFactionsInSettings(tester);
      await navigateBackFromSubscreen(tester);

      final menuText = readAllVisibleText(tester);
      expect(menuText, contains('United States'));
      expect(menuText, contains('Vietnam'));

      await tapMenuOption(tester, 'Start');
      final viewport2 = findBoardViewportRect(tester);
      await tapBoardCoord(tester, 'g1');
      final swappedRedCommander = readPieceTitle(
        tester,
        viewport2,
        PieceType.commander,
      );
      expect(swappedRedCommander, equals(usBlueCommander));

      await playMove(tester, 'g5', 'g6');
      await tapBoardCoord(tester, 'g12');
      final swappedBlueCommander = readPieceTitle(
        tester,
        viewport2,
        PieceType.commander,
      );
      expect(swappedBlueCommander, equals(vnRedCommander));

      await unmountApp(tester);
    });

    testWidgets('T3-03: Theme persistence flows across Settings, Menu, and In-Game HUD toggle', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(readActiveBrightness(tester), Brightness.dark);

      await tapMenuOption(tester, 'Settings');
      await selectSettingsThemeMode(tester, ThemeMode.light);
      await navigateBackFromSubscreen(tester);
      expect(readActiveBrightness(tester), Brightness.light);

      await tapMenuOption(tester, 'Start');
      expect(readActiveBrightness(tester), Brightness.light);

      await tapHudThemeToggle(tester);
      expect(readActiveBrightness(tester), Brightness.dark);

      await navigateBackToMenuFromGame(tester, confirm: true);
      expect(readActiveBrightness(tester), Brightness.dark);

      await tapMenuOption(tester, 'Settings');
      expect(readActiveBrightness(tester), Brightness.dark);

      await unmountApp(tester);
    });

    testWidgets('T3-04: Help -> Settings (China vs India, tacticalTop) -> Start activates tacticalTop & Chinese Commander', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Help');
      final helpText = await collectHelpScreenText(tester);
      expect(helpText, contains('China'));
      expect(helpText, contains('India'));
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'China');
      await selectFactionForSide(tester, PlayerSide.blue, 'India');
      await selectSettingsCameraPreset(tester, E2ECameraPreset.tacticalTop);
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      final topChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey<String>('hud_camera_tacticalTop')),
      );
      expect(topChip.selected, isTrue);

      final viewportRect = findBoardViewportRect(tester);
      final topText = readTopHudText(tester, viewportRect);
      expect(topText, anyOf(contains('China'), contains('CN')));
      expect(topText, anyOf(contains('India'), contains('IN')));

      await tapBoardCoord(
        tester,
        'g1',
        preset: E2ECameraPreset.tacticalTop,
      );
      final bottomText = readBottomHudText(tester, viewportRect);
      expect(bottomText, contains('g1'));
      expect(bottomText, contains('Tư lệnh • Commander'));

      await unmountApp(tester);
    });

    testWidgets('T3-05: Mirror Match (South Korea vs South Korea) -> Moves -> Undo -> Rematch', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'South Korea');
      await selectFactionForSide(tester, PlayerSide.blue, 'South Korea');
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);

      await playMove(tester, 'g5', 'g6');
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));
      expect(readTopHudText(tester, viewportRect), contains('Blue'));

      await playMove(tester, 'g8', 'g7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 3'));
      expect(readTopHudText(tester, viewportRect), contains('Red'));

      await tapHudUndo(tester);
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));
      expect(readTopHudText(tester, viewportRect), contains('Blue'));
      await tapBoardCoord(tester, 'g8');
      expect(readBottomHudText(tester, viewportRect), contains('g8'));

      await tapHudRematch(tester);
      expect(readTopHudText(tester, viewportRect), contains('Turn 1'));
      expect(readTopHudText(tester, viewportRect), contains('Red'));
      final rematchTop = readTopHudText(tester, viewportRect);
      expect(rematchTop, anyOf(contains('South Korea'), contains('KR')));

      await unmountApp(tester);
    });

    testWidgets('T3-06: Reconfigure Germany vs Israel -> Reset Defaults restores Vietnam vs United States', (
      tester,
    ) async {
      await pumpApp(tester);

      // Record default Vietnam g1 Commander designation first.
      await tapMenuOption(tester, 'Start');
      final viewportDefault = findBoardViewportRect(tester);
      await tapBoardCoord(tester, 'g1');
      final defaultVnCommander = readPieceTitle(
        tester,
        viewportDefault,
        PieceType.commander,
      );
      await navigateBackToMenuFromGame(tester, confirm: true);

      // Reconfigure to Germany vs Israel, then Reset Defaults.
      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'Germany');
      await selectFactionForSide(tester, PlayerSide.blue, 'Israel');
      await tapResetDefaultsInSettings(tester);
      await navigateBackFromSubscreen(tester);

      final menuText = readAllVisibleText(tester);
      expect(menuText, contains('Vietnam'));
      expect(menuText, contains('United States'));

      await tapMenuOption(tester, 'Start');
      final viewportAfterReset = findBoardViewportRect(tester);
      await tapBoardCoord(tester, 'g1');
      final resetCommander = readPieceTitle(
        tester,
        viewportAfterReset,
        PieceType.commander,
      );
      expect(resetCommander, equals(defaultVnCommander));

      await unmountApp(tester);
    });
  });
}
