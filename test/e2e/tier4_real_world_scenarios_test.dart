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

  group('Tier 4 — Real-World Multi-Turn Player Scenarios', () {
    testWidgets('T4-01: Vietnam vs United States classic opening and Militia capture', (
      tester,
    ) async {
      await pumpApp(tester);
      expectOnMainMenu(tester);

      final menuText = readAllVisibleText(tester);
      expect(menuText, contains('Vietnam'));
      expect(menuText, contains('United States'));

      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);
      expect(readTopHudText(tester, viewportRect), contains('Turn 1'));

      // Inspect Red Commander & Red Militia, then advance g5 -> g6.
      await tapBoardCoord(tester, 'g1');
      expect(readBottomHudText(tester, viewportRect), contains('Tư lệnh • Commander'));
      await tapBoardCoord(tester, 'g5');
      expect(readBottomHudText(tester, viewportRect), contains('Militia'));

      await tapBoardCoord(tester, 'g6');
      await pumpFrames(tester, count: 6);
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));

      // Inspect Blue Militia at g8 and advance g8 -> g7.
      await tapBoardCoord(tester, 'g8');
      expect(readBottomHudText(tester, viewportRect), contains('Militia'));
      await tapBoardCoord(tester, 'g7');
      await pumpFrames(tester, count: 6);
      expect(readTopHudText(tester, viewportRect), contains('Turn 3'));

      // Red Militia captures Blue Militia g6 -> g7.
      await playMove(tester, 'g6', 'g7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 4'));

      // On Turn 4 (Blue), g7 holds Red Militia so Blue cannot select g7; Blue Tank advances h9 -> h7.
      await tapBoardCoord(tester, 'g7');
      expect(readBottomHudText(tester, viewportRect), contains('Drag to orbit'));
      expect(readBottomHudText(tester, viewportRect), isNot(contains('g7')));
      await playMove(tester, 'h9', 'h7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 5'));

      // On Turn 5 (Red), Red Militia is verified alive at g7.
      await tapBoardCoord(tester, 'g7');
      final g7Hud = readBottomHudText(tester, viewportRect);
      expect(g7Hud, contains('g7'));
      expect(g7Hud, contains('Militia'));

      await unmountApp(tester);
    });

    testWidgets('T4-02: Soviet Union vs Germany armored Tank clash across river', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'Soviet Union');
      await selectFactionForSide(tester, PlayerSide.blue, 'Germany');
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);
      final topText = readTopHudText(tester, viewportRect);
      expect(topText, anyOf(contains('Soviet Union'), contains('USSR')));
      expect(topText, anyOf(contains('Germany'), contains('DE')));

      // Inspect Soviet Tank f4 and advance 2 steps f4 -> f6.
      await tapBoardCoord(tester, 'f4');
      expect(readBottomHudText(tester, viewportRect), contains('Tank'));
      await tapBoardCoord(tester, 'f6');
      await pumpFrames(tester, count: 6);
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));

      // German Tank advances 2 steps f9 -> f7.
      await playMove(tester, 'f9', 'f7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 3'));

      // Soviet Tank captures German Tank across ford f6 -> f7.
      await playMove(tester, 'f6', 'f7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 4'));

      // German Militia counter-captures diagonally g8 -> f7.
      await playMove(tester, 'g8', 'f7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 5'));

      await unmountApp(tester);
    });

    testWidgets('T4-03: Mirror match Vietnam vs Vietnam disambiguation, capture, and Undo', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'Vietnam');
      await selectFactionForSide(tester, PlayerSide.blue, 'Vietnam');
      expect(readAllVisibleText(tester).toLowerCase(), contains('mirror'));
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);
      expect(readTopHudText(tester, viewportRect), contains('Red'));

      // Infantry clash along mixed coast c-file: c5 -> c6, c8 -> c7, c6 -> c7.
      await playMove(tester, 'c5', 'c6');
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));
      expect(readTopHudText(tester, viewportRect), contains('Blue'));

      await playMove(tester, 'c8', 'c7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 3'));
      expect(readTopHudText(tester, viewportRect), contains('Red'));

      await playMove(tester, 'c6', 'c7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 4'));

      // Undo capture -> back to Turn 3 with Red c6 and Blue c7 restored.
      await tapHudUndo(tester);
      expect(readTopHudText(tester, viewportRect), contains('Turn 3'));
      await tapBoardCoord(tester, 'c6');
      expect(readBottomHudText(tester, viewportRect), contains('c6'));
      expect(readBottomHudText(tester, viewportRect), contains('Infantry'));

      // Replay capture c6 -> c7 cleanly.
      await tapBoardCoord(tester, 'c7');
      await pumpFrames(tester, count: 6);
      expect(readTopHudText(tester, viewportRect), contains('Turn 4'));

      await unmountApp(tester);
    });

    testWidgets('T4-04: Mid-session exit and reconfigure to Japan vs South Korea', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Start');
      final viewport1 = findBoardViewportRect(tester);
      await tapBoardCoord(tester, 'g1');
      final defaultVnCommander = readPieceTitle(
        tester,
        viewport1,
        PieceType.commander,
      );

      await playMove(tester, 'g5', 'g6');
      await playMove(tester, 'g8', 'g7');
      expect(readTopHudText(tester, viewport1), contains('Turn 3'));

      await navigateBackToMenuFromGame(tester, confirm: true);
      expectOnMainMenu(tester);

      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'Japan');
      await selectFactionForSide(tester, PlayerSide.blue, 'South Korea');
      await navigateBackFromSubscreen(tester);

      final menuText = readAllVisibleText(tester);
      expect(menuText, contains('Japan'));
      expect(menuText, contains('South Korea'));

      await tapMenuOption(tester, 'Start');
      final viewport2 = findBoardViewportRect(tester);
      expect(readTopHudText(tester, viewport2), contains('Turn 1'));

      // Fresh board: g6 is empty and g5 Militia is back.
      await tapBoardCoord(tester, 'g6');
      expect(readBottomHudText(tester, viewport2), contains('Drag to orbit'));
      expect(readBottomHudText(tester, viewport2), isNot(contains('g6')));
      await tapBoardCoord(tester, 'g5');
      expect(readBottomHudText(tester, viewport2), contains('g5'));

      // g1 displays Japanese Commander designation (distinct from Vietnam).
      await tapBoardCoord(tester, 'g1');
      final jpCommander = readPieceTitle(
        tester,
        viewport2,
        PieceType.commander,
      );
      expect(jpCommander, isNot(equals(defaultVnCommander)));

      // Advance to Turn 2 and verify g12 displays South Korean Commander.
      await playMove(tester, 'g5', 'g6');
      await tapBoardCoord(tester, 'g12');
      final krCommander = readPieceTitle(
        tester,
        viewport2,
        PieceType.commander,
      );
      expect(krCommander, isNot(equals(jpCommander)));

      await unmountApp(tester);
    });

    testWidgets('T4-05: Help study -> Custom setup (UK vs France, Light, tacticalTop) -> Air Force opening', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Help');
      final helpText = await collectHelpScreenText(tester);
      expect(helpText.toLowerCase(), contains('air force'));
      expect(helpText, contains('United Kingdom'));
      expect(helpText, contains('France'));
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'United Kingdom');
      await selectFactionForSide(tester, PlayerSide.blue, 'France');
      await selectSettingsThemeMode(tester, ThemeMode.light);
      await selectSettingsCameraPreset(tester, E2ECameraPreset.tacticalTop);
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      expect(readActiveBrightness(tester), Brightness.light);
      final topChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey<String>('hud_camera_tacticalTop')),
      );
      expect(topChip.selected, isTrue);

      final viewportRect = findBoardViewportRect(tester);
      // Red Air Force flies 4 steps e2 -> e6 over e4 Anti-Aircraft.
      await playMove(
        tester,
        'e2',
        'e6',
        preset: E2ECameraPreset.tacticalTop,
      );
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));

      // Blue Air Force flies 4 steps e11 -> e7 onto estuary.
      await playMove(
        tester,
        'e11',
        'e7',
        preset: E2ECameraPreset.tacticalTop,
      );
      expect(readTopHudText(tester, viewportRect), contains('Turn 3'));

      await unmountApp(tester);
    });

    testWidgets('T4-06: Multi-turn camera presets, theme toggles, Undo, and Rematch with India vs Israel', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'India');
      await selectFactionForSide(tester, PlayerSide.blue, 'Israel');
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);

      // Cycle camera presets and verify spring settle + zero exceptions.
      await tapHudCameraPreset(tester, E2ECameraPreset.blueCommander);
      await tapHudCameraPreset(tester, E2ECameraPreset.sideOverview);
      await tapHudCameraPreset(tester, E2ECameraPreset.redCommander);
      expect(tester.takeException(), isNull);

      // Toggle theme Dark -> Light -> Dark from HUD.
      expect(readActiveBrightness(tester), Brightness.dark);
      await tapHudThemeToggle(tester);
      expect(readActiveBrightness(tester), Brightness.light);
      await tapHudThemeToggle(tester);
      expect(readActiveBrightness(tester), Brightness.dark);

      // Execute 3-ply sequence, Undo once, then Rematch.
      await playMove(tester, 'g5', 'g6');
      await playMove(tester, 'g8', 'g7');
      await playMove(tester, 'g6', 'g7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 4'));

      await tapHudUndo(tester);
      expect(readTopHudText(tester, viewportRect), contains('Turn 3'));

      await tapHudRematch(tester);
      final rematchTop = readTopHudText(tester, viewportRect);
      expect(rematchTop, contains('Turn 1'));
      expect(rematchTop, anyOf(contains('India'), contains('IN')));
      expect(rematchTop, anyOf(contains('Israel'), contains('IL')));

      await unmountApp(tester);
    });

    testWidgets('T4-07: Coastal naval engagement (China vs United States) and clean Exit flow', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'China');
      await selectFactionForSide(tester, PlayerSide.blue, 'United States');
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);

      // Red Navy sails past friendly c5 Infantry: c4 -> c6.
      await playMove(tester, 'c4', 'c6');
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));

      // Blue Navy sails past friendly c8 Infantry: c9 -> c7.
      await playMove(tester, 'c9', 'c7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 3'));

      // Red Navy captures Blue Navy across river coast: c6 -> c7.
      await playMove(tester, 'c6', 'c7');
      expect(readTopHudText(tester, viewportRect), contains('Turn 4'));

      // Return to Menu and perform clean Exit confirmation.
      await navigateBackToMenuFromGame(tester, confirm: true);
      expectOnMainMenu(tester);

      await triggerAndHandleExit(tester, confirm: true);
      expect(tester.takeException(), isNull);

      await unmountApp(tester);
    });
  });
}
