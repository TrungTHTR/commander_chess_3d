import 'dart:convert';

import 'package:commander_chess_3d/core/result/app_failure.dart';
import 'package:commander_chess_3d/features/game/models/asset_manifest_model.dart';
import 'package:commander_chess_3d/features/game/models/faction_model.dart';
import 'package:commander_chess_3d/features/game/models/game_state_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:commander_chess_3d/features/game/repositories/asset_manifest_loader.dart';
import 'package:commander_chess_3d/features/game/rules/board_topology.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' hide AssetManifest;
import 'package:flutter_test/flutter_test.dart';

final class _MockAssetBundle extends CachingAssetBundle {
  _MockAssetBundle(this._strings);

  final Map<String, String> _strings;

  @override
  Future<ByteData> load(String key) async {
    final text = _strings[key];
    if (text == null) {
      throw FlutterError('Missing asset: $key');
    }
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final text = _strings[key];
    if (text == null) {
      throw FlutterError('Missing asset: $key');
    }
    return text;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FactionId & FactionCatalog', () {
    test('defines all 11 factions in exact order with unique metadata', () {
      expect(FactionId.values, const <FactionId>[
        FactionId.usa,
        FactionId.vietnam,
        FactionId.sovietUnion,
        FactionId.unitedKingdom,
        FactionId.germany,
        FactionId.france,
        FactionId.china,
        FactionId.japan,
        FactionId.southKorea,
        FactionId.india,
        FactionId.israel,
      ]);

      expect(FactionCatalog.all, hasLength(11));

      final codes = <String>{};
      final displayNames = <String>{};
      final shortCodes = <String>{};

      for (final factionId in FactionId.values) {
        final def = FactionCatalog.of(factionId);
        expect(def.id, factionId);
        expect(def.code, matches(RegExp(r'^[a-z]+(_[a-z]+)*$')));
        expect(def.displayName.trim(), isNotEmpty);
        expect(def.shortCode.trim(), isNotEmpty);
        expect(def.doctrineSummary.trim(), isNotEmpty);

        expect(codes.add(def.code), isTrue);
        expect(displayNames.add(def.displayName), isTrue);
        expect(shortCodes.add(def.shortCode), isTrue);
      }

      expect(codes, hasLength(11));
      expect(displayNames, hasLength(11));
      expect(shortCodes, hasLength(11));
    });

    test('parses FactionId defensively across code, name, shortCode, and invalid inputs', () {
      expect(FactionId.tryFromJsonValue('usa'), FactionId.usa);
      expect(FactionId.tryFromJsonValue('vietnam'), FactionId.vietnam);
      expect(FactionId.tryFromJsonValue('soviet_union'), FactionId.sovietUnion);
      expect(FactionId.tryFromJsonValue('sovietUnion'), FactionId.sovietUnion);
      expect(
        FactionId.tryFromJsonValue('  Soviet_Union  '),
        FactionId.sovietUnion,
      );
      expect(FactionId.tryFromJsonValue('USSR'), FactionId.sovietUnion);
      expect(FactionId.tryFromJsonValue('vn'), FactionId.vietnam);
      expect(FactionId.tryFromJsonValue('UK'), FactionId.unitedKingdom);
      expect(FactionId.tryFromJsonValue('South Korea'), FactionId.southKorea);

      for (final invalid in <Object?>[
        null,
        '',
        '   ',
        'unknown_nation',
        123,
        const <String, dynamic>{},
      ]) {
        expect(FactionId.tryFromJsonValue(invalid), isNull);
        expect(
          FactionId.fromJsonValue(invalid, fallback: FactionId.usa),
          FactionId.usa,
        );
      }
    });

    test('exposes 121 distinct unit profiles across 11 factions × 11 PieceTypes', () {
      expect(FactionCatalog.allUnitProfiles, hasLength(121));

      final allDesignations = <String>{};
      for (final factionId in FactionId.values) {
        final definition = FactionCatalog.of(factionId);
        expect(definition.units, hasLength(PieceType.values.length));

        for (final pieceType in PieceType.values) {
          final profile = FactionCatalog.unitOf(factionId, pieceType);
          expect(profile, definition.unitFor(pieceType));
          expect(profile.faction, factionId);
          expect(profile.pieceType, pieceType);
          expect(profile.unitDesignation.trim(), isNotEmpty);
          expect(profile.equipmentSummary.trim(), isNotEmpty);
          expect(profile.roleSilhouetteTag.trim(), isNotEmpty);
          expect(
            allDesignations.add(profile.unitDesignation),
            isTrue,
            reason:
                'Duplicate unitDesignation "${profile.unitDesignation}" on ${factionId.code}.${pieceType.name}',
          );
        }
      }

      expect(allDesignations, hasLength(121));
    });

    test('resolves all 19 units per side from kStandardCommanderFen across all 11 factions', () {
      final standardPieces = parseFenPieces(kStandardCommanderFen);
      final redPieces =
          standardPieces.where((p) => p.side == PlayerSide.red).toList();
      final bluePieces =
          standardPieces.where((p) => p.side == PlayerSide.blue).toList();

      expect(standardPieces, hasLength(38));
      expect(redPieces, hasLength(19));
      expect(bluePieces, hasLength(19));

      for (final factionId in FactionId.values) {
        for (final piece in redPieces) {
          final profile = FactionCatalog.unitOf(factionId, piece.type);
          expect(profile.faction, factionId);
          expect(profile.pieceType, piece.type);
        }
        for (final piece in bluePieces) {
          final profile = FactionCatalog.unitOf(factionId, piece.type);
          expect(profile.faction, factionId);
          expect(profile.pieceType, piece.type);
        }
      }
    });

    test('validates opaque ARGB FactionColorPalette and model JSON round-trips', () {
      for (final factionId in FactionId.values) {
        final palette = FactionCatalog.of(factionId).palette;
        for (final hex in <int>[
          palette.primaryHex,
          palette.accentHex,
          palette.uniformHex,
          palette.neutralMetalHex,
          palette.emblemHex,
        ]) {
          expect(hex >>> 24, 0xFF);
        }
        expect(palette.primaryHex, isNot(palette.accentHex));
        expect(
          FactionColorPalette.fromJson(palette.toJson()),
          palette,
        );
      }

      final usaDef = FactionCatalog.of(FactionId.usa);
      expect(FactionDefinition.fromJson(usaDef.toJson()), usaDef);

      final modifiedDef = usaDef.copyWith(
        palette: usaDef.palette.copyWith(accentHex: 0xFFFFFFFF),
      );
      expect(modifiedDef.palette.accentHex, 0xFFFFFFFF);
      expect(modifiedDef, isNot(usaDef));

      final emptyDef = FactionDefinition(
        id: FactionId.usa,
        palette: usaDef.palette,
        units: const <PieceType, FactionUnitProfile>{},
      );
      expect(() => emptyDef.unitFor(PieceType.tank), throwsStateError);
    });
  });

  group('GameSettings', () {
    test('provides safe defaults, mirror match detection, and JSON round-trip', () {
      const defaults = GameSettings();
      expect(defaults.redFaction, FactionId.vietnam);
      expect(defaults.blueFaction, FactionId.usa);
      expect(defaults.defaultCameraPreset, 'classic');
      expect(defaults.isDarkMode, isTrue);
      expect(defaults.isMirrorMatch, isFalse);
      expect(defaults.factionFor(PlayerSide.red), FactionId.vietnam);
      expect(defaults.factionFor(PlayerSide.blue), FactionId.usa);

      final mirror = defaults.copyWith(blueFaction: FactionId.vietnam);
      expect(mirror.isMirrorMatch, isTrue);
      expect(mirror.factionFor(PlayerSide.blue), FactionId.vietnam);

      final custom = defaults.copyWith(
        redFaction: FactionId.sovietUnion,
        blueFaction: FactionId.germany,
        defaultCameraPreset: 'tacticalTop',
        isDarkMode: false,
      );
      expect(GameSettings.fromJson(custom.toJson()), custom);

      final snakeParsed = GameSettings.fromJson(const <String, dynamic>{
        'red_faction': 'united_kingdom',
        'blue_faction': 'JP',
        'default_camera_preset': 'sideOverview',
        'is_dark_mode': 'false',
      });
      expect(snakeParsed.redFaction, FactionId.unitedKingdom);
      expect(snakeParsed.blueFaction, FactionId.japan);
      expect(snakeParsed.defaultCameraPreset, 'sideOverview');
      expect(snakeParsed.isDarkMode, isFalse);

      final fallback = GameSettings.fromJson(const <String, dynamic>{
        'redFaction': 'bogus',
        'blueFaction': 999,
        'defaultCameraPreset': '   ',
      });
      expect(fallback, defaults);
    });
  });

  group('PieceVisualKey, AssetManifest & BundledAssetManifestLoader', () {
    test('PieceVisualKey includes faction in equality, hashCode, copyWith, and JSON', () {
      const baseKey = PieceVisualKey(
        type: PieceType.tank,
        side: PlayerSide.red,
      );
      const usaKey = PieceVisualKey(
        type: PieceType.tank,
        side: PlayerSide.red,
        faction: FactionId.usa,
      );
      const vnKey = PieceVisualKey(
        type: PieceType.tank,
        side: PlayerSide.red,
        faction: FactionId.vietnam,
      );

      expect(baseKey, isNot(usaKey));
      expect(usaKey, isNot(vnKey));
      expect(usaKey.hashCode, isNot(baseKey.hashCode));

      expect(baseKey.copyWith(faction: FactionId.usa), usaKey);
      expect(usaKey.copyWith(clearFaction: true), baseKey);

      expect(baseKey.toJson().containsKey('faction'), isFalse);
      expect(usaKey.toJson()['faction'], 'usa');
      expect(PieceVisualKey.fromJson(baseKey.toJson()), baseKey);
      expect(PieceVisualKey.fromJson(usaKey.toJson()), usaKey);
    });

    test('bundled asset_manifest.json preserves 22 base pieces and adds all 121 factionMeshes', () async {
      const strictLoader = BundledAssetManifestLoader(
        requireFactionMeshes: true,
      );
      final result = await strictLoader.loadManifest();
      expect(result.isOk, isTrue);

      final manifest = result.valueOrNull!;
      expect(manifest.schemaVersion, 1);
      expect(manifest.pieces, hasLength(22));
      expect(manifest.factionMeshes, hasLength(11));

      for (final faction in FactionId.values) {
        expect(manifest.factionMeshes[faction], hasLength(11));
        for (final type in PieceType.values) {
          final expectedPath =
              'assets/models/pieces/${faction.code}_${type.snakeCaseName}_lod0.glb';
          expect(manifest.findFactionMeshPath(faction, type), expectedPath);
          expect(
            manifest.resolveGlbPath(
              PieceVisualKey(
                type: type,
                side: PlayerSide.red,
                faction: faction,
              ),
            ),
            expectedPath,
          );
        }
      }

      // findPiece falls back to base 22 entries when key.faction is populated.
      final redTankBase = manifest.findPiece(
        const PieceVisualKey(type: PieceType.tank, side: PlayerSide.red),
      );
      expect(redTankBase, isNotNull);
      expect(
        manifest.findPiece(
          const PieceVisualKey(
            type: PieceType.tank,
            side: PlayerSide.red,
            isHero: true,
            faction: FactionId.israel,
          ),
        ),
        redTankBase,
      );

      expect(AssetManifest.fromJson(manifest.toJson()), manifest);
    });

    test('BundledAssetManifestLoader validates optional vs required factionMeshes', () async {
      const minimalV1Json =
          '{"schemaVersion":1,"boardGlbPath":"assets/models/board/b.glb","pieces":[{"assetId":"red_commander","visualKey":{"type":"commander","side":"red"},"glbPath":"assets/models/pieces/commander_lod0.glb"}]}';

      final optionalLoader = BundledAssetManifestLoader(
        bundle: _MockAssetBundle(<String, String>{
          BundledAssetManifestLoader.defaultManifestPath: minimalV1Json,
        }),
      );
      final optionalResult = await optionalLoader.loadManifest();
      expect(optionalResult.isOk, isTrue);

      final requiredLoader = BundledAssetManifestLoader(
        bundle: _MockAssetBundle(<String, String>{
          BundledAssetManifestLoader.defaultManifestPath: minimalV1Json,
        }),
        requireFactionMeshes: true,
      );
      final requiredResult = await requiredLoader.loadManifest();
      expect(requiredResult.isErr, isTrue);
      final requiredFailure =
          requiredResult.failureOrNull! as ValidationAppFailure;
      expect(requiredFailure.code, 'INVALID_ASSET_MANIFEST_SCHEMA');
      expect(requiredFailure.fieldErrors.keys, contains('factionMeshes'));

      // Invalid factionMeshes with missing factions & wrong path.
      final invalidFactionMeshesJson = jsonEncode(<String, dynamic>{
        'schemaVersion': 1,
        'boardGlbPath': 'assets/models/board/b.glb',
        'pieces': <Map<String, dynamic>>[
          <String, dynamic>{
            'assetId': 'red_commander',
            'visualKey': <String, dynamic>{
              'type': 'commander',
              'side': 'red',
            },
            'glbPath': 'assets/models/pieces/commander_lod0.glb',
          },
        ],
        'factionMeshes': <String, dynamic>{
          'usa': <String, dynamic>{
            'commander': 'assets/models/pieces/wrong_path.glb',
          },
          'atlantis': <String, dynamic>{},
        },
      });
      final badFactionLoader = BundledAssetManifestLoader(
        bundle: _MockAssetBundle(<String, String>{
          BundledAssetManifestLoader.defaultManifestPath:
              invalidFactionMeshesJson,
        }),
      );
      final badFactionResult = await badFactionLoader.loadManifest();
      expect(badFactionResult.isErr, isTrue);
      final badFailure =
          badFactionResult.failureOrNull! as ValidationAppFailure;
      expect(badFailure.code, 'INVALID_ASSET_MANIFEST_SCHEMA');
      expect(
        badFailure.fieldErrors.keys,
        containsAll(<String>[
          'factionMeshes.atlantis',
          'factionMeshes.usa.commander',
          'factionMeshes.usa.tank',
          'factionMeshes.vietnam',
        ]),
      );
    });
  });

  group('GameSessionState faction support', () {
    test('defaults to vietnam vs usa, supports copyWith/Equatable, and stays v1 JSON compatible', () {
      const baseState = GameSessionState(
        matchId: 'm_faction_1',
        mode: GameMode.localPassAndPlay,
        pieces: <PieceEntity>[],
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
      );

      expect(baseState.redFaction, FactionId.vietnam);
      expect(baseState.blueFaction, FactionId.usa);
      expect(baseState.factionFor(PlayerSide.red), FactionId.vietnam);
      expect(baseState.factionFor(PlayerSide.blue), FactionId.usa);

      final customState = baseState.copyWith(
        redFaction: FactionId.sovietUnion,
        blueFaction: FactionId.france,
      );
      expect(customState.redFaction, FactionId.sovietUnion);
      expect(customState.blueFaction, FactionId.france);
      expect(customState, isNot(baseState));
      expect(GameSessionState.fromJson(customState.toJson()), customState);

      final legacyV1State = GameSessionState.fromJson(const <String, dynamic>{
        'matchId': 'm_legacy_v1',
        'mode': 'localPassAndPlay',
        'boardRanks': 12,
        'boardFiles': 11,
        'pieces': <Object>[],
        'currentTurn': 'red',
        'phase': 'playing',
        'moveHistory': <Object>[],
        'turnNumber': 1,
      });
      expect(legacyV1State.redFaction, FactionId.vietnam);
      expect(legacyV1State.blueFaction, FactionId.usa);

      final snakeInvalidState =
          GameSessionState.fromJson(const <String, dynamic>{
        'matchId': 'm_snake_1',
        'red_faction': 'south_korea',
        'blue_faction': 'unknown_faction',
      });
      expect(snakeInvalidState.redFaction, FactionId.southKorea);
      expect(snakeInvalidState.blueFaction, FactionId.usa);
    });
  });
}
