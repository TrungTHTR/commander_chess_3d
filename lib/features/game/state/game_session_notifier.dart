import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../models/action_model.dart';
import '../models/board_coord.dart';
import '../models/game_state_model.dart';
import '../models/piece_model.dart';
import '../repositories/game_repository.dart';
import 'game_hud_snapshot.dart';
import 'game_providers.dart';

/// Manual Riverpod 3.x notifier managing discrete Commander Chess turn state
/// and HUD snapshot updates with [ref.mounted] async disposal safety.
final class GameSessionNotifier extends Notifier<GameHudSnapshot> {
  int _matchCounter = 0;

  @override
  GameHudSnapshot build() {
    final clock = ref.watch(clockProvider);
    final rulesEngine = ref.watch(rulesEngineProvider);
    final repository = ref.watch(gameRepositoryProvider);

    final initialSession = rulesEngine.createInitialSession(
      matchId: _nextMatchId(clock),
      mode: GameMode.localPassAndPlay,
    );

    unawaited(_seedInitialMatch(repository, initialSession));

    return GameHudSnapshot(
      session: initialSession,
      statusMessage: _formatStatusMessage(initialSession),
      canUndo: initialSession.moveHistory.isNotEmpty,
    );
  }

  /// Initializes and persists a fresh match for [mode].
  Future<void> startNewMatch({
    GameMode mode = GameMode.localPassAndPlay,
  }) async {
    if (state.isBusy) return;

    final clock = ref.read(clockProvider);
    final startMatch = ref.read(startMatchUseCaseProvider);
    final matchId = _nextMatchId(clock);

    state = state.copyWith(
      isBusy: true,
      clearSelectedCoord: true,
      legalHints: const <LegalActionHint>[],
      clearErrorMessage: true,
    );

    final result = await startMatch(
      matchId: matchId,
      mode: mode,
    );
    if (!ref.mounted) return;

    result.when(
      ok: (newSession) {
        state = state.copyWith(
          session: newSession,
          clearSelectedCoord: true,
          legalHints: const <LegalActionHint>[],
          isBusy: false,
          statusMessage: _formatStatusMessage(newSession),
          clearErrorMessage: true,
          canUndo: newSession.moveHistory.isNotEmpty,
        );
      },
      err: (failure) {
        state = state.copyWith(
          isBusy: false,
          errorMessage: failure.message,
        );
      },
    );
  }

  /// Handles discrete board intersection taps from the 3D viewport.
  void selectCoord(BoardCoord coord) {
    if (state.isBusy) return;

    if (state.session.phase == MatchPhase.finished) {
      if (state.selectedCoord != null || state.legalHints.isNotEmpty) {
        state = state.copyWith(
          clearSelectedCoord: true,
          legalHints: const <LegalActionHint>[],
        );
      }
      return;
    }

    final topology = ref.read(boardTopologyProvider);
    if (!topology.isValidCoord(coord)) {
      state = state.copyWith(
        clearSelectedCoord: true,
        legalHints: const <LegalActionHint>[],
        clearErrorMessage: true,
      );
      return;
    }

    if (state.selectedCoord == coord) {
      state = state.copyWith(
        clearSelectedCoord: true,
        legalHints: const <LegalActionHint>[],
        clearErrorMessage: true,
      );
      return;
    }

    final tappedPiece = state.session.pieceAt(coord);
    if (tappedPiece != null && tappedPiece.side == state.session.currentTurn) {
      final rulesEngine = ref.read(rulesEngineProvider);
      final hints = rulesEngine.legalActionsFor(
        state: state.session,
        from: coord,
      );
      state = state.copyWith(
        selectedCoord: coord,
        legalHints: hints,
        clearErrorMessage: true,
      );
      return;
    }

    if (state.selectedCoord != null &&
        state.legalHints.any((hint) => hint.targetCoord == coord)) {
      unawaited(attemptMoveTo(coord));
      return;
    }

    state = state.copyWith(
      clearSelectedCoord: true,
      legalHints: const <LegalActionHint>[],
      clearErrorMessage: true,
    );
  }

