import 'package:equatable/equatable.dart';

import '../models/action_model.dart';
import '../models/board_coord.dart';
import '../models/faction_model.dart';
import '../models/game_state_model.dart';
import '../models/piece_model.dart';

/// Discrete camera presets selectable from the HUD for the 3D orbit camera.
enum OrbitCameraPreset {
  redCommander,
  blueCommander,
  tacticalTop,
  sideOverview,
}

/// Canonical settings camera preset keys supported across the settings UI and repository.
const List<String> kSupportedCameraPresetKeys = <String>[
  'classic',
  'high',
  'side',
  'top',
];

/// Normalizes a settings key or [OrbitCameraPreset.name] string into one of
/// `'classic'`, `'high'`, `'side'`, or `'top'`, returning `null` if invalid.
String? tryNormalizeSettingsCameraPreset(String rawPreset) {
  final normalized = rawPreset
      .trim()
      .toLowerCase()
      .replaceAll('_', '')
      .replaceAll('-', '')
      .replaceAll(' ', '');
  return switch (normalized) {
    'classic' || 'redcommander' || 'red' => 'classic',
    'high' || 'tacticaltop' => 'high',
    'side' || 'sideoverview' => 'side',
    'top' || 'bluecommander' || 'blue' => 'top',
    _ => null,
  };
}

/// Maps a settings camera preset key (or [OrbitCameraPreset.name]) to [OrbitCameraPreset].
///
/// Falls back to [OrbitCameraPreset.redCommander] for unrecognized inputs.
OrbitCameraPreset orbitCameraPresetFromSettingsKey(String rawPreset) {
  return switch (tryNormalizeSettingsCameraPreset(rawPreset)) {
    'classic' => OrbitCameraPreset.redCommander,
    'high' => OrbitCameraPreset.tacticalTop,
    'side' => OrbitCameraPreset.sideOverview,
    'top' => OrbitCameraPreset.blueCommander,
    _ => OrbitCameraPreset.redCommander,
  };
}

/// Maps an [OrbitCameraPreset] back to its canonical settings key.
String settingsKeyForOrbitCameraPreset(OrbitCameraPreset preset) {
  return switch (preset) {
    OrbitCameraPreset.redCommander => 'classic',
    OrbitCameraPreset.tacticalTop => 'high',
    OrbitCameraPreset.sideOverview => 'side',
    OrbitCameraPreset.blueCommander => 'top',
  };
}

extension OrbitCameraPresetSettingsX on OrbitCameraPreset {
  /// Canonical settings key (`'classic'`, `'high'`, `'side'`, or `'top'`) for this preset.
  String get settingsKey => settingsKeyForOrbitCameraPreset(this);
}

/// Cold, immutable HUD snapshot managed by [GameSessionNotifier].
///
/// Continuous 60/120Hz camera orbit physics and piece animations live in
/// `engine/`, while Riverpod tracks only discrete turn and HUD state here.
final class GameHudSnapshot extends Equatable {
  const GameHudSnapshot({
    required this.session,
    this.selectedCoord,
    this.legalHints = const <LegalActionHint>[],
    this.cameraPreset = OrbitCameraPreset.redCommander,
    this.isBusy = false,
    this.statusMessage = '',
    this.errorMessage,
    this.canUndo = false,
    FactionId? redFaction,
    FactionId? blueFaction,
  })  : _overrideRedFaction = redFaction,
        _overrideBlueFaction = blueFaction;

  final GameSessionState session;
  final BoardCoord? selectedCoord;
  final List<LegalActionHint> legalHints;
  final OrbitCameraPreset cameraPreset;
  final bool isBusy;
  final String statusMessage;
  final String? errorMessage;
  final bool canUndo;
  final FactionId? _overrideRedFaction;
  final FactionId? _overrideBlueFaction;

  FactionId get redFaction => _overrideRedFaction ?? session.redFaction;

  FactionId get blueFaction => _overrideBlueFaction ?? session.blueFaction;

  bool get isMirrorMatch => redFaction == blueFaction;

  FactionDefinition get redFactionDefinition => FactionCatalog.of(redFaction);

  FactionDefinition get blueFactionDefinition => FactionCatalog.of(blueFaction);

  FactionId factionForSide(PlayerSide side) =>
      side == PlayerSide.red ? redFaction : blueFaction;

  FactionDefinition factionDefinitionForSide(PlayerSide side) =>
      FactionCatalog.of(factionForSide(side));

  FactionUnitProfile unitProfileFor(PieceEntity piece) =>
      FactionCatalog.unitOf(factionForSide(piece.side), piece.type);

  String sideLabel(PlayerSide side) =>
      side == PlayerSide.red ? 'Red' : 'Blue';

  String sideFactionLabel(PlayerSide side) =>
      '${sideLabel(side)} • ${factionForSide(side).displayName}';

  String sideFactionShortLabel(PlayerSide side) =>
      '${sideLabel(side)} (${factionForSide(side).shortCode})';

  String get matchupSummary =>
      '${redFaction.displayName} vs ${blueFaction.displayName}';

  GameHudSnapshot copyWith({
    GameSessionState? session,
    BoardCoord? selectedCoord,
    bool clearSelectedCoord = false,
    List<LegalActionHint>? legalHints,
    OrbitCameraPreset? cameraPreset,
    bool? isBusy,
    String? statusMessage,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? canUndo,
    FactionId? redFaction,
    FactionId? blueFaction,
    bool clearFactionOverrides = false,
  }) {
    final resolvedRed = clearFactionOverrides
        ? null
        : (redFaction ?? (session != null ? null : _overrideRedFaction));
    final resolvedBlue = clearFactionOverrides
        ? null
        : (blueFaction ?? (session != null ? null : _overrideBlueFaction));

    return GameHudSnapshot(
      session: session ?? this.session,
      selectedCoord:
          clearSelectedCoord ? null : (selectedCoord ?? this.selectedCoord),
      legalHints: legalHints != null
          ? List<LegalActionHint>.unmodifiable(legalHints)
          : this.legalHints,
      cameraPreset: cameraPreset ?? this.cameraPreset,
      isBusy: isBusy ?? this.isBusy,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      canUndo: canUndo ?? this.canUndo,
      redFaction: resolvedRed,
      blueFaction: resolvedBlue,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        session,
        selectedCoord,
        legalHints,
        cameraPreset,
        isBusy,
        statusMessage,
        errorMessage,
        canUndo,
        redFaction,
        blueFaction,
      ];
}
