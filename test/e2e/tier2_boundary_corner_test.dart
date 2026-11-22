import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'e2e_test_helpers.dart';

Uint8List _assembleGlb(Map<String, dynamic> gltfObj, Uint8List binPayload) {
  final rawJson = utf8.encode(jsonEncode(gltfObj));
  final jsonPad = (4 - (rawJson.length % 4)) % 4;
  final chunk0Len = rawJson.length + jsonPad;
  final binPad = (4 - (binPayload.length % 4)) % 4;
  final chunk1Len = binPayload.length + binPad;
  final totalLen = 12 + 8 + chunk0Len + 8 + chunk1Len;

  final out = Uint8List(totalLen);
  final bd = ByteData.sublistView(out);

  // Header
  bd.setUint32(0, 0x46546C67, Endian.little);
  bd.setUint32(4, 2, Endian.little);
  bd.setUint32(8, totalLen, Endian.little);

  // Chunk 0: JSON
  bd.setUint32(12, chunk0Len, Endian.little);
  bd.setUint32(16, 0x4E4F534A, Endian.little);
  out.setRange(20, 20 + rawJson.length, rawJson);
  for (var i = 0; i < jsonPad; i++) {
    out[20 + rawJson.length + i] = 0x20;
  }

  // Chunk 1: BIN
  final binHeaderOff = 20 + chunk0Len;
  bd.setUint32(binHeaderOff, chunk1Len, Endian.little);
  bd.setUint32(binHeaderOff + 4, 0x004E4942, Endian.little);
  out.setRange(
    binHeaderOff + 8,
    binHeaderOff + 8 + binPayload.length,
    binPayload,
  );
  return out;
}

Uint8List _encodeFloat32Vertices(List<double> coords) {
  final bytes = Uint8List(coords.length * 4);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < coords.length; i++) {
    bd.setFloat32(i * 4, coords[i], Endian.little);
  }
  return bytes;
}

Map<String, dynamic> _baseGltfJson({
  required List<Map<String, dynamic>> nodes,
  List<int>? sceneNodes,
  int bufferByteLength = 36,
  List<Map<String, dynamic>>? bufferViews,
  List<Map<String, dynamic>>? accessors,
  Map<String, dynamic>? primitive,
}) {
  return <String, dynamic>{
    'asset': <String, dynamic>{'version': '2.0'},
    'scene': 0,
    'scenes': <dynamic>[
      <String, dynamic>{'nodes': sceneNodes ?? <int>[0]},
    ],
    'nodes': nodes,
    'meshes': <dynamic>[
      <String, dynamic>{
        'primitives': <dynamic>[
          primitive ??
              <String, dynamic>{
                'attributes': <String, dynamic>{'POSITION': 0},
              },
        ],
      },
    ],
    'materials': <dynamic>[
      <String, dynamic>{'name': 'mat_test'},
    ],
    'buffers': <dynamic>[
      <String, dynamic>{'byteLength': bufferByteLength},
    ],
    'bufferViews':
        bufferViews ??
        <Map<String, dynamic>>[
          <String, dynamic>{
            'buffer': 0,
            'byteOffset': 0,
            'byteLength': bufferByteLength,
          },
        ],
    'accessors':
        accessors ??
        <Map<String, dynamic>>[
          <String, dynamic>{
            'bufferView': 0,
            'componentType': 5126,
            'count': 3,
            'type': 'VEC3',
          },
        ],
  };
}

Uint8List _buildMinimalValidGlb({double peakY = 0.5}) {
  final verts = _encodeFloat32Vertices(<double>[
    0.0,
    0.0,
    0.0,
    0.2,
    peakY,
    0.0,
    -0.2,
    0.0,
    0.2,
  ]);
  final gltfObj = _baseGltfJson(
    nodes: <Map<String, dynamic>>[
      <String, dynamic>{'name': 'piece_test', 'mesh': 0},
    ],
    bufferByteLength: verts.length,
  );
  return _assembleGlb(gltfObj, verts);
}

