import '../../../core/result/app_failure.dart';
import '../../../core/result/result.dart';
import '../models/faction_model.dart';

/// Persistence contract for user-selected factions, camera preset, and theme.
abstract interface class SettingsRepository {
  /// Loads the currently persisted [GameSettings].
  Future<Result<GameSettings>> loadSettings();

  /// Validates and persists [settings].
  Future<Result<GameSettings>> saveSettings(GameSettings settings);

  /// Restores [GameSettings] back to factory defaults.
  Future<Result<GameSettings>> resetDefaults();

  /// Releases any backing resources held by this repository.
  void dispose();
}

/// Pure-Dart in-memory [SettingsRepository] suitable for local state and tests.
final class InMemorySettingsRepository implements SettingsRepository {
  /// Canonical contract keys plus [OrbitCameraPreset] enum names.
  static const Set<String> supportedCameraPresets = <String>{
    'classic',
    'high',
    'side',
    'top',
    'redCommander',
    'blueCommander',
    'tacticalTop',
    'sideOverview',
  };

  InMemorySettingsRepository({
    GameSettings initialSettings = const GameSettings(),
  }) : _current = initialSettings;

  GameSettings _current;
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  GameSettings get currentSettings => _current;

  @override
  Future<Result<GameSettings>> loadSettings() async {
    if (_isDisposed) {
      return const Err<GameSettings>(
        ValidationAppFailure(
          'SettingsRepository has been disposed.',
          code: 'REPOSITORY_DISPOSED',
        ),
      );
    }
    return Ok<GameSettings>(_current);
  }

  @override
  Future<Result<GameSettings>> saveSettings(GameSettings settings) async {
    if (_isDisposed) {
      return const Err<GameSettings>(
        ValidationAppFailure(
          'SettingsRepository has been disposed.',
          code: 'REPOSITORY_DISPOSED',
        ),
      );
    }

    final trimmedPreset = settings.defaultCameraPreset.trim();
    if (trimmedPreset.isEmpty ||
        !supportedCameraPresets.contains(trimmedPreset)) {
      return Err<GameSettings>(
        ValidationAppFailure(
          'Invalid defaultCameraPreset "${settings.defaultCameraPreset}".',
          code: 'INVALID_CAMERA_PRESET',
          fieldErrors: <String, String>{
            'defaultCameraPreset':
                'Must be one of: ${supportedCameraPresets.join(', ')}.',
          },
        ),
      );
    }

    final normalized = trimmedPreset == settings.defaultCameraPreset
        ? settings
        : settings.copyWith(defaultCameraPreset: trimmedPreset);
    _current = normalized;
    return Ok<GameSettings>(_current);
  }

  @override
  Future<Result<GameSettings>> resetDefaults() async {
    if (_isDisposed) {
      return const Err<GameSettings>(
        ValidationAppFailure(
          'SettingsRepository has been disposed.',
          code: 'REPOSITORY_DISPOSED',
        ),
      );
    }

    _current = const GameSettings();
    return Ok<GameSettings>(_current);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
  }
}
