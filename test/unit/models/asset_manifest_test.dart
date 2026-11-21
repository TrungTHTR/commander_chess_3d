import 'dart:convert';
import 'dart:io';

import 'package:commander_chess_3d/features/game/models/asset_manifest_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectedMaterialSlots = <String>[
    'mat_faction_primary',
    'mat_faction_accent',
    'mat_base_pedestal',
    'mat_neutral_metal',
    'mat_heroic_emissive',
  ];

  void assertValidManifest(AssetManifest manifest) {
    expect(manifest.schemaVersion, 1);
    expect(manifest.unitScaleMeters, 1.0);
    expect(manifest.boardGlbPath, isNotEmpty);
    expect(manifest.boardRootNodeName, 'board_root');
    expect(manifest.pieces, hasLength(22));

    final seenIds = <String>{};
    for (final side in PlayerSide.values) {
      for (final type in PieceType.values) {
        final key = PieceVisualKey(type: type, side: side, isHero: false);
        final descriptor = manifest.findPiece(key);
        expect(
          descriptor,
          isNotNull,
          reason: 'Missing manifest descriptor for ${side.name} ${type.name}',
        );
        final item = descriptor!;
        expect(seenIds.add(item.assetId), isTrue);

        expect(
          item.glbPath,
          'assets/models/pieces/${type.snakeCaseName}_lod0.glb',
        );
        expect(item.effectiveRootNodeName, 'piece_${type.snakeCaseName}');
        expect(item.boundingRadius, lessThanOrEqualTo(0.425));

        expect(item.lodTiers, hasLength(2));
        final lod0 = item.lodTiers.firstWhere((l) => l.tier == 'lod0');
        final lod1 = item.lodTiers.firstWhere((l) => l.tier == 'lod1');
        expect(
          lod0.assetPath,
          'assets/models/pieces/${type.snakeCaseName}_lod0.glb',
        );
        expect(
          lod1.assetPath,
          'assets/models/pieces/${type.snakeCaseName}_lod1.glb',
        );
        expect(lod0.maxDistanceSq, lessThan(lod1.maxDistanceSq));
        expect(lod0.maxTriangles, greaterThan(0));
        expect(lod1.maxTriangles, greaterThan(0));

        final slotNames = item.materialSlots.map((s) => s.slotName).toList();
        expect(slotNames, containsAll(expectedMaterialSlots));
        expect(item.materialSlots, hasLength(5));

        final pedestalSlot = item.materialSlots.firstWhere(
          (s) => s.slotName == 'mat_base_pedestal',
        );
        final emissiveSlot = item.materialSlots.firstWhere(
          (s) => s.slotName == 'mat_heroic_emissive',
        );
        expect(pedestalSlot.heroicHex, '#FFD54F');
        expect(emissiveSlot.heroicHex, '#FFD54F');

        for (final clip in PieceAnimClip.values) {
          expect(
            item.animations[clip],
            clip.name,
            reason: 'Missing animation clip ${clip.name} on ${item.assetId}',
          );
        }

        if (type.carrierCapacity > 0) {
          expect(
            item.passengerSockets,
            contains('socket_passenger_0'),
            reason: 'Carrier ${item.assetId} must expose socket_passenger_0',
          );
          if (type.carrierCapacity >= 2) {
            expect(
              item.passengerSockets,
              containsAll(<String>[
                'socket_passenger_0',
                'socket_passenger_1',
              ]),
            );
          }
        } else {
          expect(item.passengerSockets, isEmpty);
        }
      }
    }
  }

  group('AssetManifest & Blender asset contract', () {
    test('parses assets/models/asset_manifest.json from disk and validates all 22 descriptors', () {
      final file = File('assets/models/asset_manifest.json');
      expect(file.existsSync(), isTrue);

      final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final manifest = AssetManifest.fromJson(decoded);
      assertValidManifest(manifest);
    });

    test('parses assets/models/asset_manifest.json via Flutter rootBundle', () async {
      final raw = await rootBundle.loadString('assets/models/asset_manifest.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final manifest = AssetManifest.fromJson(decoded);
      assertValidManifest(manifest);
    });

    test('AssetManifest.findPiece performs exact lookup and Hero fallback lookup', () async {
      final raw = await rootBundle.loadString('assets/models/asset_manifest.json');
      final manifest = AssetManifest.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );

      const nonHeroKey = PieceVisualKey(
        type: PieceType.tank,
        side: PlayerSide.red,
        isHero: false,
      );
      const heroKey = PieceVisualKey(
        type: PieceType.tank,
        side: PlayerSide.red,
        isHero: true,
      );

      final baseDescriptor = manifest.findPiece(nonHeroKey);
      final heroFallback = manifest.findPiece(heroKey);
      expect(baseDescriptor, isNotNull);
      expect(heroFallback, baseDescriptor);

      final dedicatedHeroDescriptor = baseDescriptor!.copyWith(
        assetId: 'red_tank_hero',
        visualKey: heroKey,
      );
      final customManifest = manifest.copyWith(
        pieces: <MeshAssetDescriptor>[
          ...manifest.pieces,
          dedicatedHeroDescriptor,
        ],
      );
      expect(customManifest.findPiece(heroKey), dedicatedHeroDescriptor);
      expect(customManifest.findPiece(nonHeroKey), baseDescriptor);

      const emptyManifest = AssetManifest(
        boardGlbPath: 'assets/models/board/commander_board.glb',
        pieces: <MeshAssetDescriptor>[],
      );
      expect(emptyManifest.findPiece(heroKey), isNull);
    });

    test('AssetManifest supports JSON serialization round-trip', () async {
      final raw = await rootBundle.loadString('assets/models/asset_manifest.json');
      final manifest = AssetManifest.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );

      final reserialized = AssetManifest.fromJson(manifest.toJson());
      expect(reserialized, manifest);
    });

    test('AssetManifest.fromJson({}) uses canonical boardGlbPath matching asset_manifest.json', () async {
      final raw = await rootBundle.loadString('assets/models/asset_manifest.json');
      final diskManifest = AssetManifest.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      final defaultManifest = AssetManifest.fromJson(const <String, dynamic>{});

      expect(
        defaultManifest.boardGlbPath,
        'assets/models/board/commander_board_11x12.glb',
      );
      expect(defaultManifest.boardGlbPath, diskManifest.boardGlbPath);
    });

    test('AssetManifest, MeshLodSpec, and MeshAssetDescriptor throw FormatException on 1e999, NaN, and invalid unitScaleMeters', () {
      // JSON 1e999 decodes to double.infinity in Dart.
      final infManifestJson = jsonDecode(
        '{"schemaVersion": 1e999, "pieces": []}',
      ) as Map<String, dynamic>;
      expect(
        () => AssetManifest.fromJson(infManifestJson),
        throwsFormatException,
      );

      expect(
        () => AssetManifest.fromJson(<String, dynamic>{
          'schemaVersion': double.nan,
          'pieces': <Object>[],
        }),
        throwsFormatException,
      );

      // Invalid unitScaleMeters: <= 0, -1e999, 1e999, NaN, or non-numeric.
      final negInfScaleJson = jsonDecode(
        '{"unitScaleMeters": -1e999, "pieces": []}',
      ) as Map<String, dynamic>;
      expect(
        () => AssetManifest.fromJson(negInfScaleJson),
        throwsFormatException,
      );

      for (final badScale in <Object>[
        0,
        0.0,
        -2.5,
        double.infinity,
        double.negativeInfinity,
        double.nan,
        '0',
        '-1.5',
        'NaN',
        'Infinity',
        'not_a_number',
      ]) {
        expect(
          () => AssetManifest.fromJson(<String, dynamic>{
            'unitScaleMeters': badScale,
            'pieces': <Object>[],
          }),
          throwsFormatException,
          reason: 'Expected FormatException for unitScaleMeters=$badScale',
        );
      }

      // MeshLodSpec non-finite maxDistanceSq / maxTriangles.
      final infLodJson = jsonDecode(
        '{"tier": "lod0", "maxDistanceSq": 1e999, "assetPath": "a.glb", "maxTriangles": 1e999}',
      ) as Map<String, dynamic>;
      expect(() => MeshLodSpec.fromJson(infLodJson), throwsFormatException);

      for (final badNum in <Object>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
        'Infinity',
        'NaN',
      ]) {
        expect(
          () => MeshLodSpec.fromJson(<String, dynamic>{
            'maxDistanceSq': badNum,
            'assetPath': 'a.glb',
          }),
          throwsFormatException,
        );
      }
      for (final badInt in <Object>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(
          () => MeshLodSpec.fromJson(<String, dynamic>{
            'maxTriangles': badInt,
            'assetPath': 'a.glb',
          }),
          throwsFormatException,
        );
      }

      // MeshAssetDescriptor non-finite boundingRadius.
      final infMeshJson = jsonDecode(
        '{"assetId": "red_tank", "visualKey": {"type": "tank", "side": "red"}, "glbPath": "tank.glb", "boundingRadius": 1e999}',
      ) as Map<String, dynamic>;
      expect(
        () => MeshAssetDescriptor.fromJson(infMeshJson),
        throwsFormatException,
      );
      for (final badRadius in <Object>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
        'Infinity',
        'NaN',
      ]) {
        expect(
          () => MeshAssetDescriptor.fromJson(<String, dynamic>{
            'assetId': 'red_tank',
            'visualKey': <String, dynamic>{'type': 'tank', 'side': 'red'},
            'glbPath': 'tank.glb',
            'boundingRadius': badRadius,
          }),
          throwsFormatException,
        );
      }
    });
  });
}
