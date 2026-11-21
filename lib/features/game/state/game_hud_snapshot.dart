import 'package:equatable/equatable.dart';

import '../models/action_model.dart';
import '../models/board_coord.dart';
import '../models/game_state_model.dart';

/// Discrete camera presets selectable from the HUD for the 3D orbit camera.
enum OrbitCameraPreset {
  redCommander,
  blueCommander,
  tacticalTop,
  sideOverview,
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
  });

  final GameSessionState session;
  final BoardCoord? selectedCoord;
  final List<LegalActionHint> legalHints;
  final OrbitCameraPreset cameraPreset;
  final bool isBusy;
  final String statusMessage;
  final String? errorMessage;
  final bool canUndo;

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
  }) {
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
      ];
}
