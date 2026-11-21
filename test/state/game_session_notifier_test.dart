import 'dart:async';

import 'package:commander_chess_3d/core/result/app_failure.dart';
import 'package:commander_chess_3d/core/result/result.dart';
import 'package:commander_chess_3d/core/time/clock.dart';
import 'package:commander_chess_3d/features/game/models/board_coord.dart';
import 'package:commander_chess_3d/features/game/models/game_state_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:commander_chess_3d/features/game/repositories/game_repository.dart';
import 'package:commander_chess_3d/features/game/state/game_hud_snapshot.dart';
import 'package:commander_chess_3d/features/game/state/game_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FailingGameRepository implements GameRepository {
  _FailingGameRepository({
    this.failOnCreate = false,
    this.failOnSave = false,
    this.createCompleter,
  });

  final bool failOnCreate;
  final bool failOnSave;
  final Completer<Result<GameSessionState>>? createCompleter;
  final InMemoryGameRepository _inner = InMemoryGameRepository();

  @override
  Future<Result<GameSessionState>> createMatch({
    required String matchId,
    required GameSessionState initialState,
  }) {
    if (createCompleter != null) {
      return createCompleter!.future;
    }
    if (failOnCreate) {
      return Future<Result<GameSessionState>>.value(
        const Err<GameSessionState>(
          ValidationAppFailure('Simulated create failure', code: 'CREATE_ERR'),
        ),
      );
    }
    return _inner.createMatch(matchId: matchId, initialState: initialState);
  }

  @override
  Future<Result<GameSessionState>> loadMatch(String matchId) =>
      _inner.loadMatch(matchId);

  @override
  Future<Result<GameSessionState>> saveSnapshot(GameSessionState state) {
    if (failOnSave) {
      return Future<Result<GameSessionState>>.value(
        const Err<GameSessionState>(
          ServerAppFailure('Simulated save failure', code: 'SAVE_ERR'),
        ),
      );
    }
    return _inner.saveSnapshot(state);
  }

  @override
  Future<Result<GameSessionState>> undoLastMove(String matchId) =>
      _inner.undoLastMove(matchId);

  @override
  Stream<GameSessionState> watchMatch(String matchId) =>
      _inner.watchMatch(matchId);

  @override
  void dispose() => _inner.dispose();
}

