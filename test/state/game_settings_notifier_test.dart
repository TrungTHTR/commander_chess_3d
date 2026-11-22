import 'dart:async';

import 'package:commander_chess_3d/core/result/app_failure.dart';
import 'package:commander_chess_3d/core/result/result.dart';
import 'package:commander_chess_3d/features/game/models/faction_model.dart';
import 'package:commander_chess_3d/features/game/repositories/settings_repository.dart';
import 'package:commander_chess_3d/features/game/state/game_hud_snapshot.dart';
import 'package:commander_chess_3d/features/game/state/game_providers.dart';
import 'package:commander_chess_3d/features/game/state/game_settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _CompleterSettingsRepository implements SettingsRepository {
  _CompleterSettingsRepository({
    this.loadCompleter,
    this.saveCompleter,
    this.resetCompleter,
    this.failOnSave = false,
  });

  final Completer<Result<GameSettings>>? loadCompleter;
  final Completer<Result<GameSettings>>? saveCompleter;
  final Completer<Result<GameSettings>>? resetCompleter;
  final bool failOnSave;
  final InMemorySettingsRepository _inner = InMemorySettingsRepository();

  int saveCalls = 0;
  final List<GameSettings> savedHistory = <GameSettings>[];

  bool get isDisposed => _inner.isDisposed;
  GameSettings get currentSettings => _inner.currentSettings;

  @override
  Future<Result<GameSettings>> loadSettings() {
    if (loadCompleter != null) return loadCompleter!.future;
    return _inner.loadSettings();
  }

  @override
  Future<Result<GameSettings>> saveSettings(GameSettings settings) {
    saveCalls += 1;
    savedHistory.add(settings);
    if (saveCompleter != null) return saveCompleter!.future;
    if (failOnSave) {
      return Future<Result<GameSettings>>.value(
        const Err<GameSettings>(
          ServerAppFailure('Simulated settings save failure', code: 'SAVE_ERR'),
        ),
      );
    }
    return _inner.saveSettings(settings);
  }

  @override
  Future<Result<GameSettings>> resetDefaults() {
    if (resetCompleter != null) return resetCompleter!.future;
    return _inner.resetDefaults();
  }

  @override
  void dispose() => _inner.dispose();
}

