import '../../../../core/result/app_failure.dart';
import '../../../../core/result/result.dart';
import '../../models/action_model.dart';
import '../../models/game_state_model.dart';
import '../../repositories/game_repository.dart';
import '../commander_rules_engine.dart';

/// Pure-Dart use-case that validates and applies a [GameMove] through
/// [CommanderRulesEngine] and persists the resulting snapshot to [GameRepository].
final class SubmitMoveUseCase {
  const SubmitMoveUseCase({
    required this.rulesEngine,
    required this.repository,
  });

  final CommanderRulesEngine rulesEngine;
  final GameRepository repository;

  Future<Result<GameSessionState>> call({
    String? matchId,
    GameSessionState? currentState,
    required GameMove move,
  }) async {
    final resolvedMatchId = (matchId ?? currentState?.matchId ?? '').trim();
    if (resolvedMatchId.isEmpty) {
      return const Err<GameSessionState>(
        ValidationAppFailure(
          'matchId must not be empty.',
          code: 'INVALID_MATCH_ID',
          fieldErrors: <String, String>{'matchId': 'Must not be empty.'},
        ),
      );
    }

    final GameSessionState baseState;
    if (currentState != null) {
      if (currentState.matchId != resolvedMatchId) {
        return Err<GameSessionState>(
          ValidationAppFailure(
            'currentState.matchId (${currentState.matchId}) does not match "$resolvedMatchId".',
            code: 'MATCH_ID_MISMATCH',
            fieldErrors: <String, String>{
              'matchId': 'Expected "$resolvedMatchId".',
            },
          ),
        );
      }
      baseState = currentState;
    } else {
      final loaded = await repository.loadMatch(resolvedMatchId);
      switch (loaded) {
        case Ok<GameSessionState>(:final data):
          baseState = data;
        case Err<GameSessionState>(:final failure):
          return Err<GameSessionState>(failure);
      }
    }

    final applied = rulesEngine.applyMove(state: baseState, move: move);
    switch (applied) {
      case Ok<GameSessionState>(:final data):
        return repository.saveSnapshot(data);
      case Err<GameSessionState>(:final failure):
        return Err<GameSessionState>(failure);
    }
  }
}
