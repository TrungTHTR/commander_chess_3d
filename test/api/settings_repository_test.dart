import 'dart:io';

import 'package:commander_chess_3d/core/result/app_failure.dart';
import 'package:commander_chess_3d/features/game/models/faction_model.dart';
import 'package:commander_chess_3d/features/game/models/game_state_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:commander_chess_3d/features/game/repositories/settings_repository.dart';
import 'package:commander_chess_3d/features/game/rules/board_topology.dart';
import 'package:commander_chess_3d/features/game/rules/commander_rules_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemorySettingsRepository', () {
    test('returns default GameSettings on fresh load and supports custom seeding',
        () async {
      final repo = InMemorySettingsRepository();
      addTearDown(repo.dispose);

      final loaded = await repo.loadSettings();
      expect(loaded.isOk, isTrue);
      final settings = loaded.valueOrNull!;
      expect(settings.redFaction, FactionId.vietnam);
      expect(settings.blueFaction, FactionId.usa);
      expect(settings.defaultCameraPreset, 'classic');
      expect(settings.isDarkMode, isTrue);
      expect(settings.isMirrorMatch, isFalse);

      const seeded = GameSettings(
        redFaction: FactionId.unitedKingdom,
        blueFaction: FactionId.france,
        defaultCameraPreset: 'high',
        isDarkMode: false,
      );
      final seededRepo = InMemorySettingsRepository(initialSettings: seeded);
      addTearDown(seededRepo.dispose);

      final seededResult = await seededRepo.loadSettings();
      expect(seededResult.valueOrNull, equals(seeded));
      expect(seededRepo.currentSettings, equals(seeded));
    });

    test('saveSettings and loadSettings round-trip all 11 factions and supported presets',
        () async {
      final repo = InMemorySettingsRepository();
      addTearDown(repo.dispose);

      for (var i = 0; i < FactionId.values.length; i++) {
        final red = FactionId.values[i];
        final blue = FactionId.values[(i + 3) % FactionId.values.length];
        final preset = InMemorySettingsRepository.supportedCameraPresets
            .elementAt(
              i % InMemorySettingsRepository.supportedCameraPresets.length,
            );
        final candidate = GameSettings(
          redFaction: red,
          blueFaction: blue,
          defaultCameraPreset: preset,
          isDarkMode: i.isEven,
        );

        final saved = await repo.saveSettings(candidate);
        expect(saved.isOk, isTrue);
        expect(saved.valueOrNull, equals(candidate));

        final loaded = await repo.loadSettings();
        expect(loaded.valueOrNull, equals(candidate));
      }

      for (final preset in InMemorySettingsRepository.supportedCameraPresets) {
        final saved = await repo.saveSettings(
          GameSettings(defaultCameraPreset: preset),
        );
        expect(saved.isOk, isTrue);
        expect(saved.valueOrNull?.defaultCameraPreset, preset);
      }
    });

    test('supports mirror matches where redFaction == blueFaction', () async {
      final repo = InMemorySettingsRepository();
      addTearDown(repo.dispose);

      const mirrorSettings = GameSettings(
        redFaction: FactionId.israel,
        blueFaction: FactionId.israel,
        defaultCameraPreset: 'side',
        isDarkMode: true,
      );
      final saved = await repo.saveSettings(mirrorSettings);
      expect(saved.isOk, isTrue);
      expect(saved.valueOrNull?.isMirrorMatch, isTrue);

      final loaded = await repo.loadSettings();
      expect(loaded.valueOrNull, equals(mirrorSettings));
      expect(loaded.valueOrNull?.isMirrorMatch, isTrue);
    });

    test('trims whitespace on valid presets and rejects blank/unknown presets without corrupting prior state',
        () async {
      final repo = InMemorySettingsRepository();
      addTearDown(repo.dispose);

      const initialValid = GameSettings(
        redFaction: FactionId.germany,
        blueFaction: FactionId.japan,
        defaultCameraPreset: '  high  ',
        isDarkMode: false,
      );
      final savedValid = await repo.saveSettings(initialValid);
      expect(savedValid.isOk, isTrue);
      expect(savedValid.valueOrNull?.defaultCameraPreset, 'high');

      for (final invalidPreset in <String>['', '   ', 'invalid_preset']) {
        final rejected = await repo.saveSettings(
          GameSettings(
            redFaction: FactionId.china,
            blueFaction: FactionId.india,
            defaultCameraPreset: invalidPreset,
            isDarkMode: true,
          ),
        );
        expect(rejected.isErr, isTrue);
        final failure = rejected.failureOrNull;
        expect(failure, isA<ValidationAppFailure>());
        final validation = failure! as ValidationAppFailure;
        expect(validation.code, 'INVALID_CAMERA_PRESET');
        expect(validation.fieldErrors.containsKey('defaultCameraPreset'), isTrue);

        // Prior saved settings must remain intact.
        final current = await repo.loadSettings();
        expect(current.valueOrNull?.redFaction, FactionId.germany);
        expect(current.valueOrNull?.blueFaction, FactionId.japan);
        expect(current.valueOrNull?.defaultCameraPreset, 'high');
        expect(current.valueOrNull?.isDarkMode, isFalse);
      }
    });

    test('resetDefaults restores factory defaults and does not mutate prior snapshots',
        () async {
      final repo = InMemorySettingsRepository();
      addTearDown(repo.dispose);

      const custom = GameSettings(
        redFaction: FactionId.germany,
        blueFaction: FactionId.japan,
        defaultCameraPreset: 'high',
        isDarkMode: false,
      );
      final saved = await repo.saveSettings(custom);
      final priorSnapshot = saved.valueOrNull!;

      final reset = await repo.resetDefaults();
      expect(reset.isOk, isTrue);
      expect(reset.valueOrNull, equals(const GameSettings()));

      final reloaded = await repo.loadSettings();
      expect(reloaded.valueOrNull, equals(const GameSettings()));
      expect(priorSnapshot, equals(custom));
    });

    test('dispose is idempotent and guards loadSettings, saveSettings, and resetDefaults',
        () async {
      final repo = InMemorySettingsRepository();
      expect(repo.isDisposed, isFalse);

      repo.dispose();
      expect(repo.isDisposed, isTrue);
      // Idempotent second call.
      repo.dispose();
      expect(repo.isDisposed, isTrue);

      final loadAfterDispose = await repo.loadSettings();
      expect(loadAfterDispose.isErr, isTrue);
      expect(loadAfterDispose.failureOrNull, isA<ValidationAppFailure>());
      expect(loadAfterDispose.failureOrNull?.code, 'REPOSITORY_DISPOSED');

      final saveAfterDispose = await repo.saveSettings(const GameSettings());
      expect(saveAfterDispose.isErr, isTrue);
      expect(saveAfterDispose.failureOrNull, isA<ValidationAppFailure>());
      expect(saveAfterDispose.failureOrNull?.code, 'REPOSITORY_DISPOSED');

      final resetAfterDispose = await repo.resetDefaults();
      expect(resetAfterDispose.isErr, isTrue);
      expect(resetAfterDispose.failureOrNull, isA<ValidationAppFailure>());
      expect(resetAfterDispose.failureOrNull?.code, 'REPOSITORY_DISPOSED');
    });

    test('OpenAPI FactionId enum and GameSessionState schema match Dart models',
        () {
      final specFile = File('openapi/commander_chess_v1.yaml');
      expect(specFile.existsSync(), isTrue);
      final schemas = _parseOpenApiSchemas(specFile.readAsStringSync());

      expect(schemas.containsKey('FactionId'), isTrue);
      expect(
        schemas['FactionId']!.enumValues,
        equals(FactionId.values.map((e) => e.name).toList()),
      );

      final rules = const StarterCommanderRulesEngine(
        topology: StandardCommanderBoardTopology(),
      );
      final baseSession = rules.createInitialSession(matchId: 'openapi_parity');
      final fullSession = baseSession.copyWith(
        winner: PlayerSide.red,
        victoryReason: VictoryReason.commanderCaptured,
        redFaction: FactionId.unitedKingdom,
        blueFaction: FactionId.france,
      );

      final sessionSchema = schemas['GameSessionState']!;
      expect(
        fullSession.toJson().keys.toSet(),
        equals(sessionSchema.properties),
      );
      expect(
        baseSession.toJson().keys.toSet(),
        containsAll(sessionSchema.required),
      );
      expect(sessionSchema.required.contains('redFaction'), isFalse);
      expect(sessionSchema.required.contains('blueFaction'), isFalse);
    });
  });
}