void main() {
  group('GameSettingsNotifier (Riverpod ProviderContainer)', () {
    test('exposes default GameSettings initially', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final settings = container.read(gameSettingsProvider);
      expect(settings.redFaction, FactionId.vietnam);
      expect(settings.blueFaction, FactionId.usa);
      expect(settings.defaultCameraPreset, 'classic');
      expect(settings.isDarkMode, isTrue);
      expect(settings.isMirrorMatch, isFalse);
    });

    test('hydrates from seeded repository and prevents stale hydration from overwriting user edits',
        () async {
      final seededRepo = InMemorySettingsRepository(
        initialSettings: const GameSettings(
          redFaction: FactionId.unitedKingdom,
          blueFaction: FactionId.france,
          defaultCameraPreset: 'tacticalTop',
          isDarkMode: false,
        ),
      );
      final container1 = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(seededRepo)],
      );
      addTearDown(container1.dispose);

      // Synchronous build returns defaults, then async hydration applies normalized seeded settings.
      expect(container1.read(gameSettingsProvider), const GameSettings());
      await Future<void>.delayed(Duration.zero);

      final hydrated = container1.read(gameSettingsProvider);
      expect(hydrated.redFaction, FactionId.unitedKingdom);
      expect(hydrated.blueFaction, FactionId.france);
      expect(hydrated.defaultCameraPreset, 'high');
      expect(hydrated.isDarkMode, isFalse);

      // Stale loadSettings() completion must NOT overwrite a newer user selection.
      final loadCompleter = Completer<Result<GameSettings>>();
      final slowLoadRepo =
          _CompleterSettingsRepository(loadCompleter: loadCompleter);
      final container2 = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(slowLoadRepo)],
      );
      addTearDown(container2.dispose);

      final notifier2 = container2.read(gameSettingsProvider.notifier);
      await notifier2.selectRedFaction(FactionId.japan);

      loadCompleter.complete(
        const Ok<GameSettings>(
          GameSettings(
            redFaction: FactionId.china,
            blueFaction: FactionId.india,
            defaultCameraPreset: 'side',
            isDarkMode: false,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container2.read(gameSettingsProvider).redFaction, FactionId.japan);
      expect(container2.read(gameSettingsProvider).blueFaction, FactionId.usa);
    });

    test(
        'Probe 2b regression: explicit default-matching selections during pending loadSettings() are retained and persisted',
        () async {
      const stalePersisted = GameSettings(
        redFaction: FactionId.china,
        blueFaction: FactionId.india,
        defaultCameraPreset: 'side',
        isDarkMode: false,
      );

      // 1. Each mutator independently prevents stale hydration clobbering.
      final mutators =
          <String, Future<void> Function(GameSettingsNotifier notifier)>{
        'selectRedFaction': (notifier) =>
            notifier.selectRedFaction(FactionId.vietnam),
        'selectBlueFaction': (notifier) =>
            notifier.selectBlueFaction(FactionId.usa),
        'setDefaultCameraPreset': (notifier) =>
            notifier.setDefaultCameraPreset('classic'),
        'setDarkMode': (notifier) => notifier.setDarkMode(true),
      };

      for (final entry in mutators.entries) {
        final loadCompleter = Completer<Result<GameSettings>>();
        final slowRepo =
            _CompleterSettingsRepository(loadCompleter: loadCompleter);
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(slowRepo)],
        );

        final notifier = container.read(gameSettingsProvider.notifier);
        await entry.value(notifier);
        expect(slowRepo.saveCalls, 1, reason: '${entry.key} must persist');

        loadCompleter.complete(const Ok<GameSettings>(stalePersisted));
        await Future<void>.delayed(Duration.zero);

        final finalState = container.read(gameSettingsProvider);
        expect(
          finalState,
          const GameSettings(),
          reason: '${entry.key} must block stale loadSettings() overwrite',
        );
        expect(slowRepo.currentSettings, const GameSettings());

        // Once hydration has completed, redundant no-op calls short-circuit.
        await entry.value(notifier);
        expect(
          slowRepo.saveCalls,
          1,
          reason: '${entry.key} should short-circuit after hydration finishes',
        );

        container.dispose();
      }

      // 2. All 4 mutators invoked sequentially while loadSettings() is pending.
      final combinedLoadCompleter = Completer<Result<GameSettings>>();
      final combinedRepo =
          _CompleterSettingsRepository(loadCompleter: combinedLoadCompleter);
      final combinedContainer = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(combinedRepo)],
      );
      addTearDown(combinedContainer.dispose);

      final combinedNotifier =
          combinedContainer.read(gameSettingsProvider.notifier);
      await combinedNotifier.selectRedFaction(FactionId.vietnam);
      await combinedNotifier.selectBlueFaction(FactionId.usa);
      await combinedNotifier.setDefaultCameraPreset('classic');
      await combinedNotifier.setDarkMode(true);

      expect(combinedRepo.saveCalls, 4);

      combinedLoadCompleter.complete(const Ok<GameSettings>(stalePersisted));
      await Future<void>.delayed(Duration.zero);

      final combinedState = combinedContainer.read(gameSettingsProvider);
      expect(combinedState.redFaction, FactionId.vietnam);
      expect(combinedState.blueFaction, FactionId.usa);
      expect(combinedState.defaultCameraPreset, 'classic');
      expect(combinedState.isDarkMode, isTrue);
      expect(combinedRepo.currentSettings, const GameSettings());

      // 3. Hydration Err still marks hydration complete cleanly without throwing.
      final errLoadCompleter = Completer<Result<GameSettings>>();
      final errRepo =
          _CompleterSettingsRepository(loadCompleter: errLoadCompleter);
      final errContainer = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(errRepo)],
      );
      addTearDown(errContainer.dispose);

      final errNotifier = errContainer.read(gameSettingsProvider.notifier);
      errLoadCompleter.complete(
        const Err<GameSettings>(
          ServerAppFailure('Load failed', code: 'LOAD_ERR'),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(errContainer.read(gameSettingsProvider), const GameSettings());
      await errNotifier.selectRedFaction(FactionId.vietnam);
      expect(errRepo.saveCalls, 0);
    });

    test('selectRedFaction and selectBlueFaction support all 11 factions and persist to repository',
        () async {
      final repo = InMemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(gameSettingsProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      for (final red in FactionId.values) {
        await notifier.selectRedFaction(red);
        expect(container.read(gameSettingsProvider).redFaction, red);
        expect(repo.currentSettings.redFaction, red);
      }

      for (final blue in FactionId.values) {
        await notifier.selectBlueFaction(blue);
        expect(container.read(gameSettingsProvider).blueFaction, blue);
        expect(repo.currentSettings.blueFaction, blue);
      }
    });

    test('supports mirror matches and swapFactions across asymmetric and mirror states',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(gameSettingsProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Default vietnam vs usa -> usa vs vietnam -> vietnam vs usa.
      await notifier.swapFactions();
      expect(container.read(gameSettingsProvider).redFaction, FactionId.usa);
      expect(
        container.read(gameSettingsProvider).blueFaction,
        FactionId.vietnam,
      );

      await notifier.swapFactions();
      expect(
        container.read(gameSettingsProvider).redFaction,
        FactionId.vietnam,
      );
      expect(container.read(gameSettingsProvider).blueFaction, FactionId.usa);

      // Custom asymmetric swap.
      await notifier.selectRedFaction(FactionId.unitedKingdom);
      await notifier.selectBlueFaction(FactionId.france);
      await notifier.swapFactions();
      expect(
        container.read(gameSettingsProvider).redFaction,
        FactionId.france,
      );
      expect(
        container.read(gameSettingsProvider).blueFaction,
        FactionId.unitedKingdom,
      );

      // Mirror match.
      await notifier.selectRedFaction(FactionId.southKorea);
      await notifier.selectBlueFaction(FactionId.southKorea);
      expect(container.read(gameSettingsProvider).isMirrorMatch, isTrue);

      await notifier.selectRedFaction(FactionId.israel);
      await notifier.selectBlueFaction(FactionId.israel);
      expect(container.read(gameSettingsProvider).isMirrorMatch, isTrue);
      await notifier.swapFactions();
      expect(
        container.read(gameSettingsProvider).redFaction,
        FactionId.israel,
      );
      expect(
        container.read(gameSettingsProvider).blueFaction,
        FactionId.israel,
      );
      expect(container.read(gameSettingsProvider).isMirrorMatch, isTrue);
    });

    test('validates/normalizes camera presets, maps to OrbitCameraPreset, and ignores invalid inputs',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(gameSettingsProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      expect(kSupportedCameraPresetKeys, ['classic', 'high', 'side', 'top']);

      const expectedMappings = <String, OrbitCameraPreset>{
        'classic': OrbitCameraPreset.redCommander,
        'high': OrbitCameraPreset.tacticalTop,
        'side': OrbitCameraPreset.sideOverview,
        'top': OrbitCameraPreset.blueCommander,
      };

      for (final entry in expectedMappings.entries) {
        await notifier.setDefaultCameraPreset(entry.key);
        expect(
          container.read(gameSettingsProvider).defaultCameraPreset,
          entry.key,
        );
        expect(orbitCameraPresetFromSettingsKey(entry.key), entry.value);
        expect(settingsKeyForOrbitCameraPreset(entry.value), entry.key);
        expect(entry.value.settingsKey, entry.key);
      }

      // Case/whitespace normalization and OrbitCameraPreset.name normalization.
      await notifier.setDefaultCameraPreset(' HIGH ');
      expect(container.read(gameSettingsProvider).defaultCameraPreset, 'high');

      await notifier.setDefaultCameraPreset('sideOverview');
      expect(container.read(gameSettingsProvider).defaultCameraPreset, 'side');

      await notifier.setDefaultCameraPreset('blueCommander');
      expect(container.read(gameSettingsProvider).defaultCameraPreset, 'top');

      await notifier.setDefaultOrbitCameraPreset(OrbitCameraPreset.tacticalTop);
      expect(container.read(gameSettingsProvider).defaultCameraPreset, 'high');

      // Invalid presets do not overwrite current valid preset.
      for (final invalid in <String>['', '   ', 'orbital', 'invalid_preset']) {
        await notifier.setDefaultCameraPreset(invalid);
        expect(
          container.read(gameSettingsProvider).defaultCameraPreset,
          'high',
        );
      }

      // Unknown raw string safely falls back to redCommander.
      expect(
        orbitCameraPresetFromSettingsKey('unknown_preset'),
        OrbitCameraPreset.redCommander,
      );
    });

    test('setDarkMode, toggleDarkMode, and resetDefaults update state and persist',
        () async {
      final repo = InMemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(gameSettingsProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      await notifier.setDarkMode(false);
      expect(container.read(gameSettingsProvider).isDarkMode, isFalse);
      expect(repo.currentSettings.isDarkMode, isFalse);

      await notifier.toggleDarkMode();
      expect(container.read(gameSettingsProvider).isDarkMode, isTrue);
      expect(repo.currentSettings.isDarkMode, isTrue);

      await notifier.selectRedFaction(FactionId.germany);
      await notifier.selectBlueFaction(FactionId.japan);
      await notifier.setDefaultCameraPreset('side');
      await notifier.setDarkMode(false);

      await notifier.resetDefaults();
      final restored = container.read(gameSettingsProvider);
      expect(restored.redFaction, FactionId.vietnam);
      expect(restored.blueFaction, FactionId.usa);
      expect(restored.defaultCameraPreset, 'classic');
      expect(restored.isDarkMode, isTrue);
      expect(restored.isMirrorMatch, isFalse);
      expect(repo.currentSettings, equals(const GameSettings()));
    });

    test('ref.onDispose disposes SettingsRepository and guards async completion when unmounted',
        () async {
      final defaultContainer = ProviderContainer();
      final repo =
          defaultContainer.read(settingsRepositoryProvider)
              as InMemorySettingsRepository;
      defaultContainer.read(gameSettingsProvider);
      expect(repo.isDisposed, isFalse);

      defaultContainer.dispose();
      expect(repo.isDisposed, isTrue);

      // Mid-flight async save/reset disposal safety (ref.mounted guard).
      final saveCompleter = Completer<Result<GameSettings>>();
      final slowRepo =
          _CompleterSettingsRepository(saveCompleter: saveCompleter);
      final asyncContainer = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(slowRepo)],
      );

      final notifier = asyncContainer.read(gameSettingsProvider.notifier);
      final future = notifier.selectRedFaction(FactionId.india);

      asyncContainer.dispose();
      expect(slowRepo.isDisposed, isFalse);

      saveCompleter.complete(
        const Ok<GameSettings>(
          GameSettings(redFaction: FactionId.india),
        ),
      );
      await expectLater(future, completes);

      // Mid-flight resetDefaults disposal safety + save failure tolerance.
      final resetCompleter = Completer<Result<GameSettings>>();
      final slowResetRepo = _CompleterSettingsRepository(
        resetCompleter: resetCompleter,
        failOnSave: true,
      );
      final resetContainer = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(slowResetRepo)],
      );

      final resetNotifier = resetContainer.read(gameSettingsProvider.notifier);
      await resetNotifier.selectBlueFaction(FactionId.germany);
      expect(
        resetContainer.read(gameSettingsProvider).blueFaction,
        FactionId.germany,
      );

      final resetFuture = resetNotifier.resetDefaults();
      resetContainer.dispose();
      resetCompleter.complete(const Ok<GameSettings>(GameSettings()));
      await expectLater(resetFuture, completes);
    });
  });
}