void main() {
  group('Tier 2 — Boundary & Corner Cases', () {
    testWidgets('T2-01: Mirror match Vietnam vs Vietnam keeps Red/Blue distinct and executes moves', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'Vietnam');
      await selectFactionForSide(tester, PlayerSide.blue, 'Vietnam');

      final settingsText = readAllVisibleText(tester).toLowerCase();
      expect(settingsText, contains('mirror'));
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);
      expect(readTopHudText(tester, viewportRect), contains('Red'));
      expect(readTopHudText(tester, viewportRect), contains('Turn 1'));

      await playMove(tester, 'g5', 'g6');
      final turn2Top = readTopHudText(tester, viewportRect);
      expect(turn2Top, contains('Blue'));
      expect(turn2Top, contains('Turn 2'));

      await playMove(tester, 'g8', 'g7');
      final turn3Top = readTopHudText(tester, viewportRect);
      expect(turn3Top, contains('Red'));
      expect(turn3Top, contains('Turn 3'));

      await unmountApp(tester);
    });

    testWidgets('T2-02: Mirror match Israel vs Israel preserves Israeli designations & Red/Blue side labels', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Settings');
      await selectFactionForSide(tester, PlayerSide.red, 'Israel');
      await selectFactionForSide(tester, PlayerSide.blue, 'Israel');
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);
      expect(readTopHudText(tester, viewportRect), contains('Red'));

      await tapBoardCoord(tester, 'g1');
      final redCommanderBanner = readBottomHudText(tester, viewportRect);
      expect(redCommanderBanner, contains('Tư lệnh • Commander'));
      expect(redCommanderBanner, contains('g1'));

      await playMove(tester, 'g5', 'g6');
      expect(readTopHudText(tester, viewportRect), contains('Blue'));

      await tapBoardCoord(tester, 'g12');
      final blueCommanderBanner = readBottomHudText(tester, viewportRect);
      expect(blueCommanderBanner, contains('Tư lệnh • Commander'));
      expect(blueCommanderBanner, contains('g12'));

      await unmountApp(tester);
    });

    testWidgets('T2-03: 320x568 with textScaler 1.4x has zero overflow on Menu, Help, and Settings in Light & Dark themes', (
      tester,
    ) async {
      for (final mode in const <ThemeMode>[ThemeMode.dark, ThemeMode.light]) {
        await pumpApp(
          tester,
          size: const Size(320, 568),
          textScaleFactor: 1.4,
        );

        if (mode == ThemeMode.light) {
          await tapMenuOption(tester, 'Settings');
          await selectSettingsThemeMode(tester, ThemeMode.light);
          await navigateBackFromSubscreen(tester);
        }

        expectOnMainMenu(tester);
        expect(tester.takeException(), isNull);

        await tapMenuOption(tester, 'Help');
        final helpText = await collectHelpScreenText(tester);
        expect(helpText.toLowerCase(), contains('commander'));
        expect(tester.takeException(), isNull);
        await navigateBackFromSubscreen(tester);

        await tapMenuOption(tester, 'Settings');
        await selectFactionForSide(tester, PlayerSide.red, 'France');
        expect(tester.takeException(), isNull);
        await navigateBackFromSubscreen(tester);

        await unmountApp(tester);
      }
    });

    testWidgets('T2-04: 320x568 with textScaler 1.4x has zero overflow on Game screen in Light & Dark themes', (
      tester,
    ) async {
      for (final mode in const <ThemeMode>[ThemeMode.dark, ThemeMode.light]) {
        await pumpApp(
          tester,
          size: const Size(320, 568),
          textScaleFactor: 1.4,
        );

        if (mode == ThemeMode.light) {
          await tapMenuOption(tester, 'Settings');
          await selectSettingsThemeMode(tester, ThemeMode.light);
          await navigateBackFromSubscreen(tester);
        }

        await tapMenuOption(tester, 'Start');
        final viewportRect = findBoardViewportRect(tester);
        expect(viewportRect.height, greaterThanOrEqualTo(180.0));
        expect(tester.takeException(), isNull);

        await tapBoardCoord(tester, 'g5');
        final bottomText = readBottomHudText(tester, viewportRect);
        expect(bottomText, contains('g5'));
        expect(tester.takeException(), isNull);

        await unmountApp(tester);
      }
    });

    testWidgets('T2-05: Rapid menu, subscreen, and game navigation stress produces zero exceptions', (
      tester,
    ) async {
      await pumpApp(tester);

      for (var cycle = 0; cycle < 3; cycle++) {
        await tapMenuOption(tester, 'Help');
        await pumpFrames(tester, count: 2);
        await navigateBackFromSubscreen(tester);

        await tapMenuOption(tester, 'Settings');
        await pumpFrames(tester, count: 2);
        await navigateBackFromSubscreen(tester);

        await tapMenuOption(tester, 'Start');
        await pumpFrames(tester, count: 3);
        findBoardViewportRect(tester);
        await navigateBackToMenuFromGame(tester, confirm: true);
        expectOnMainMenu(tester);
      }

      expect(tester.takeException(), isNull);
      await unmountApp(tester);
    });

    testWidgets('T2-06: Light and Dark theme brightness stays consistent across Menu, Help, Settings, and Game', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(readActiveBrightness(tester), Brightness.dark);

      // Switch to Light in Settings and verify all 4 screens.
      await tapMenuOption(tester, 'Settings');
      await selectSettingsThemeMode(tester, ThemeMode.light);
      expect(readActiveBrightness(tester), Brightness.light);
      await navigateBackFromSubscreen(tester);
      expect(readActiveBrightness(tester), Brightness.light);

      await tapMenuOption(tester, 'Help');
      expect(readActiveBrightness(tester), Brightness.light);
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Start');
      expect(readActiveBrightness(tester), Brightness.light);

      // Toggle back to Dark from in-game HUD and verify across all 4 screens.
      await tapHudThemeToggle(tester);
      expect(readActiveBrightness(tester), Brightness.dark);
      await navigateBackToMenuFromGame(tester, confirm: true);
      expect(readActiveBrightness(tester), Brightness.dark);

      await tapMenuOption(tester, 'Help');
      expect(readActiveBrightness(tester), Brightness.dark);
      await navigateBackFromSubscreen(tester);

      await tapMenuOption(tester, 'Settings');
      expect(readActiveBrightness(tester), Brightness.dark);

      await unmountApp(tester);
    });

    testWidgets('T2-07: Cancelling Exit confirmation dialog keeps user on Main Menu with all 4 options', (
      tester,
    ) async {
      await pumpApp(tester);

      await triggerAndHandleExit(tester, confirm: false);
      expectOnMainMenu(tester);
      expect(tester.takeException(), isNull);

      await unmountApp(tester);
    });

    testWidgets('T2-08: Cancelling Back-to-Menu preserves Turn 2 state, then confirming returns to Menu', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);

      await playMove(tester, 'g5', 'g6');
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));

      await navigateBackToMenuFromGame(tester, confirm: false);
      expect(readTopHudText(tester, viewportRect), contains('Turn 2'));

      // Verify Blue Turn 2 is still active and g6 cannot be selected by Blue.
      await tapBoardCoord(tester, 'g8');
      expect(readBottomHudText(tester, viewportRect), contains('g8'));

      await navigateBackToMenuFromGame(tester, confirm: true);
      expectOnMainMenu(tester);

      await unmountApp(tester);
    });

    testWidgets('T2-09: Invalid, empty, wrong-turn, immobile, and illegal target taps & deselection on Turn 1', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);

      // Empty square g6 -> no selection.
      await tapBoardCoord(tester, 'g6');
      expect(readTopHudText(tester, viewportRect), contains('Turn 1'));
      expect(readBottomHudText(tester, viewportRect), contains('Drag to orbit'));
      expect(readBottomHudText(tester, viewportRect), isNot(contains('g6')));

      // Wrong-turn Blue piece g8 -> rejected.
      await tapBoardCoord(tester, 'g8');
      expect(readTopHudText(tester, viewportRect), contains('Turn 1'));
      expect(readBottomHudText(tester, viewportRect), contains('Drag to orbit'));
      expect(readBottomHudText(tester, viewportRect), isNot(contains('g8')));

      // Immobile Red Headquarters f2 -> 0 legal moves.
      await tapBoardCoord(tester, 'f2');
      final hqText = readBottomHudText(tester, viewportRect);
      expect(hqText, contains('f2'));
      expect(hqText, contains('0 legal moves'));

      // Select g5 then tap illegal target a1 -> remains Turn 1.
      await tapBoardCoord(tester, 'g5');
      expect(readBottomHudText(tester, viewportRect), contains('g5'));
      await tapBoardCoord(tester, 'a1');
      expect(readTopHudText(tester, viewportRect), contains('Turn 1'));

      // Select g5 then tap g5 again -> deselects cleanly.
      await tapBoardCoord(tester, 'g5');
      expect(readBottomHudText(tester, viewportRect), contains('g5'));
      await tapBoardCoord(tester, 'g5');
      expect(readBottomHudText(tester, viewportRect), contains('Drag to orbit'));
      expect(readBottomHudText(tester, viewportRect), isNot(contains('g5')));

      await unmountApp(tester);
    });

    testWidgets('T2-10: Viewport corner and edge boundary taps do not crash or mutate Turn 1', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapMenuOption(tester, 'Start');
      final viewportRect = findBoardViewportRect(tester);

      final corners = <Offset>[
        viewportRect.topLeft + const Offset(1, 1),
        Offset(viewportRect.right - 1, viewportRect.top + 1),
        Offset(viewportRect.left + 1, viewportRect.bottom - 1),
        viewportRect.bottomRight - const Offset(1, 1),
      ];

      for (final corner in corners) {
        await tester.tapAt(corner);
        await pumpFrames(tester, count: 3);
      }

      expect(readTopHudText(tester, viewportRect), contains('Turn 1'));
      expect(tester.takeException(), isNull);

      await unmountApp(tester);
    });

    test('T2-11: Negative GLB parser boundary checks reject malformed binaries and accept valid parent-scaled hierarchies', () {
      final valid = _buildMinimalValidGlb(peakY: 0.5);
      expect(parseGlbBinaryOpaque(valid).vertexCount, 3);

      // 1. Empty payload
      expect(
        () => parseGlbBinaryOpaque(Uint8List(0)),
        throwsFormatException,
      );

      // 2. 11-byte truncated header
      expect(
        () => parseGlbBinaryOpaque(Uint8List.fromList(valid.sublist(0, 11))),
        throwsFormatException,
      );

      // 3. Bad magic ('NOTG')
      final badMagic = Uint8List.fromList(valid);
      ByteData.sublistView(badMagic).setUint32(0, 0x47544F4E, Endian.little);
      expect(() => parseGlbBinaryOpaque(badMagic), throwsFormatException);

      // 4. Wrong version (version 1 and version 3)
      for (final badVer in const <int>[1, 3]) {
        final badVersion = Uint8List.fromList(valid);
        ByteData.sublistView(badVersion).setUint32(4, badVer, Endian.little);
        expect(() => parseGlbBinaryOpaque(badVersion), throwsFormatException);
      }

      // 5. Wrong declared length
      final badLen = Uint8List.fromList(valid);
      ByteData.sublistView(badLen).setUint32(8, valid.length + 4, Endian.little);
      expect(() => parseGlbBinaryOpaque(badLen), throwsFormatException);

      // 6. Missing JSON chunk (chunk0Type != 'JSON')
      final missingJson = Uint8List.fromList(valid);
      ByteData.sublistView(missingJson).setUint32(16, 0x004E4942, Endian.little);
      expect(() => parseGlbBinaryOpaque(missingJson), throwsFormatException);

      // 7. Out-of-bounds vertex (y > 1.20)
      final oobVertex = _buildMinimalValidGlb(peakY: 1.30);
      expect(() => parseGlbBinaryOpaque(oobVertex), throwsFormatException);

      final baseVerts = _encodeFloat32Vertices(<double>[
        0.0,
        0.0,
        0.0,
        0.2,
        0.8,
        0.0,
        -0.2,
        0.0,
        0.2,
      ]);

      // 8 (M2): Trailing garbage inside BIN chunk (binBytes.length - buf0ByteLength > 3)
      final m2Payload = Uint8List(baseVerts.length + 16)
        ..setRange(0, baseVerts.length, baseVerts);
      final m2Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{'name': 'm2', 'mesh': 0},
          ],
          bufferByteLength: baseVerts.length,
        ),
        m2Payload,
      );
      expect(() => parseGlbBinaryOpaque(m2Glb), throwsFormatException);

      // 9 (M8): Node rotation quaternion pushes y=0.8 vertex into x=-0.8 (< -0.425)
      const invSqrt2 = 0.7071067811865476;
      final m8Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'm8',
              'mesh': 0,
              'rotation': <double>[0.0, 0.0, invSqrt2, invSqrt2],
            },
          ],
          bufferByteLength: baseVerts.length,
        ),
        baseVerts,
      );
      expect(() => parseGlbBinaryOpaque(m8Glb), throwsFormatException);

      // 10 (M9): Parent node translation pushes child mesh vertex above y=1.20
      final m9Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'm9_parent',
              'translation': <double>[0.0, 0.6, 0.0],
              'children': <int>[1],
            },
            <String, dynamic>{'name': 'm9_child', 'mesh': 0},
          ],
          sceneNodes: <int>[0],
          bufferByteLength: baseVerts.length,
        ),
        baseVerts,
      );
      expect(() => parseGlbBinaryOpaque(m9Glb), throwsFormatException);

      // 11 (M10): Node 4x4 column-major matrix translates vertex outside bounds
      final m10Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'm10',
              'mesh': 0,
              'matrix': <double>[
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.35, 0.0, 0.0, 1.0,
              ],
            },
          ],
          bufferByteLength: baseVerts.length,
        ),
        baseVerts,
      );
      expect(() => parseGlbBinaryOpaque(m10Glb), throwsFormatException);

      // 12 (M11): Two nodes sharing mesh 0 where first node is OOB and second is valid
      final m11Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'm11_first_oob',
              'mesh': 0,
              'translation': <double>[0.4, 0.0, 0.0],
            },
            <String, dynamic>{
              'name': 'm11_second_valid',
              'mesh': 0,
              'translation': <double>[0.0, 0.0, 0.0],
            },
          ],
          sceneNodes: <int>[0, 1],
          bufferByteLength: baseVerts.length,
        ),
        baseVerts,
      );
      expect(() => parseGlbBinaryOpaque(m11Glb), throwsFormatException);

      // 13 (M12): Negative accessor byteOffset must throw FormatException (never RangeError)
      final m12Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{'name': 'm12', 'mesh': 0},
          ],
          bufferByteLength: baseVerts.length,
          accessors: <Map<String, dynamic>>[
            <String, dynamic>{
              'bufferView': 0,
              'byteOffset': -4,
              'componentType': 5126,
              'count': 3,
              'type': 'VEC3',
            },
          ],
        ),
        baseVerts,
      );
      expect(() => parseGlbBinaryOpaque(m12Glb), throwsFormatException);

      // 14 (M13): POSITION accessor overruns bufferView[0] into bufferView[1]
      final m13Bin = Uint8List(48)
        ..setRange(0, baseVerts.length, baseVerts);
      ByteData.sublistView(m13Bin)
        ..setUint16(36, 0, Endian.little)
        ..setUint16(38, 1, Endian.little)
        ..setUint16(40, 2, Endian.little);
      final m13Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{'name': 'm13', 'mesh': 0},
          ],
          bufferByteLength: 48,
          bufferViews: <Map<String, dynamic>>[
            <String, dynamic>{'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
            <String, dynamic>{'buffer': 0, 'byteOffset': 36, 'byteLength': 12},
          ],
          accessors: <Map<String, dynamic>>[
            <String, dynamic>{
              'bufferView': 0,
              'componentType': 5126,
              'count': 4, // overruns bufferView[0] (36 bytes) into bufferView[1]!
              'type': 'VEC3',
            },
            <String, dynamic>{
              'bufferView': 1,
              'componentType': 5123,
              'count': 3,
              'type': 'SCALAR',
            },
          ],
          primitive: <String, dynamic>{
            'attributes': <String, dynamic>{'POSITION': 0},
            'indices': 1,
          },
        ),
        m13Bin,
      );
      expect(() => parseGlbBinaryOpaque(m13Glb), throwsFormatException);

      // 15 (M17): Zero-extent indexed triangles masked by unreferenced 4th vertex
      final m17Verts = _encodeFloat32Vertices(<double>[
        0.0, 0.5, 0.0, // v0 (referenced)
        0.0, 0.5, 0.0, // v1 (referenced)
        0.0, 0.5, 0.0, // v2 (referenced)
        0.3, 1.0, 0.3, // v3 (unreferenced!)
      ]);
      final m17Bin = Uint8List(m17Verts.length + 8)
        ..setRange(0, m17Verts.length, m17Verts);
      ByteData.sublistView(m17Bin)
        ..setUint16(m17Verts.length, 0, Endian.little)
        ..setUint16(m17Verts.length + 2, 1, Endian.little)
        ..setUint16(m17Verts.length + 4, 2, Endian.little);
      final m17Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{'name': 'm17', 'mesh': 0},
          ],
          bufferByteLength: m17Bin.length,
          bufferViews: <Map<String, dynamic>>[
            <String, dynamic>{
              'buffer': 0,
              'byteOffset': 0,
              'byteLength': m17Verts.length,
            },
            <String, dynamic>{
              'buffer': 0,
              'byteOffset': m17Verts.length,
              'byteLength': 8,
            },
          ],
          accessors: <Map<String, dynamic>>[
            <String, dynamic>{
              'bufferView': 0,
              'componentType': 5126,
              'count': 4,
              'type': 'VEC3',
            },
            <String, dynamic>{
              'bufferView': 1,
              'componentType': 5123,
              'count': 3,
              'type': 'SCALAR',
            },
          ],
          primitive: <String, dynamic>{
            'attributes': <String, dynamic>{'POSITION': 0},
            'indices': 1,
          },
        ),
        m17Bin,
      );
      expect(() => parseGlbBinaryOpaque(m17Glb), throwsFormatException);

      // 16 (M16): Valid parent-scaled glTF 2.0 hierarchy bringing child mesh into contract bounds
      final m16Verts = _encodeFloat32Vertices(<double>[
        -0.8, 0.0, -0.8,
        0.8, 2.0, 0.0,
        0.0, 0.0, 0.8,
      ]);
      final m16Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'm16_parent',
              'scale': <double>[0.5, 0.5, 0.5],
              'children': <int>[1],
            },
            <String, dynamic>{'name': 'm16_child', 'mesh': 0},
          ],
          sceneNodes: <int>[0],
          bufferByteLength: m16Verts.length,
        ),
        m16Verts,
      );
      final parsedM16 = parseGlbBinaryOpaque(m16Glb);
      expect(parsedM16.vertexCount, 3);
      expect(parsedM16.minX, closeTo(-0.4, 1e-4));
      expect(parsedM16.maxX, closeTo(0.4, 1e-4));
      expect(parsedM16.minY, closeTo(0.0, 1e-4));
      expect(parsedM16.maxY, closeTo(1.0, 1e-4));
      expect(parsedM16.minZ, closeTo(-0.4, 1e-4));
      expect(parsedM16.maxZ, closeTo(0.4, 1e-4));

      // 17 (E1): int64 overflow in POSITION accessor.count must throw FormatException
      final e1Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{'name': 'e1', 'mesh': 0},
          ],
          bufferByteLength: baseVerts.length,
          accessors: <Map<String, dynamic>>[
            <String, dynamic>{
              'bufferView': 0,
              'componentType': 5126,
              'count': (1 << 60) + 1,
              'type': 'VEC3',
            },
          ],
        ),
        baseVerts,
      );
      expect(() => parseGlbBinaryOpaque(e1Glb), throwsFormatException);

      // 18 (E2): int64 overflow in indices accessor.count must throw FormatException
      final e2Bin = Uint8List(48)
        ..setRange(0, baseVerts.length, baseVerts);
      ByteData.sublistView(e2Bin).setUint32(36, 0, Endian.little);
      final e2Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{'name': 'e2', 'mesh': 0},
          ],
          bufferByteLength: 48,
          bufferViews: <Map<String, dynamic>>[
            <String, dynamic>{'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
            <String, dynamic>{'buffer': 0, 'byteOffset': 36, 'byteLength': 12},
          ],
          accessors: <Map<String, dynamic>>[
            <String, dynamic>{
              'bufferView': 0,
              'componentType': 5126,
              'count': 3,
              'type': 'VEC3',
            },
            <String, dynamic>{
              'bufferView': 1,
              'componentType': 5125,
              'count': (1 << 61) + 1,
              'type': 'SCALAR',
            },
          ],
          primitive: <String, dynamic>{
            'attributes': <String, dynamic>{'POSITION': 0},
            'indices': 1,
          },
        ),
        e2Bin,
      );
      expect(() => parseGlbBinaryOpaque(e2Glb), throwsFormatException);

      // 19 (E3): int64 overflow in bufferView byteOffset + byteLength must throw FormatException
      final e3Glb = _assembleGlb(
        _baseGltfJson(
          nodes: <Map<String, dynamic>>[
            <String, dynamic>{'name': 'e3', 'mesh': 0},
          ],
          bufferByteLength: baseVerts.length,
          bufferViews: <Map<String, dynamic>>[
            <String, dynamic>{
              'buffer': 0,
              'byteOffset': 1 << 62,
              'byteLength': 1 << 62,
            },
          ],
        ),
        baseVerts,
      );
      expect(() => parseGlbBinaryOpaque(e3Glb), throwsFormatException);
    });

    test('T2-12: Manifest structural boundary checks reject duplicates, empty paths, NaN/Infinity, and asset gaps', () {
      final rawManifest = File('assets/models/asset_manifest.json')
          .readAsStringSync();
      expect(rawManifest, isNot(contains('NaN')));
      expect(rawManifest, isNot(contains('Infinity')));

      final manifest = loadAssetManifestJson();

      void assertAllNumbersFinite(Object? node) {
        if (node is num) {
          expect(node.isFinite, isTrue);
        } else if (node is List) {
          for (final item in node) {
            assertAllNumbersFinite(item);
          }
        } else if (node is Map) {
          for (final value in node.values) {
            assertAllNumbersFinite(value);
          }
        }
      }

      assertAllNumbersFinite(manifest);

      final v1Pieces = manifest['pieces'] as List<dynamic>;
      final seenPieceAssetIds = <String>{};
      for (final raw in v1Pieces) {
        final item = Map<String, dynamic>.from(raw as Map);
        final assetId = (item['assetId'] ?? '').toString();
        expect(assetId.trim(), isNotEmpty);
        expect(seenPieceAssetIds.add(assetId), isTrue);
        expect((item['glbPath'] ?? '').toString().trim(), isNotEmpty);
      }
      expect(seenPieceAssetIds, hasLength(22));

      final factionMeshes = extractFactionMeshPaths(manifest);
      expect(factionMeshes, hasLength(121));
      final distinctPaths = factionMeshes.values.toSet();
      expect(distinctPaths, hasLength(121));
      for (final path in distinctPaths) {
        expect(path.startsWith('assets/models/pieces/'), isTrue);
        expect(path.endsWith('.glb'), isTrue);
      }

      final pubspecText = File('pubspec.yaml').readAsStringSync();
      expect(pubspecText, contains('assets/models/asset_manifest.json'));
      expect(pubspecText, contains('assets/models/pieces/'));
    });
  });
}
