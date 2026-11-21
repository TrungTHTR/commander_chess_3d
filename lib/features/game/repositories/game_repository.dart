import 'dart:async';

import '../../../core/result/app_failure.dart';
import '../../../core/result/result.dart';
import '../models/game_state_model.dart';

/// Persistence and reactive snapshot contract for Commander Chess matches.
abstract interface class GameRepository {
  /// Creates and stores a new match seeded with [initialState].
  Future<Result<GameSessionState>> createMatch({
    required String matchId,
    required GameSessionState initialState,
  });

  /// Loads the latest persisted snapshot for [matchId].
  Future<Result<GameSessionState>> loadMatch(String matchId);

  /// Persists a new [GameSessionState] snapshot and notifies active watchers.
  Future<Result<GameSessionState>> saveSnapshot(GameSessionState state);

  /// Reverts [matchId] to the immediately preceding snapshot, if available.
  Future<Result<GameSessionState>> undoLastMove(String matchId);

  /// Broadcast stream emitting updated snapshots for [matchId].
  Stream<GameSessionState> watchMatch(String matchId);

  /// Releases held stream controllers and backing resources.
  void dispose();
}

/// In-memory [GameRepository] preserving full per-match snapshot history.
final class InMemoryGameRepository implements GameRepository {
  final Map<String, List<GameSessionState>> _histories =
      <String, List<GameSessionState>>{};
  final Map<String, StreamController<GameSessionState>> _controllers =
      <String, StreamController<GameSessionState>>{};
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  @override
  Future<Result<GameSessionState>> createMatch({
    required String matchId,
    required GameSessionState initialState,
  }) async {
    if (_isDisposed) {
      return const Err<GameSessionState>(
        ValidationAppFailure(
          'GameRepository has been disposed.',
          code: 'REPOSITORY_DISPOSED',
        ),
      );
    }

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

    if (initialState.matchId != normalizedId) {
      return Err<GameSessionState>(
        ValidationAppFailure(
          'initialState.matchId (${initialState.matchId}) does not match "$normalizedId".',
          code: 'MATCH_ID_MISMATCH',
          fieldErrors: <String, String>{
            'matchId': 'Expected "$normalizedId".',
          },
        ),
      );
    }

    if (_histories.containsKey(normalizedId)) {
      return Err<GameSessionState>(
        ValidationAppFailure(
          'Match "$normalizedId" already exists.',
          code: 'MATCH_ALREADY_EXISTS',
          fieldErrors: <String, String>{
            'matchId': 'Match already exists.',
          },
        ),
      );
    }

    _histories[normalizedId] = <GameSessionState>[initialState];
    _emit(normalizedId, initialState);
    return Ok<GameSessionState>(initialState);
  }

  @override
  Future<Result<GameSessionState>> loadMatch(String matchId) async {
    if (_isDisposed) {
      return const Err<GameSessionState>(
        ValidationAppFailure(
          'GameRepository has been disposed.',
          code: 'REPOSITORY_DISPOSED',
        ),
      );
    }

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

    final history = _histories[normalizedId];
    if (history == null || history.isEmpty) {
      return Err<GameSessionState>(
        ValidationAppFailure(
          'Match "$normalizedId" was not found.',
          code: 'MATCH_NOT_FOUND',
          fieldErrors: <String, String>{'matchId': 'Match not found.'},
        ),
      );
    }

    return Ok<GameSessionState>(history.last);
  }

  @override
  Future<Result<GameSessionState>> saveSnapshot(GameSessionState state) async {
    if (_isDisposed) {
      return const Err<GameSessionState>(
        ValidationAppFailure(
          'GameRepository has been disposed.',
          code: 'REPOSITORY_DISPOSED',
        ),
      );
    }

    final normalizedId = state.matchId.trim();
    if (normalizedId.isEmpty) {
      return const Err<GameSessionState>(
        ValidationAppFailure(
          'state.matchId must not be empty.',
          code: 'INVALID_MATCH_ID',
          fieldErrors: <String, String>{'matchId': 'Must not be empty.'},
        ),
      );
    }

    final normalizedState = state.matchId == normalizedId
        ? state
        : state.copyWith(matchId: normalizedId);

    final history = _histories.putIfAbsent(
      normalizedId,
      () => <GameSessionState>[],
    );
    history.add(normalizedState);
    _emit(normalizedId, normalizedState);
    return Ok<GameSessionState>(normalizedState);
  }

  @override
  Future<Result<GameSessionState>> undoLastMove(String matchId) async {
    if (_isDisposed) {
      return const Err<GameSessionState>(
        ValidationAppFailure(
          'GameRepository has been disposed.',
          code: 'REPOSITORY_DISPOSED',
        ),
      );
    }

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

    final history = _histories[normalizedId];
    if (history == null || history.isEmpty) {
      return Err<GameSessionState>(
        ValidationAppFailure(
          'Match "$normalizedId" was not found.',
          code: 'MATCH_NOT_FOUND',
          fieldErrors: <String, String>{'matchId': 'Match not found.'},
        ),
      );
    }

    if (history.length <= 1) {
      return Err<GameSessionState>(
        ValidationAppFailure(
          'No moves to undo for match "$normalizedId".',
          code: 'NOTHING_TO_UNDO',
        ),
      );
    }

    history.removeLast();
    final previous = history.last;
    _emit(normalizedId, previous);
    return Ok<GameSessionState>(previous);
  }

  @override
  Stream<GameSessionState> watchMatch(String matchId) {
    final normalizedId = matchId.trim();
    if (_isDisposed || normalizedId.isEmpty) {
      return const Stream<GameSessionState>.empty();
    }

    final controller = _controllers.putIfAbsent(
      normalizedId,
      () => StreamController<GameSessionState>.broadcast(),
    );
    return controller.stream;
  }

  void _emit(String matchId, GameSessionState state) {
    final controller = _controllers[matchId];
    if (controller != null && !controller.isClosed) {
      controller.add(state);
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final controller in _controllers.values) {
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
    }
    _controllers.clear();
    _histories.clear();
  }
}
