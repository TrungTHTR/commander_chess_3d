import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/faction_model.dart';
import '../repositories/settings_repository.dart';
import 'game_hud_snapshot.dart';
import 'game_providers.dart';

export 'game_providers.dart' show gameSettingsProvider;

/// Manual Riverpod 3.x notifier managing [GameSettings] with optimistic
/// synchronous state updates, repository hydration, and [ref.mounted] safety.
final class GameSettingsNotifier extends Notifier<GameSettings> {
  int _mutationRevision = 0;
  int _buildRevision = 0;
  bool _isHydrated = false;

  @override
  GameSettings build() {
    final repo = ref.watch(settingsRepositoryProvider);
    _isHydrated = false;
    final buildRevision = ++_mutationRevision;
    _buildRevision = buildRevision;
    unawaited(_hydrateFromRepository(repo, buildRevision));
    return const GameSettings();
  }

  /// Selects the national faction for the Red (Side 1) force.
  Future<void> selectRedFaction(FactionId faction) async {
    if (_isHydrated && state.redFaction == faction) return;
    await _applyAndPersist(state.copyWith(redFaction: faction));
  }

  /// Selects the national faction for the Blue (Side 2) force.
  Future<void> selectBlueFaction(FactionId faction) async {
    if (_isHydrated && state.blueFaction == faction) return;
    await _applyAndPersist(state.copyWith(blueFaction: faction));
  }

  /// Swaps the selected Red and Blue national factions.
  Future<void> swapFactions() async {
    if (_isHydrated && state.redFaction == state.blueFaction) return;
    await _applyAndPersist(
      state.copyWith(
        redFaction: state.blueFaction,
        blueFaction: state.redFaction,
      ),
    );
  }

  /// Updates [GameSettings.defaultCameraPreset] if [preset] normalizes to a
  /// supported camera preset key; invalid or blank values are ignored.
  Future<void> setDefaultCameraPreset(String preset) async {
    final normalized = tryNormalizeSettingsCameraPreset(preset);
    if (normalized == null ||
        (_isHydrated && state.defaultCameraPreset == normalized)) {
      return;
    }
    await _applyAndPersist(
      state.copyWith(defaultCameraPreset: normalized),
    );
  }

  /// Convenience wrapper accepting an [OrbitCameraPreset] directly.
  Future<void> setDefaultOrbitCameraPreset(OrbitCameraPreset preset) =>
      setDefaultCameraPreset(preset.settingsKey);

  /// Updates the preferred UI theme mode flag.
  Future<void> setDarkMode(bool isDarkMode) async {
    if (_isHydrated && state.isDarkMode == isDarkMode) return;
    await _applyAndPersist(state.copyWith(isDarkMode: isDarkMode));
  }

  /// Toggles between dark and light mode preference.
  Future<void> toggleDarkMode() => setDarkMode(!state.isDarkMode);

  /// Restores all user settings back to [GameSettings] defaults.
  Future<void> resetDefaults() async {
    final rev = ++_mutationRevision;
    const defaults = GameSettings();
    if (state != defaults) {
      state = defaults;
    }

    final result = await ref.read(settingsRepositoryProvider).resetDefaults();
    if (!ref.mounted || _mutationRevision != rev) return;

    result.when(
      ok: (saved) {
        if (state != saved) {
          state = saved;
        }
      },
      err: (_) {},
    );
  }

  Future<void> _hydrateFromRepository(
    SettingsRepository repo,
    int revisionAtStart,
  ) async {
    final result = await repo.loadSettings();
    if (!ref.mounted) return;
    if (_buildRevision == revisionAtStart) {
      _isHydrated = true;
    }
    if (_mutationRevision != revisionAtStart) return;

    result.when(
      ok: (loaded) {
        final normalizedPreset =
            tryNormalizeSettingsCameraPreset(loaded.defaultCameraPreset) ??
                GameSettings.defaultPresetName;
        final sanitized = loaded.defaultCameraPreset == normalizedPreset
            ? loaded
            : loaded.copyWith(defaultCameraPreset: normalizedPreset);
        if (state != sanitized) {
          state = sanitized;
        }
      },
      err: (_) {},
    );
  }

  Future<void> _applyAndPersist(GameSettings next) async {
    final rev = ++_mutationRevision;
    state = next;

    final result = await ref.read(settingsRepositoryProvider).saveSettings(next);
    if (!ref.mounted || _mutationRevision != rev) return;

    result.when(
      ok: (saved) {
        if (state != saved) {
          state = saved;
        }
      },
      err: (_) {},
    );
  }
}
