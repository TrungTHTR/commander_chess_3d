import '../../../core/result/result.dart';
import '../models/action_model.dart';
import '../models/game_state_model.dart';
import '../models/piece_model.dart';

/// Search depth and tactical aggressiveness presets for AI opponents.
enum AiDifficulty {
  casual,
  tactical,
  master,
}

/// Pure domain contract for background AI move search.
///
/// Phase D implementations execute search in a dedicated `Isolate` (passing
/// compact board state via `TransferableTypedData` where applicable) using the
/// shared pure-Dart `CommanderRulesEngine`.
abstract interface class AiOpponentEngine {
  /// Selects the best legal [GameMove] for [aiSide] from [state] within
  /// [timeBudget], or `Ok(null)` when no legal move exists.
  Future<Result<GameMove?>> selectBestMove({
    required GameSessionState state,
    required PlayerSide aiSide,
    AiDifficulty difficulty = AiDifficulty.tactical,
    Duration timeBudget = const Duration(milliseconds: 800),
  });

  /// Terminates any long-lived worker isolate and releases allocated buffers.
  void dispose();
}
