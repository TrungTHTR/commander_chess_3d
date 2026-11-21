import '../../../../core/result/app_failure.dart';
import '../../../../core/result/result.dart';
import '../../models/game_state_model.dart';
import '../../repositories/game_repository.dart';
import '../board_topology.dart';
import '../commander_rules_engine.dart';

/// Pure-Dart use-case that initializes a new Commander Chess match,
/// validates initial board topology placement, and persists it via [GameRepository].
final class StartMatchUseCase {
  const StartMatchUseCase({
    required this.topology,
    required this.rulesEngine,
    required this.repository,
  });

  final BoardTopology topology;
  final CommanderRulesEngine rulesEngine;
  final GameRepository repository;

  Future<Result<GameSessionState>> call({
    required String matchId,
    GameMode mode = GameMode.localPassAndPlay,
    RuleVariantConfig? variantConfig,
  }) async {
    final normalizedId = matchId.trim();
    if (normalizedId.isEmpty) {
      return const Err<GameSessionState>(
        ValidationAppFailure(
          'matchId must not be empty.',
          code: 'INVALID_MATCH_ID',
          fieldErrors: <String, String>{'matchId': 'Must not be empty.'},
        ),
      );
    }

    final initialState = rulesEngine.createInitialSession(
      matchId: normalizedId,
      mode: mode,
      variantConfig: variantConfig,
    );

    if (initialState.boardFiles != topology.files ||
        initialState.boardRanks != topology.ranks) {
      return const Err<GameSessionState>(
        RulesViolationFailure(
          'Initial session board dimensions do not match board topology.',
          code: 'TOPOLOGY_DIMENSION_MISMATCH',
        ),
      );
    }

    for (final piece in initialState.pieces) {
      if (!piece.isAlive) {
        continue;
      }
      if (!topology.isValidCoord(piece.position) ||
          !topology.isPassableFor(piece.type, piece.position)) {
        return Err<GameSessionState>(
          RulesViolationFailure(
            'Initial piece ${piece.id} at ${piece.position.toAlgebraic()} violates board topology.',
            code: 'INVALID_INITIAL_PLACEMENT',
          ),
        );
      }
    }

    return repository.createMatch(
      matchId: normalizedId,
      initialState: initialState,
    );
  }
}
