import 'dart:io';

import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:commander_chess_3d/features/game/rules/board_topology.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'e2e_test_helpers.dart';

void main() {
  String readPieceTitleFromBottomHud(
    WidgetTester tester,
    Rect viewportRect,
    PieceType type,
  ) {
    return readPiecePanelSummaryFromBottomHud(tester, viewportRect, type);
  }

  group('Tier 1 — Area A: Main UI Menu & Navigation', () {
    testWidgets('T1-A1: App launches onto Main Menu with all 4 required options', (
      tester,
    ) async {
      await pumpApp(tester);

      expectOnMainMenu(tester);
      expect(
        find.byKey(const ValueKey<String>('board_3d_viewport')),
        findsNothing,
      );

      await unmountApp(tester);
    });

    testWidgets('T1-A2: Main Menu displays default matchup summary', (
      tester,
    ) async {
      await pumpApp(tester);

      expectOnMainMenu(tester);
      final menuText = readAllVisibleText(tester);
      expect(menuText, contains('Vietnam'));
      expect(menuText, contains('United States'));

      await unmountApp(tester);
    });

    testWidgets('T1-A3: Start enters 3D match screen with active HUD & viewport', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);
      final topText = readTopHudText(tester, viewportRect);
      expect(topText, contains('Turn 1'));
      expect(
        find.byKey(const ValueKey<String>('hud_undo_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('hud_new_match_button')),
        findsOneWidget,
      );

      await unmountApp(tester);
    });

    testWidgets('T1-A4: Help opens Help screen and returns cleanly to Main Menu', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Help');
      expect(find.text('Start'), findsNothing);
      final helpText = readAllVisibleText(tester).toLowerCase();
      expect(helpText, anyOf(contains('commander'), contains('rules')));

      await navigateBackFromSubscreen(tester);
      expectOnMainMenu(tester);

      await unmountApp(tester);
    });

    testWidgets('T1-A5: Settings opens Settings screen and returns to Main Menu', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Settings');
      final settingsText = readAllVisibleText(tester).toLowerCase();
      expect(
        settingsText,
        anyOf(contains('side 1'), contains('red'), contains('faction')),
      );

      await navigateBackFromSubscreen(tester);
      expectOnMainMenu(tester);

      await unmountApp(tester);
    });

    testWidgets('T1-A6: Exit triggers platform-safe confirmation or session-ended view', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapMenuOption(tester, 'Exit');
      final hasDialog =
          find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(Dialog).evaluate().isNotEmpty;
      final visible = readAllVisibleText(tester).toLowerCase();
      final hasSessionEndedView =
          visible.contains('session ended') ||
          visible.contains('return to menu');

      expect(
        hasDialog || hasSessionEndedView,
        isTrue,
        reason:
            'Tapping Exit must open a confirmation dialog or Session Ended view.',
      );

      if (hasDialog) {
        final dialogs = find.byType(AlertDialog).evaluate().isNotEmpty
            ? find.byType(AlertDialog)
            : find.byType(Dialog);
        final confirmBtn = find.descendant(
          of: dialogs.last,
          matching: find.byWidgetPredicate((widget) {
            if (widget is Text) {
              final v = (widget.data ?? '').trim().toLowerCase();
              return v == 'exit' ||
                  v == 'quit' ||
                  v == 'confirm' ||
                  v == 'yes';
            }
            return false;
          }),
        );
        expect(confirmBtn, findsAtLeastNWidgets(1));
        await tester.tap(confirmBtn.last);
        await pumpFrames(tester, count: 8);
      }

      expect(tester.takeException(), isNull);
      await unmountApp(tester);
    });
  });

  group('Tier 1 — Area B: Help Screen Completeness', () {
    testWidgets('T1-B1: Help documents 11x12 board and all terrain zones', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Help');

      final helpText = (await collectHelpScreenText(tester)).toLowerCase();
      expect(helpText, contains('11'));
      expect(helpText, contains('12'));
      expect(helpText, contains('sea'));
      expect(
        helpText,
        anyOf(contains('mixed'), contains('coast'), contains('estuary')),
      );
      expect(helpText, contains('river'));
      expect(helpText, contains('ford'));

      await unmountApp(tester);
    });

    testWidgets('T1-B2: Help documents all 11 unit types and 19 units per side', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Help');

      final helpText = (await collectHelpScreenText(tester)).toLowerCase();
      expect(helpText, contains('19'));
      for (final type in PieceType.values) {
        expect(
          helpText,
          contains(type.displayNameEn.toLowerCase()),
          reason: 'Help must document unit type ${type.displayNameEn}.',
        );
      }

      await unmountApp(tester);
    });

    testWidgets('T1-B3: Help documents core Commander Chess rules', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Help');

      final helpText = (await collectHelpScreenText(tester)).toLowerCase();
      expect(helpText, contains('commander'));
      expect(helpText, contains('headquarters'));
      expect(
        helpText,
        anyOf(
          contains('face-to-face'),
          contains('face to face'),
          contains('line of sight'),
          contains('los'),
          contains('face each other'),
        ),
      );
      expect(helpText, contains('heavy'));
      expect(helpText, contains('capture'));

      await unmountApp(tester);
    });

    testWidgets('T1-B4: Help documents 3D camera and board controls', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Help');

      final helpText = (await collectHelpScreenText(tester)).toLowerCase();
      expect(helpText, anyOf(contains('tap'), contains('select')));
      expect(helpText, anyOf(contains('drag'), contains('orbit')));
      expect(
        helpText,
        anyOf(contains('zoom'), contains('pinch'), contains('scroll')),
      );
      expect(helpText, anyOf(contains('camera'), contains('preset')));

      await unmountApp(tester);
    });

    testWidgets('T1-B5: Help lists all 11 national factions', (tester) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Help');

      final helpText = await collectHelpScreenText(tester);
      for (final faction in kAllFactionNames) {
        expect(
          helpText,
          contains(faction),
          reason: 'Help must document national faction "$faction".',
        );
      }

      await unmountApp(tester);
    });
  });

  group('Tier 1 — Area C: Settings & 11-Faction Selection', () {
    testWidgets('T1-C1: Settings exposes all 11 factions for Side 1 and Side 2', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Settings');

      for (final faction in kAllFactionNames) {
        await selectFactionForSide(tester, PlayerSide.red, faction);
        expect(tester.takeException(), isNull);
      }
      for (final faction in kAllFactionNames) {
        await selectFactionForSide(tester, PlayerSide.blue, faction);
        expect(tester.takeException(), isNull);
      }

      await navigateBackFromSubscreen(tester);
      final menuText = readAllVisibleText(tester);
      expect(menuText, contains('Israel'));

      await unmountApp(tester);
    });

    testWidgets('T1-C2: Selecting Soviet Union vs Germany persists to Main Menu', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Settings');

      await selectFactionForSide(tester, PlayerSide.red, 'Soviet Union');
      await selectFactionForSide(tester, PlayerSide.blue, 'Germany');
      await navigateBackFromSubscreen(tester);

      final menuText = readAllVisibleText(tester);
      expect(menuText, contains('Soviet Union'));
      expect(menuText, contains('Germany'));

      await unmountApp(tester);
    });

    testWidgets('T1-C3: Rotating remaining factions persists cleanly to Main Menu', (
      tester,
    ) async {
      await pumpApp(tester);

      const pairs = <(String, String)>[
        ('United Kingdom', 'France'),
        ('China', 'Japan'),
        ('South Korea', 'India'),
        ('Israel', 'United States'),
      ];

      for (final (redFaction, blueFaction) in pairs) {
        await tapMenuOption(tester, 'Settings');
        await selectFactionForSide(tester, PlayerSide.red, redFaction);
        await selectFactionForSide(tester, PlayerSide.blue, blueFaction);
        await navigateBackFromSubscreen(tester);

        final menuText = readAllVisibleText(tester);
        expect(menuText, contains(redFaction));
        expect(menuText, contains(blueFaction));
      }

      await unmountApp(tester);
    });

    testWidgets('T1-C4: Swap Sides exchanges Side 1 and Side 2 factions in-game', (
      tester,
    ) async {
      await pumpApp(tester);

      // Capture baseline Vietnam g1 Commander designation.
      await tapMenuOption(tester, 'Start');
      await tapBoardCoord(tester, 'g1');
      final viewport1 = findBoardViewportRect(tester);
      final vietnamCommanderTitle = readPieceTitleFromBottomHud(
        tester,
        viewport1,
        PieceType.commander,
      );
      await navigateBackToMenuFromGame(tester, confirm: true);

      // Swap default Vietnam (Side 1) vs United States (Side 2).
      await tapMenuOption(tester, 'Settings');
      await tapSwapFactionsInSettings(tester);
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      await tapBoardCoord(tester, 'g1');
      final viewport2 = findBoardViewportRect(tester);
      final swappedRedCommanderTitle = readPieceTitleFromBottomHud(
        tester,
        viewport2,
        PieceType.commander,
      );

      expect(
        swappedRedCommanderTitle,
        isNot(equals(vietnamCommanderTitle)),
        reason: 'After swapping, Side 1 g1 must use United States designation.',
      );

      await unmountApp(tester);
    });

    testWidgets('T1-C5: Settings Theme toggle updates MaterialApp brightness', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(readActiveBrightness(tester), Brightness.dark);

      await tapMenuOption(tester, 'Settings');
      await selectSettingsThemeMode(tester, ThemeMode.light);
      expect(readActiveBrightness(tester), Brightness.light);

      await navigateBackFromSubscreen(tester);
      expect(readActiveBrightness(tester), Brightness.light);

      await unmountApp(tester);
    });

    testWidgets('T1-C6: Settings Default Camera Preset applies on new match start', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Settings');
      await selectSettingsCameraPreset(tester, E2ECameraPreset.tacticalTop);
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      final topChipFinder = find.byKey(
        const ValueKey<String>('hud_camera_tacticalTop'),
      );
      expect(topChipFinder, findsOneWidget);
      final chip = tester.widget<ChoiceChip>(topChipFinder);
      expect(chip.selected, isTrue);

      await tapBoardCoord(
        tester,
        'g1',
        preset: E2ECameraPreset.tacticalTop,
      );
      final viewportRect = findBoardViewportRect(tester);
      final bottomText = readBottomHudText(tester, viewportRect);
      expect(bottomText, contains('g1'));
      expect(bottomText, contains('Tư lệnh • Commander'));

      await unmountApp(tester);
    });
  });

  group('Tier 1 — Area D: 19-Unit Setup, Faction Units & Match Flow', () {
    testWidgets('T1-D1: Full 19 Red and 19 Blue units are placed and selectable', (
      tester,
    ) async {
      const topology = StandardCommanderBoardTopology();
      final initialPieces = topology.createInitialPieces();
      final redPieces = initialPieces
          .where((p) => p.side == PlayerSide.red)
          .toList();
      final bluePieces = initialPieces
          .where((p) => p.side == PlayerSide.blue)
          .toList();
      expect(redPieces, hasLength(19));
      expect(bluePieces, hasLength(19));

      await pumpApp(tester);
      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);

      // Turn 1: tap every single Red unit on its initial square.
      for (final piece in redPieces) {
        final alg = piece.position.toAlgebraic();
        await tapBoardCoord(tester, alg);
        final hudText = readBottomHudText(tester, viewportRect);
        expect(hudText, contains(alg));
        expect(hudText, contains(piece.type.displayNameEn));
      }

      // Advance to Turn 2 (Blue) and tap every single Blue unit.
      await playMove(tester, 'g5', 'g6');
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));

      for (final piece in bluePieces) {
        final alg = piece.position.toAlgebraic();
        await tapBoardCoord(tester, alg);
        final hudText = readBottomHudText(tester, viewportRect);
        expect(hudText, contains(alg));
        expect(hudText, contains(piece.type.displayNameEn));
      }

      await unmountApp(tester);
    });

    testWidgets('T1-D2: Game HUD displays active factions and preserves Tư lệnh • Commander', (
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
      expect(
        topText,
        anyOf(contains('Soviet Union'), contains('USSR')),
      );
      expect(
        topText,
        anyOf(contains('Germany'), contains('DE')),
      );

      await tapBoardCoord(tester, 'g1');
      final bottomText = readBottomHudText(tester, viewportRect);
      expect(bottomText, contains('Tư lệnh • Commander'));
      expect(bottomText, contains('g1'));

      await unmountApp(tester);
    });

    testWidgets('T1-D3: Side 1 unit designations are unique across Vietnam, USA, Soviet Union', (
      tester,
    ) async {
      await pumpApp(tester);

      const inspectedCoords = <(String, PieceType)>[
        ('g1', PieceType.commander),
        ('f4', PieceType.tank),
        ('e2', PieceType.airForce),
        ('b2', PieceType.navy),
      ];
      final designationsByFaction = <String, Map<String, String>>{};

      for (final faction in const <String>[
        'Vietnam',
        'United States',
        'Soviet Union',
      ]) {
        await tapMenuOption(tester, 'Settings');
        await selectFactionForSide(tester, PlayerSide.red, faction);
        await navigateBackFromSubscreen(tester);
        await tapMenuOption(tester, 'Start');

        final viewportRect = findBoardViewportRect(tester);
        final map = <String, String>{};
        for (final (coord, type) in inspectedCoords) {
          await tapBoardCoord(tester, coord);
          map[coord] = readPieceTitleFromBottomHud(tester, viewportRect, type);
        }
        designationsByFaction[faction] = map;
        await navigateBackToMenuFromGame(tester, confirm: true);
      }

      for (final (coord, _) in inspectedCoords) {
        final vn = designationsByFaction['Vietnam']![coord]!;
        final us = designationsByFaction['United States']![coord]!;
        final su = designationsByFaction['Soviet Union']![coord]!;
        expect(<String>{vn, us, su}, hasLength(3));
      }

      await unmountApp(tester);
    });

    testWidgets('T1-D4: Side 2 unit designations are unique between Germany and Japan', (
      tester,
    ) async {
      await pumpApp(tester);

      const inspectedCoords = <(String, PieceType)>[
        ('g12', PieceType.commander),
        ('f9', PieceType.tank),
        ('e11', PieceType.airForce),
        ('b11', PieceType.navy),
      ];
      final designationsByFaction = <String, Map<String, String>>{};

      for (final faction in const <String>['Germany', 'Japan']) {
        await tapMenuOption(tester, 'Settings');
        await selectFactionForSide(tester, PlayerSide.blue, faction);
        await navigateBackFromSubscreen(tester);
        await tapMenuOption(tester, 'Start');

        await playMove(tester, 'g5', 'g6');
        final viewportRect = findBoardViewportRect(tester);
        final map = <String, String>{};
        for (final (coord, type) in inspectedCoords) {
          await tapBoardCoord(tester, coord);
          map[coord] = readPieceTitleFromBottomHud(tester, viewportRect, type);
        }
        designationsByFaction[faction] = map;
        await navigateBackToMenuFromGame(tester, confirm: true);
      }

      for (final (coord, _) in inspectedCoords) {
        final de = designationsByFaction['Germany']![coord]!;
        final jp = designationsByFaction['Japan']![coord]!;
        expect(de, isNot(equals(jp)));
      }

      await unmountApp(tester);
    });

    testWidgets('T1-D5: Move, Undo, and Rematch flow resets and restores turns accurately', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);

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
      await tapBoardCoord(tester, 'g5');
      expect(readBottomHudText(tester, viewportRect), contains('g5'));

      await unmountApp(tester);
    });

    testWidgets('T1-D6: In-game Back-to-Menu returns cleanly to Main Menu', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Start');
      findBoardViewportRect(tester);

      await navigateBackToMenuFromGame(tester, confirm: true);
      expectOnMainMenu(tester);
      expect(
        find.byKey(const ValueKey<String>('board_3d_viewport')),
        findsNothing,
      );

      await unmountApp(tester);
    });
  });

  group('Tier 1 — Area E: 121 National .glb & Manifest Coverage', () {
    test('T1-E1: asset_manifest.json keeps 22 v1 pieces and adds 121 faction entries', () {
      final manifest = loadAssetManifestJson();
      expect(manifest['schemaVersion'], anyOf(1, 2));

      final v1Pieces = manifest['pieces'] as List<dynamic>;
      expect(v1Pieces, hasLength(22));

      final factionMeshes = extractFactionMeshPaths(manifest);
      expect(factionMeshes, hasLength(121));

      for (final faction in kAllFactionNames) {
        for (final type in PieceType.values) {
          expect(
            factionMeshes.containsKey((faction, type)),
            isTrue,
            reason: 'Manifest missing factionMesh for ($faction, ${type.name}).',
          );
        }
      }
    });

    test('T1-E2: All 121 national .glb files exist and pass glTF 2.0 binary header checks', () {
      final manifest = loadAssetManifestJson();
      final factionMeshes = extractFactionMeshPaths(manifest);
      expect(factionMeshes, hasLength(121));

      for (final entry in factionMeshes.entries) {
        final file = File(entry.value);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Missing GLB file ${entry.value} for ${entry.key}.',
        );
        final bytes = file.readAsBytesSync();
        final parsed = parseGlbBinaryOpaque(bytes);
        expect(parsed.totalLength, bytes.length);
        expect(parsed.vertexCount, greaterThan(0));
      }
    });

    test('T1-E3: All 121 .glb bounding boxes strictly comply with BLENDER_ASSET_CONTRACT', () {
      final manifest = loadAssetManifestJson();
      final factionMeshes = extractFactionMeshPaths(manifest);

      for (final entry in factionMeshes.entries) {
        final parsed = parseGlbBinaryOpaque(
          File(entry.value).readAsBytesSync(),
        );
        expect(parsed.minX, greaterThanOrEqualTo(-0.4251));
        expect(parsed.maxX, lessThanOrEqualTo(0.4251));
        expect(parsed.minY, greaterThanOrEqualTo(-0.0001));
        expect(parsed.maxY, lessThanOrEqualTo(1.2001));
        expect(parsed.minZ, greaterThanOrEqualTo(-0.4251));
        expect(parsed.maxZ, lessThanOrEqualTo(0.4251));
        expect(parsed.maxX - parsed.minX, greaterThan(0.05));
        expect(parsed.maxY - parsed.minY, greaterThan(0.05));
        expect(parsed.maxZ - parsed.minZ, greaterThan(0.05));
      }
    });

    test('T1-E4: Faction .glb meshes have distinct geometry per nation for every unit type', () {
      final manifest = loadAssetManifestJson();
      final factionMeshes = extractFactionMeshPaths(manifest);

      for (final type in PieceType.values) {
        final rawHashes = <int>{};
        final geometryHashes = <int>{};
        for (final faction in kAllFactionNames) {
          final path = factionMeshes[(faction, type)]!;
          final parsed = parseGlbBinaryOpaque(File(path).readAsBytesSync());
          rawHashes.add(parsed.rawFileHash);
          geometryHashes.add(parsed.geometryHash);
        }
        expect(
          rawHashes,
          hasLength(11),
          reason: 'All 11 factions for ${type.name} must have distinct .glb files.',
        );
        expect(
          geometryHashes,
          hasLength(11),
          reason:
              'All 11 factions for ${type.name} must have genuinely distinct 3D geometry.',
        );
      }
    });

    test('T1-E5: Carrier descriptors and socket nodes expose passenger sockets accurately', () {
      final manifest = loadAssetManifestJson();
      final v1Pieces = manifest['pieces'] as List<dynamic>;
      expect(v1Pieces, hasLength(22));

      final seenPairs = <(PlayerSide, PieceType)>{};
      for (final rawItem in v1Pieces) {
        final item = Map<String, dynamic>.from(rawItem as Map);
        final visualKey = Map<String, dynamic>.from(item['visualKey'] as Map);
        final side = PlayerSide.tryFromJsonValue(visualKey['side']);
        final type = PieceType.tryFromJsonValue(visualKey['type']);
        expect(side, isNotNull);
        expect(type, isNotNull);
        expect(seenPairs.add((side!, type!)), isTrue);

        final sockets = (item['passengerSockets'] as List<dynamic>)
            .cast<String>();
        final carrySocket = (item['carrySocketName'] ?? '').toString();

        if (type.carrierCapacity > 0) {
          expect(carrySocket, 'socket_passenger_0');
          expect(sockets, contains('socket_passenger_0'));
          if (type.carrierCapacity >= 2) {
            expect(sockets, contains('socket_passenger_1'));
          }
        } else {
          expect(carrySocket, isEmpty);
          expect(sockets, isEmpty);
        }
      }
      expect(seenPairs, hasLength(22));

      // Validate all 121 generated .glb files across all 11 factions:
      // every .glb has valid nodes & non-zero geometry, non-carriers expose no
      // passenger socket nodes, and every carrier .glb unconditionally exposes
      // all required socket_passenger_* nodes matching carrierCapacity.
      final factionMeshes = extractFactionMeshPaths(manifest);
      expect(factionMeshes, hasLength(121));
      for (final faction in kAllFactionNames) {
        for (final type in PieceType.values) {
          final path = factionMeshes[(faction, type)]!;
          final parsed = parseGlbBinaryOpaque(File(path).readAsBytesSync());
          expect(parsed.nodeNames, isNotEmpty);
          expect(parsed.vertexCount, greaterThan(0));
          expect(parsed.maxY - parsed.minY, greaterThan(0.05));

          final socketNodes = parsed.socketNodeWorldPositions.keys.toSet();
          if (type.carrierCapacity == 0) {
            expect(
              socketNodes,
              isEmpty,
              reason:
                  'Non-carrier ($faction, ${type.name}) must not declare socket nodes.',
            );
          } else {
            expect(
              socketNodes,
              contains('socket_passenger_0'),
              reason:
                  'Carrier ($faction, ${type.name}) GLB must expose socket_passenger_0.',
            );
            if (type.carrierCapacity >= 2) {
              expect(
                socketNodes,
                contains('socket_passenger_1'),
                reason:
                    'Multi-passenger carrier ($faction, ${type.name}) GLB must expose socket_passenger_1.',
              );
            }
            expect(
              socketNodes,
              hasLength(type.carrierCapacity),
              reason:
                  'Carrier ($faction, ${type.name}) GLB socket count must match carrierCapacity ${type.carrierCapacity}.',
            );
          }
        }
      }
    });
  });
}
