import 'dart:async';

import 'package:commander_chess_3d/core/result/app_failure.dart';
import 'package:commander_chess_3d/core/result/result.dart';
import 'package:commander_chess_3d/core/time/clock.dart';
import 'package:commander_chess_3d/features/game/models/board_coord.dart';
import 'package:commander_chess_3d/features/game/models/faction_model.dart';
import 'package:commander_chess_3d/features/game/models/game_state_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:commander_chess_3d/features/game/repositories/game_repository.dart';
import 'package:commander_chess_3d/features/game/repositories/settings_repository.dart';
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

  group('Faction & Settings Integration (M3)', () {
    test('build() picks up default gameSettingsProvider factions and camera preset',
        () async {
      final fixedClock = FixedClock(DateTime.utc(2026, 11, 21, 9, 0, 0));
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(fixedClock)],
      );
      addTearDown(container.dispose);

      final snapshot = container.read(gameSessionNotifierProvider);
      await Future<void>.delayed(Duration.zero);

      expect(snapshot.session.redFaction, FactionId.vietnam);
      expect(snapshot.session.blueFaction, FactionId.usa);
      expect(snapshot.redFaction, FactionId.vietnam);
      expect(snapshot.blueFaction, FactionId.usa);
      expect(snapshot.cameraPreset, OrbitCameraPreset.redCommander);
      expect(snapshot.statusMessage, 'Red to move');
    });

    test('build() picks up pre-configured gameSettingsProvider factions and all 4 camera preset mappings',
        () async {
      final cases = <(String, OrbitCameraPreset)>[
        ('classic', OrbitCameraPreset.redCommander),
        ('high', OrbitCameraPreset.tacticalTop),
        ('side', OrbitCameraPreset.sideOverview),
        ('top', OrbitCameraPreset.blueCommander),
      ];

      for (final (presetKey, expectedOrbit) in cases) {
        final fixedClock = FixedClock(DateTime.utc(2026, 11, 21, 9, 5, 0));
        final container = ProviderContainer(
          overrides: [clockProvider.overrideWithValue(fixedClock)],
        );

        final settingsNotifier = container.read(gameSettingsProvider.notifier);
        await settingsNotifier.selectRedFaction(FactionId.unitedKingdom);
        await settingsNotifier.selectBlueFaction(FactionId.france);
        await settingsNotifier.setDefaultCameraPreset(presetKey);

        final snapshot = container.read(gameSessionNotifierProvider);
        await Future<void>.delayed(Duration.zero);

        expect(snapshot.session.redFaction, FactionId.unitedKingdom);
        expect(snapshot.session.blueFaction, FactionId.france);
        expect(snapshot.redFaction, FactionId.unitedKingdom);
        expect(snapshot.blueFaction, FactionId.france);
        expect(snapshot.cameraPreset, expectedOrbit);
        expect(snapshot.statusMessage, 'Red to move');

        container.dispose();
      }
    });

    test('startNewMatch() reads updated settings, supports explicit overrides without mutating settings, and supports mirror match',
        () async {
      final fixedClock = FixedClock(DateTime.utc(2026, 11, 21, 9, 10, 0));
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(fixedClock)],
      );
      addTearDown(container.dispose);

      final sessionNotifier =
          container.read(gameSessionNotifierProvider.notifier);
      final settingsNotifier = container.read(gameSettingsProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Update settings mid-session and start new match with zero faction args.
      await settingsNotifier.selectRedFaction(FactionId.sovietUnion);
      await settingsNotifier.selectBlueFaction(FactionId.germany);
      await settingsNotifier.setDefaultCameraPreset('side');

      // Active match must NOT have been wiped by settings edits prior to startNewMatch.
      expect(
        container.read(gameSessionNotifierProvider).session.redFaction,
        FactionId.vietnam,
      );

      fixedClock.advance(const Duration(seconds: 2));
      await sessionNotifier.startNewMatch();

      final fromSettings = container.read(gameSessionNotifierProvider);
      expect(fromSettings.session.redFaction, FactionId.sovietUnion);
      expect(fromSettings.session.blueFaction, FactionId.germany);
      expect(fromSettings.cameraPreset, OrbitCameraPreset.sideOverview);
      expect(fromSettings.statusMessage, 'Red to move');

      // Explicit override args take precedence without mutating gameSettingsProvider.
      fixedClock.advance(const Duration(seconds: 2));
      await sessionNotifier.startNewMatch(
        redFaction: FactionId.japan,
        blueFaction: FactionId.india,
        cameraPreset: OrbitCameraPreset.blueCommander,
      );

      final overridden = container.read(gameSessionNotifierProvider);
      expect(overridden.session.redFaction, FactionId.japan);
      expect(overridden.session.blueFaction, FactionId.india);
      expect(overridden.cameraPreset, OrbitCameraPreset.blueCommander);
      expect(
        container.read(gameSettingsProvider).redFaction,
        FactionId.sovietUnion,
      );
      expect(
        container.read(gameSettingsProvider).blueFaction,
        FactionId.germany,
      );

      // Mirror match via startNewMatch.
      fixedClock.advance(const Duration(seconds: 2));
      await sessionNotifier.startNewMatch(
        redFaction: FactionId.china,
        blueFaction: FactionId.china,
      );

      final mirror = container.read(gameSessionNotifierProvider);
      expect(mirror.session.redFaction, FactionId.china);
      expect(mirror.session.blueFaction, FactionId.china);
      expect(mirror.isMirrorMatch, isTrue);
      expect(mirror.session.pieces, hasLength(38));
    });

    test('updateMatchFactions updates active session without altering turn or undo history and preserves across moves',
        () async {
      final fixedClock = FixedClock(DateTime.utc(2026, 11, 21, 9, 15, 0));
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(fixedClock)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(gameSessionNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      notifier.updateMatchFactions(FactionId.israel, FactionId.israel);
      final updated = container.read(gameSessionNotifierProvider);
      expect(updated.session.redFaction, FactionId.israel);
      expect(updated.session.blueFaction, FactionId.israel);
      expect(updated.isMirrorMatch, isTrue);
      expect(updated.session.turnNumber, 1);
      expect(updated.session.moveHistory, isEmpty);
      expect(updated.canUndo, isFalse);
      expect(updated.session.pieces, hasLength(38));

      // Play a legal move and verify updated factions carry forward.
      notifier.selectCoord(BoardCoord.fromAlgebraic('g5'));
      await notifier.attemptMoveTo(BoardCoord.fromAlgebraic('g6'));

      final afterMove = container.read(gameSessionNotifierProvider);
      expect(afterMove.session.redFaction, FactionId.israel);
      expect(afterMove.session.blueFaction, FactionId.israel);
      expect(afterMove.session.turnNumber, 2);
      expect(afterMove.statusMessage, 'Blue to move');
    });

    test('undoLastMove preserves non-default and mid-match updated factions',
        () async {
      final fixedClock = FixedClock(DateTime.utc(2026, 11, 21, 9, 20, 0));
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(fixedClock)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(gameSessionNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      await notifier.startNewMatch(
        redFaction: FactionId.unitedKingdom,
        blueFaction: FactionId.france,
      );

      notifier.selectCoord(BoardCoord.fromAlgebraic('g5'));
      await notifier.attemptMoveTo(BoardCoord.fromAlgebraic('g6'));
      expect(
        container.read(gameSessionNotifierProvider).session.turnNumber,
        2,
      );

      await notifier.undoLastMove();
      final afterFirstUndo = container.read(gameSessionNotifierProvider);
      expect(afterFirstUndo.session.turnNumber, 1);
      expect(afterFirstUndo.session.redFaction, FactionId.unitedKingdom);
      expect(afterFirstUndo.session.blueFaction, FactionId.france);
      expect(afterFirstUndo.canUndo, isFalse);

      // Also verify mid-match updateMatchFactions survives undoLastMove.
      notifier.updateMatchFactions(FactionId.germany, FactionId.japan);
      notifier.selectCoord(BoardCoord.fromAlgebraic('g5'));
      await notifier.attemptMoveTo(BoardCoord.fromAlgebraic('g6'));
      notifier.selectCoord(BoardCoord.fromAlgebraic('c8'));
      await notifier.attemptMoveTo(BoardCoord.fromAlgebraic('c7'));

      await notifier.undoLastMove();
      final afterSecondUndo = container.read(gameSessionNotifierProvider);
      expect(afterSecondUndo.session.turnNumber, 2);
      expect(afterSecondUndo.session.redFaction, FactionId.germany);
      expect(afterSecondUndo.session.blueFaction, FactionId.japan);
    });

    test('GameHudSnapshot exposes faction metadata helpers and copyWith/props while keeping statusMessage intact',
        () {
      final fixedClock = FixedClock(DateTime.utc(2026, 11, 21, 9, 25, 0));
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(fixedClock)],
      );
      addTearDown(container.dispose);

      final snapshot = container.read(gameSessionNotifierProvider);
      expect(snapshot.statusMessage, 'Red to move');
      expect(snapshot.sideLabel(PlayerSide.red), 'Red');
      expect(snapshot.sideLabel(PlayerSide.blue), 'Blue');
      expect(snapshot.sideFactionLabel(PlayerSide.red), 'Red • Vietnam');
      expect(
        snapshot.sideFactionLabel(PlayerSide.blue),
        'Blue • United States',
      );
      expect(snapshot.sideFactionShortLabel(PlayerSide.red), 'Red (VN)');
      expect(snapshot.sideFactionShortLabel(PlayerSide.blue), 'Blue (USA)');
      expect(snapshot.matchupSummary, 'Vietnam vs United States');
      expect(snapshot.redFactionDefinition.id, FactionId.vietnam);
      expect(snapshot.blueFactionDefinition.id, FactionId.usa);
      expect(
        snapshot.factionDefinitionForSide(PlayerSide.red).id,
        FactionId.vietnam,
      );

      final redMilitia =
          snapshot.session.pieceAt(BoardCoord.fromAlgebraic('g5'))!;
      final profile = snapshot.unitProfileFor(redMilitia);
      expect(profile.faction, FactionId.vietnam);
      expect(profile.pieceType, PieceType.militia);

      final overridden = snapshot.copyWith(
        redFaction: FactionId.southKorea,
        blueFaction: FactionId.southKorea,
      );
      expect(overridden, isNot(equals(snapshot)));
      expect(overridden.isMirrorMatch, isTrue);
      expect(overridden.matchupSummary, 'South Korea vs South Korea');

      final cleared = overridden.copyWith(clearFactionOverrides: true);
      expect(cleared.redFaction, FactionId.vietnam);
      expect(cleared.blueFaction, FactionId.usa);
      expect(cleared, equals(snapshot));
    });

    test('disposes both gameRepositoryProvider and settingsRepositoryProvider via ref.onDispose',
        () {
      final container = ProviderContainer();
      final gameRepo =
          container.read(gameRepositoryProvider) as InMemoryGameRepository;
      final settingsRepo = container.read(settingsRepositoryProvider)
          as InMemorySettingsRepository;
      container.read(gameSettingsProvider);
      container.read(gameSessionNotifierProvider);

      expect(gameRepo.isDisposed, isFalse);
      expect(settingsRepo.isDisposed, isFalse);

      container.dispose();
      expect(gameRepo.isDisposed, isTrue);
      expect(settingsRepo.isDisposed, isTrue);
    });
  });
}