void main() {
  group('GameSessionNotifier (Riverpod ProviderContainer)', () {
    test('exposes initial match state immediately on frame 1', () async {
      final fixedClock = FixedClock(DateTime.utc(2026, 11, 20, 16, 0, 0));
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(fixedClock)],
      );
      addTearDown(container.dispose);

      final snapshot = container.read(gameSessionNotifierProvider);
      expect(snapshot.session.pieces, hasLength(38));
      expect(snapshot.session.currentTurn, PlayerSide.red);
      expect(snapshot.session.turnNumber, 1);
      expect(snapshot.session.phase, MatchPhase.playing);
      expect(snapshot.selectedCoord, isNull);
      expect(snapshot.legalHints, isEmpty);
      expect(snapshot.cameraPreset, OrbitCameraPreset.redCommander);
      expect(snapshot.isBusy, isFalse);
      expect(snapshot.canUndo, isFalse);
      expect(snapshot.errorMessage, isNull);
      expect(snapshot.statusMessage, 'Red to move');

      // Allow initial _seedInitialMatch microtask to complete cleanly.
      await Future<void>.delayed(Duration.zero);
      final repo = container.read(gameRepositoryProvider);
      final loaded = await repo.loadMatch(snapshot.session.matchId);
      expect(loaded.isOk, isTrue);
    });

    test('selectCoord, attemptMoveTo, undoLastMove, and startNewMatch update state accurately', () async {
      final fixedClock = FixedClock(DateTime.utc(2026, 11, 20, 16, 1, 0));
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(fixedClock)],
      );
      addTearDown(container.dispose);

      final states = <GameHudSnapshot>[];
      final sub = container.listen<GameHudSnapshot>(
        gameSessionNotifierProvider,
        (prev, next) => states.add(next),
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final notifier = container.read(gameSessionNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final initialMatchId =
          container.read(gameSessionNotifierProvider).session.matchId;
      final g5 = BoardCoord.fromAlgebraic('g5');
      final g6 = BoardCoord.fromAlgebraic('g6');
      final c8 = BoardCoord.fromAlgebraic('c8');

      // Selecting enemy piece when nothing selected does not select it.
      notifier.selectCoord(c8);
      expect(container.read(gameSessionNotifierProvider).selectedCoord, isNull);

      // Selecting Red Militia at g5 populates legal hints.
      notifier.selectCoord(g5);
      final selected = container.read(gameSessionNotifierProvider);
      expect(selected.selectedCoord, g5);
      expect(selected.legalHints, isNotEmpty);
      expect(
        selected.legalHints.any((h) => h.targetCoord == g6),
        isTrue,
      );

      // Tapping g5 again deselects it.
      notifier.selectCoord(g5);
      expect(container.read(gameSessionNotifierProvider).selectedCoord, isNull);
      expect(container.read(gameSessionNotifierProvider).legalHints, isEmpty);

      // Select g5 again and commit move to g6 via attemptMoveTo.
      notifier.selectCoord(g5);
      await notifier.attemptMoveTo(g6);

      final afterMove = container.read(gameSessionNotifierProvider);
      expect(afterMove.selectedCoord, isNull);
      expect(afterMove.legalHints, isEmpty);
      expect(afterMove.isBusy, isFalse);
      expect(afterMove.session.currentTurn, PlayerSide.blue);
      expect(afterMove.session.turnNumber, 2);
      expect(afterMove.session.pieceAt(g5), isNull);
      expect(afterMove.session.pieceAt(g6)?.type, PieceType.militia);
      expect(afterMove.canUndo, isTrue);
      expect(afterMove.statusMessage, 'Blue to move');

      // Tapping a legal target via selectCoord directly also commits move.
      notifier.selectCoord(c8);
      final c7 = BoardCoord.fromAlgebraic('c7');
      notifier.selectCoord(c7);
      await Future<void>.delayed(Duration.zero);

      final afterBlueMove = container.read(gameSessionNotifierProvider);
      expect(afterBlueMove.session.currentTurn, PlayerSide.red);
      expect(afterBlueMove.session.turnNumber, 3);
      expect(afterBlueMove.session.pieceAt(c7)?.side, PlayerSide.blue);

      // Undo reverts Blue's move cleanly.
      await notifier.undoLastMove();
      final afterUndo = container.read(gameSessionNotifierProvider);
      expect(afterUndo.session.currentTurn, PlayerSide.blue);
      expect(afterUndo.session.turnNumber, 2);
      expect(afterUndo.session.pieceAt(c8)?.side, PlayerSide.blue);
      expect(afterUndo.session.pieceAt(c7), isNull);
      expect(afterUndo.canUndo, isTrue);

      // Start new match advances match counter and resets board.
      fixedClock.advance(const Duration(seconds: 5));
      await notifier.startNewMatch(mode: GameMode.localPassAndPlay);
      final freshMatch = container.read(gameSessionNotifierProvider);
      expect(freshMatch.session.matchId, isNot(initialMatchId));
      expect(freshMatch.session.turnNumber, 1);
      expect(freshMatch.session.currentTurn, PlayerSide.red);
      expect(freshMatch.canUndo, isFalse);
      expect(freshMatch.session.pieceAt(g5)?.type, PieceType.militia);
      expect(states.length, greaterThanOrEqualTo(5));
    });

    test('handles camera preset switching, error states, clearError, and repository failure recovery', () async {
      final failingRepo = _FailingGameRepository(failOnSave: true);
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 11, 20, 16, 5, 0)),
          ),
          gameRepositoryProvider.overrideWithValue(failingRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(gameSessionNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Camera preset switching.
      for (final preset in OrbitCameraPreset.values) {
        notifier.setCameraPreset(preset);
        expect(
          container.read(gameSessionNotifierProvider).cameraPreset,
          preset,
        );
      }

      // attemptMoveTo with no piece selected produces errorMessage.
      final g6 = BoardCoord.fromAlgebraic('g6');
      await notifier.attemptMoveTo(g6);
      expect(
        container.read(gameSessionNotifierProvider).errorMessage,
        contains('Select a piece'),
      );
      notifier.clearError();
      expect(container.read(gameSessionNotifierProvider).errorMessage, isNull);

      // attemptMoveTo with illegal destination produces errorMessage.
      notifier.selectCoord(BoardCoord.fromAlgebraic('g5'));
      await notifier.attemptMoveTo(BoardCoord.fromAlgebraic('a1'));
      expect(
        container.read(gameSessionNotifierProvider).errorMessage,
        contains('not a legal move'),
      );
      notifier.clearError();

      // Repository save failure surfaces errorMessage without crashing.
      await notifier.attemptMoveTo(g6);
      final failedSaveState = container.read(gameSessionNotifierProvider);
      expect(failedSaveState.isBusy, isFalse);
      expect(failedSaveState.errorMessage, 'Simulated save failure');

      // Undo with nothing to undo sets errorMessage and clears cleanly.
      await notifier.undoLastMove();
      expect(
        container.read(gameSessionNotifierProvider).errorMessage,
        isNotNull,
      );
      notifier.clearError();
      expect(container.read(gameSessionNotifierProvider).errorMessage, isNull);
    });

    test('guards async completion safely when ProviderContainer is disposed mid-flight', () async {
      final completer = Completer<Result<GameSessionState>>();
      final slowRepo = _FailingGameRepository(createCompleter: completer);
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 11, 20, 16, 10, 0)),
          ),
          gameRepositoryProvider.overrideWithValue(slowRepo),
        ],
      );

      final notifier = container.read(gameSessionNotifierProvider.notifier);
      final future = notifier.startNewMatch();

      // Dispose container before repository resolves.
      container.dispose();
      completer.complete(
        const Err<GameSessionState>(
          ValidationAppFailure('Late completion', code: 'LATE'),
        ),
      );
      await expectLater(future, completes);
    });

    test('surfaces errorMessage if initial seed createMatch fails', () async {
      final failingRepo = _FailingGameRepository(failOnCreate: true);
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(
            FixedClock(DateTime.utc(2026, 11, 20, 16, 12, 0)),
          ),
          gameRepositoryProvider.overrideWithValue(failingRepo),
        ],
      );
      addTearDown(container.dispose);

      container.read(gameSessionNotifierProvider);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(gameSessionNotifierProvider).errorMessage,
        'Simulated create failure',
      );
    });
  });
}
