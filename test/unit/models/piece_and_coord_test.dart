import 'dart:convert';

import 'package:commander_chess_3d/core/result/app_failure.dart';
import 'package:commander_chess_3d/core/result/result.dart';
import 'package:commander_chess_3d/core/time/clock.dart';
import 'package:commander_chess_3d/features/game/models/action_model.dart';
import 'package:commander_chess_3d/features/game/models/board_coord.dart';
import 'package:commander_chess_3d/features/game/models/game_state_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoardCoord', () {
    test('validates 11x12 intersection bounds (0..10 x 0..11)', () {
      expect(const BoardCoord(file: 0, rank: 0).isValid, isTrue);
      expect(const BoardCoord(file: 10, rank: 11).isValid, isTrue);
      expect(const BoardCoord(file: 6, rank: 0).isValid, isTrue);

      expect(const BoardCoord(file: -1, rank: 0).isValid, isFalse);
      expect(const BoardCoord(file: 0, rank: -1).isValid, isFalse);
      expect(const BoardCoord(file: 11, rank: 0).isValid, isFalse);
      expect(const BoardCoord(file: 0, rank: 12).isValid, isFalse);
    });

    test('converts between algebraic notation and coordinates', () {
      expect(const BoardCoord(file: 0, rank: 0).toAlgebraic(), 'a1');
      expect(const BoardCoord(file: 6, rank: 0).toAlgebraic(), 'g1');
      expect(const BoardCoord(file: 10, rank: 11).toAlgebraic(), 'k12');

      expect(
        BoardCoord.fromAlgebraic('a1'),
        const BoardCoord(file: 0, rank: 0),
      );
      expect(
        BoardCoord.fromAlgebraic(' G1 '),
        const BoardCoord(file: 6, rank: 0),
      );
      expect(
        BoardCoord.fromAlgebraic('K12'),
        const BoardCoord(file: 10, rank: 11),
      );
    });

    test('throws RangeError or FormatException on invalid algebraic inputs', () {
      expect(
        () => const BoardCoord(file: 11, rank: 0).toAlgebraic(),
        throwsRangeError,
      );
      expect(
        () => const BoardCoord(file: 0, rank: 12).toAlgebraic(),
        throwsRangeError,
      );

      for (final invalid in <String>[
        '',
        'a',
        'l1',
        'a0',
        'a01',
        'a+1',
        'g-1',
        'g02',
        'a13',
        'g100',
        '1a',
      ]) {
        expect(
          () => BoardCoord.fromAlgebraic(invalid),
          throwsFormatException,
          reason: 'Expected FormatException for "$invalid"',
        );
      }
    });

    test('throws FormatException (never UnsupportedError) on non-finite JSON coordinates', () {
      final decodedInf =
          jsonDecode('{"file": 1e999, "rank": 0}') as Map<String, dynamic>;
      expect(() => BoardCoord.fromJson(decodedInf), throwsFormatException);

      for (final bad in <Object>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(
          () => BoardCoord.fromJson(<String, dynamic>{'file': bad, 'rank': 0}),
          throwsFormatException,
        );
        expect(
          () => BoardCoord.fromJson(<String, dynamic>{'file': 0, 'rank': bad}),
          throwsFormatException,
        );
      }
    });

    test('supports JSON round-trip, numeric-string coercion, and algebraic map', () {
      const coord = BoardCoord(file: 4, rank: 7);
      final json = coord.toJson();
      expect(json, <String, dynamic>{'file': 4, 'rank': 7});
      expect(BoardCoord.fromJson(json), coord);

      expect(
        BoardCoord.fromJson(<String, dynamic>{'file': '5', 'rank': '10'}),
        const BoardCoord(file: 5, rank: 10),
      );
      expect(
        BoardCoord.fromJson(<String, dynamic>{'algebraic': 'f7'}),
        const BoardCoord(file: 5, rank: 6),
      );
    });

    test('BoardTileSpec supports JSON round-trip and snake_case keys', () {
      const spec = BoardTileSpec(
        coord: BoardCoord(file: 3, rank: 5),
        terrain: TerrainType.mixed,
        isEstuary: true,
        isRiverBorder: true,
        isFordAdjacent: false,
      );
      expect(BoardTileSpec.fromJson(spec.toJson()), spec);

      final parsedSnake = BoardTileSpec.fromJson(<String, dynamic>{
        'coord': <String, dynamic>{'file': 5, 'rank': 5},
        'terrain': 'land',
        'is_ford_adjacent': 'true',
        'is_estuary': false,
        'is_river_border': 'true',
      });
      expect(parsedSnake.terrain, TerrainType.land);
      expect(parsedSnake.isFordAdjacent, isTrue);
      expect(parsedSnake.isRiverBorder, isTrue);
    });
  });

  group('PieceType & PieceEntity', () {
    test('defines all 11 canonical piece types with FEN, points, heavy, and carrier metadata', () {
      expect(PieceType.values, hasLength(11));

      final expectedFen = <PieceType, String>{
        PieceType.commander: 'C',
        PieceType.headquarters: 'H',
        PieceType.infantry: 'I',
        PieceType.militia: 'M',
        PieceType.engineer: 'E',
        PieceType.tank: 'T',
        PieceType.artillery: 'A',
        PieceType.antiAircraft: 'G',
        PieceType.missile: 'S',
        PieceType.airForce: 'F',
        PieceType.navy: 'N',
      };
      final expectedPoints = <PieceType, int>{
        PieceType.commander: 100,
        PieceType.navy: 80,
        PieceType.airForce: 40,
        PieceType.artillery: 30,
        PieceType.tank: 20,
        PieceType.missile: 20,
        PieceType.headquarters: 10,
        PieceType.infantry: 10,
        PieceType.militia: 10,
        PieceType.engineer: 10,
        PieceType.antiAircraft: 10,
      };
      final expectedCapacity = <PieceType, int>{
        PieceType.navy: 2,
        PieceType.airForce: 2,
        PieceType.tank: 2,
        PieceType.engineer: 1,
        PieceType.headquarters: 1,
        PieceType.commander: 0,
        PieceType.infantry: 0,
        PieceType.militia: 0,
        PieceType.artillery: 0,
        PieceType.antiAircraft: 0,
        PieceType.missile: 0,
      };

      for (final type in PieceType.values) {
        expect(type.fenChar, expectedFen[type]);
        expect(type.fenCharFor(PlayerSide.red), expectedFen[type]);
        expect(type.fenCharFor(PlayerSide.blue), expectedFen[type]!.toLowerCase());
        expect(PieceType.tryFromFenChar(type.fenChar), type);
        expect(PieceType.tryFromFenChar(type.fenChar.toLowerCase()), type);
        expect(type.basePoints, expectedPoints[type]);
        expect(type.carrierCapacity, expectedCapacity[type]);
        expect(type.displayNameEn, isNotEmpty);
        expect(type.displayNameVi, isNotEmpty);
      }

      expect(PieceType.tryFromFenChar('Z'), isNull);
      expect(PieceType.tryFromFenChar('CC'), isNull);

      expect(PieceType.artillery.isHeavy, isTrue);
      expect(PieceType.antiAircraft.isHeavy, isTrue);
      expect(PieceType.missile.isHeavy, isTrue);
      expect(PieceType.tank.isHeavy, isFalse);
      expect(PieceType.infantry.isHeavy, isFalse);

      expect(PieceType.antiAircraft.airDefenseRadius, 1);
      expect(PieceType.navy.airDefenseRadius, 1);
      expect(PieceType.missile.airDefenseRadius, 2);
      expect(PieceType.infantry.airDefenseRadius, 0);
    });

    test('PieceEntity round-trips Hero flag, carriedPieces stack, and computes totalPoints', () {
      const passenger1 = PieceEntity(
        id: 'red_infantry_c5',
        side: PlayerSide.red,
        type: PieceType.infantry,
        position: BoardCoord(file: 1, rank: 4),
        isHero: true,
      );
      const passenger2 = PieceEntity(
        id: 'red_militia_g4',
        side: PlayerSide.red,
        type: PieceType.militia,
        position: BoardCoord(file: 1, rank: 4),
      );
      const carrier = PieceEntity(
        id: 'red_navy_b2',
        side: PlayerSide.red,
        type: PieceType.navy,
        position: BoardCoord(file: 1, rank: 4),
        isHero: true,
        carriedPieces: <PieceEntity>[passenger1, passenger2],
        isAlive: true,
      );

      // Navy (80 + 10 Hero) + Infantry (10 + 10 Hero) + Militia (10) = 120.
      expect(carrier.totalPoints, 120);

      final roundTripped = PieceEntity.fromJson(carrier.toJson());
      expect(roundTripped, carrier);
      expect(roundTripped.isHero, isTrue);
      expect(roundTripped.carriedPieces, hasLength(2));
      expect(roundTripped.carriedPieces.first.isHero, isTrue);

      final snakeCaseParsed = PieceEntity.fromJson(<String, dynamic>{
        'id': 'blue_aa_d10',
        'side': 'blue',
        'type': 'anti_aircraft',
        'position': <String, dynamic>{'file': 3, 'rank': 9},
        'is_hero': 'true',
        'is_alive': 'false',
        'carried_pieces': <Map<String, dynamic>>[],
      });
      expect(snakeCaseParsed.side, PlayerSide.blue);
      expect(snakeCaseParsed.type, PieceType.antiAircraft);
      expect(snakeCaseParsed.isHero, isTrue);
      expect(snakeCaseParsed.isAlive, isFalse);
    });
  });

  group('GameMove, GameSessionState, Result & AppFailure', () {
    test('GameMove & LegalActionHint support JSON round-trip and nullable copyWith clearing', () {
      final timestamp = DateTime.utc(2026, 11, 20, 12, 30, 0);
      final move = GameMove(
        side: PlayerSide.red,
        pieceId: 'red_artillery_d3',
        from: const BoardCoord(file: 3, rank: 2),
        to: const BoardCoord(file: 3, rank: 5),
        kind: ActionKind.stayCapture,
        targetPieceId: 'blue_tank_d6',
        carriedPieceId: null,
        timestampUtc: timestamp,
      );

      final roundTripped = GameMove.fromJson(move.toJson());
      expect(roundTripped, move);

      final cleared = move.copyWith(targetPieceId: null);
      expect(cleared.targetPieceId, isNull);

      const hint = LegalActionHint(
        targetCoord: BoardCoord(file: 3, rank: 5),
        kind: ActionKind.stayCapture,
        targetPieceId: 'blue_tank_d6',
      );
      expect(LegalActionHint.fromJson(hint.toJson()), hint);
    });

    test('GameSessionState round-trips JSON and resolves pieceAt / pieceById across stacks', () {
      final timestamp = DateTime.utc(2026, 11, 20, 12, 0, 0);
      const passenger = PieceEntity(
        id: 'red_commander_embarked',
        side: PlayerSide.red,
        type: PieceType.commander,
        position: BoardCoord(file: 5, rank: 1),
      );
      const hq = PieceEntity(
        id: 'red_headquarters_f2',
        side: PlayerSide.red,
        type: PieceType.headquarters,
        position: BoardCoord(file: 5, rank: 1),
        carriedPieces: <PieceEntity>[passenger],
      );
      const defeated = PieceEntity(
        id: 'blue_militia_f2',
        side: PlayerSide.blue,
        type: PieceType.militia,
        position: BoardCoord(file: 5, rank: 1),
        isAlive: false,
      );

      final state = GameSessionState(
        matchId: 'match_42',
        mode: GameMode.localPassAndPlay,
        pieces: const <PieceEntity>[defeated, hq],
        currentTurn: PlayerSide.blue,
        phase: MatchPhase.finished,
        winner: PlayerSide.red,
        victoryReason: VictoryReason.commanderCaptured,
        moveHistory: <GameMove>[
          GameMove(
            side: PlayerSide.red,
            pieceId: 'red_tank_f1',
            from: const BoardCoord(file: 5, rank: 0),
            to: const BoardCoord(file: 5, rank: 1),
            kind: ActionKind.capture,
            targetPieceId: 'blue_militia_f2',
            timestampUtc: timestamp,
          ),
        ],
        turnNumber: 2,
        variantConfig: const RuleVariantConfig(
          hqShelterEnabled: true,
          fourBattleMode: true,
          allowDrawByRepetition: false,
        ),
      );

      expect(state.pieceAt(const BoardCoord(file: 5, rank: 1)), hq);
      expect(state.pieceById('red_commander_embarked'), passenger);
      expect(state.pieceById('missing_id'), isNull);

      final roundTripped = GameSessionState.fromJson(state.toJson());
      expect(roundTripped, state);

      final clearedWinner = state.copyWith(
        phase: MatchPhase.playing,
        winner: null,
        victoryReason: null,
      );
      expect(clearedWinner.winner, isNull);
      expect(clearedWinner.victoryReason, isNull);
    });

    test('GameSessionState.fromJson returns null for bogus winner and throws FormatException on non-finite ints', () {
      final bogusWinnerState = GameSessionState.fromJson(<String, dynamic>{
        'matchId': 'm_bogus',
        'winner': 'bogus',
      });
      expect(bogusWinnerState.winner, isNull);

      final numericWinnerState = GameSessionState.fromJson(<String, dynamic>{
        'matchId': 'm_num_winner',
        'winner': 123,
      });
      expect(numericWinnerState.winner, isNull);

      final decodedInfTurn =
          jsonDecode('{"matchId": "m_inf", "turnNumber": 1e999}')
              as Map<String, dynamic>;
      expect(
        () => GameSessionState.fromJson(decodedInfTurn),
        throwsFormatException,
      );

      for (final badNum in <double>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(
          () => GameSessionState.fromJson(<String, dynamic>{
            'matchId': 'm_bad',
            'turnNumber': badNum,
          }),
          throwsFormatException,
        );
        expect(
          () => GameSessionState.fromJson(<String, dynamic>{
            'matchId': 'm_bad',
            'boardRanks': badNum,
          }),
          throwsFormatException,
        );
        expect(
          () => GameSessionState.fromJson(<String, dynamic>{
            'matchId': 'm_bad',
            'boardFiles': badNum,
          }),
          throwsFormatException,
        );
      }
    });

    test('Result<T>, AppFailure subtypes, and FixedClock behave deterministically', () {
      const ok = Ok<int>(42);
      const err = Err<int>(
        ValidationAppFailure(
          'Invalid input',
          code: 'BAD_INPUT',
          fieldErrors: <String, String>{'field': 'required'},
        ),
      );

      expect(ok.isOk, isTrue);
      expect(ok.isErr, isFalse);
      expect(ok.valueOrNull, 42);
      expect(ok.failureOrNull, isNull);
      expect(ok.when(ok: (d) => d + 1, err: (_) => -1), 43);

      expect(err.isOk, isFalse);
      expect(err.isErr, isTrue);
      expect(err.valueOrNull, isNull);
      expect(err.failureOrNull, isA<ValidationAppFailure>());
      expect(err.when(ok: (_) => 'ok', err: (f) => f.code ?? ''), 'BAD_INPUT');

      const net = NetworkAppFailure('timeout', code: 'NET', mayHaveCommitted: true);
      const auth = AuthAppFailure('unauthorized', code: '401');
      const server = ServerAppFailure('boom', code: '500', statusCode: 500);
      const rules = RulesViolationFailure('illegal', code: 'ILLEGAL');

      expect(net.mayHaveCommitted, isTrue);
      expect(net.toString(), contains('[NET]'));
      expect(auth.toString(), contains('AuthAppFailure'));
      expect(server.statusCode, 500);
      expect(rules.toString(), contains('RulesViolationFailure'));

      final clock = FixedClock(DateTime.utc(2026, 11, 20, 10, 0, 0));
      expect(clock.nowUtc(), DateTime.utc(2026, 11, 20, 10, 0, 0));
      clock.advance(const Duration(seconds: 30));
      expect(clock.nowUtc(), DateTime.utc(2026, 11, 20, 10, 0, 30));
    });
  });
}