final class _OpenApiSchemaDef {
  final Set<String> properties = <String>{};
  final Set<String> required = <String>{};
  final List<String> enumValues = <String>[];
}

Map<String, _OpenApiSchemaDef> _parseOpenApiSchemas(String yaml) {
  final lines = yaml.replaceAll('\r\n', '\n').split('\n');
  final schemas = <String, _OpenApiSchemaDef>{};

  var inComponents = false;
  var inSchemas = false;
  String? currentSchema;
  String? currentSection;

  for (final rawLine in lines) {
    final trimmedRight = rawLine.trimRight();
    if (trimmedRight.trim().isEmpty ||
        trimmedRight.trimLeft().startsWith('#')) {
      continue;
    }

    final indent = rawLine.length - rawLine.trimLeft().length;
    final trimmed = trimmedRight.trim();

    if (indent == 0) {
      inComponents = trimmed == 'components:';
      inSchemas = false;
      currentSchema = null;
      currentSection = null;
      continue;
    }
    if (!inComponents) continue;

    if (indent == 2) {
      inSchemas = trimmed == 'schemas:';
      currentSchema = null;
      currentSection = null;
      continue;
    }
    if (!inSchemas) continue;

    if (indent == 4 && trimmed.endsWith(':')) {
      currentSchema = trimmed.substring(0, trimmed.length - 1);
      schemas[currentSchema] = _OpenApiSchemaDef();
      currentSection = null;
      continue;
    }
    if (currentSchema == null) continue;

    if (indent == 6) {
      if (trimmed == 'properties:') {
        currentSection = 'properties';
      } else if (trimmed == 'required:') {
        currentSection = 'required';
      } else if (trimmed == 'enum:') {
        currentSection = 'enum';
      } else {
        currentSection = null;
      }
      continue;
    }

    if (indent == 8) {
      final def = schemas[currentSchema]!;
      if (currentSection == 'properties' && trimmed.endsWith(':')) {
        def.properties.add(trimmed.substring(0, trimmed.length - 1));
      } else if (currentSection == 'required' && trimmed.startsWith('- ')) {
        def.required.add(trimmed.substring(2).trim());
      } else if (currentSection == 'enum' && trimmed.startsWith('- ')) {
        def.enumValues.add(trimmed.substring(2).trim());
      }
    }
  }

  return schemas;
}