  /// Validates and commits a move from `state.selectedCoord` to [target].
  Future<void> attemptMoveTo(BoardCoord target) async {
    if (state.isBusy) return;

    final selected = state.selectedCoord;
    if (selected == null) {
      state = state.copyWith(
        errorMessage: 'Select a piece before choosing a destination.',
      );
      return;
    }

    LegalActionHint? matchingHint;
    for (final hint in state.legalHints) {
      if (hint.targetCoord == target) {
        matchingHint = hint;
        break;
      }
    }

    if (matchingHint == null) {
      final label =
          target.isValid ? target.toAlgebraic() : target.toNotation();
      state = state.copyWith(
        errorMessage: 'Destination $label is not a legal move.',
      );
      return;
    }

    final movingPiece = state.session.pieceAt(selected);
    if (movingPiece == null) {
      state = state.copyWith(
        clearSelectedCoord: true,
        legalHints: const <LegalActionHint>[],
        errorMessage: 'No active piece found at ${selected.toAlgebraic()}.',
      );
      return;
    }

    final clock = ref.read(clockProvider);
    final move = GameMove(
      side: state.session.currentTurn,
      pieceId: movingPiece.id,
      from: selected,
      to: target,
      kind: matchingHint.kind,
      targetPieceId: matchingHint.targetPieceId,
      timestampUtc: clock.nowUtc(),
    );

    state = state.copyWith(
      isBusy: true,
      clearErrorMessage: true,
    );

    final submitMove = ref.read(submitMoveUseCaseProvider);
    final result = await submitMove(
      matchId: state.session.matchId,
      currentState: state.session,
      move: move,
    );
    if (!ref.mounted) return;

    result.when(
      ok: (newSession) {
        state = state.copyWith(
          session: newSession,
          clearSelectedCoord: true,
          legalHints: const <LegalActionHint>[],
          isBusy: false,
          statusMessage: _formatStatusMessage(newSession),
          clearErrorMessage: true,
          canUndo: newSession.moveHistory.isNotEmpty,
        );
      },
      err: (failure) {
        state = state.copyWith(
          isBusy: false,
          errorMessage: failure.message,
        );
      },
    );
  }

  /// Reverts the active match to the immediately preceding snapshot.
  Future<void> undoLastMove() async {
    if (state.isBusy) return;

    state = state.copyWith(
      isBusy: true,
      clearErrorMessage: true,
    );

    final repository = ref.read(gameRepositoryProvider);
    final result = await repository.undoLastMove(state.session.matchId);
    if (!ref.mounted) return;

    result.when(
      ok: (previousSession) {
        state = state.copyWith(
          session: previousSession,
          clearSelectedCoord: true,
          legalHints: const <LegalActionHint>[],
          isBusy: false,
          statusMessage: _formatStatusMessage(previousSession),
          clearErrorMessage: true,
          canUndo: previousSession.moveHistory.isNotEmpty,
        );
      },
      err: (failure) {
        state = state.copyWith(
          isBusy: false,
          errorMessage: failure.message,
        );
      },
    );
  }

  /// Updates the active HUD camera preset for the 3D viewport to sync.
  void setCameraPreset(OrbitCameraPreset preset) {
    if (state.cameraPreset == preset) return;
    state = state.copyWith(cameraPreset: preset);
  }

  /// Clears any transient error banner message.
  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(clearErrorMessage: true);
  }

  Future<void> _seedInitialMatch(
    GameRepository repository,
    GameSessionState initialSession,
  ) async {
    final result = await repository.createMatch(
      matchId: initialSession.matchId,
      initialState: initialSession,
    );
    if (!ref.mounted) return;
    result.when(
      ok: (_) {},
      err: (failure) {
        if (state.session.matchId == initialSession.matchId) {
          state = state.copyWith(errorMessage: failure.message);
        }
      },
    );
  }

  String _nextMatchId(Clock clock) {
    _matchCounter += 1;
    return 'match_${clock.nowUtc().microsecondsSinceEpoch}_$_matchCounter';
  }

  static String _formatStatusMessage(GameSessionState session) {
    if (session.phase == MatchPhase.finished) {
      if (session.victoryReason == VictoryReason.draw) {
        return 'Draw — Match finished';
      }
      final winner = session.winner;
      if (winner != null) {
        return 'Victory: ${_sideLabel(winner)} wins!';
      }
      return 'Match finished';
    }

    final turnLabel = _sideLabel(session.currentTurn);
    if (session.phase == MatchPhase.check) {
      return '$turnLabel to move — Check!';
    }
    return '$turnLabel to move';
  }

  static String _sideLabel(PlayerSide side) =>
      side == PlayerSide.red ? 'Red' : 'Blue';
}
