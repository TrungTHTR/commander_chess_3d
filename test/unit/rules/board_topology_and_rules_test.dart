import 'package:commander_chess_3d/core/result/app_failure.dart';
import 'package:commander_chess_3d/features/game/models/action_model.dart';
import 'package:commander_chess_3d/features/game/models/board_coord.dart';
import 'package:commander_chess_3d/features/game/models/game_state_model.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:commander_chess_3d/features/game/rules/board_topology.dart';
import 'package:commander_chess_3d/features/game/rules/commander_rules_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const topology = StandardCommanderBoardTopology();
  const engine = StarterCommanderRulesEngine(topology: topology);
  final fixedUtc = DateTime.utc(2026, 11, 20, 14, 0, 0);

  group('StandardCommanderBoardTopology & FEN parsing', () {
    test('builds 132 intersections (11 files x 12 ranks) with exact terrain zones', () {
      expect(topology.files, 11);
      expect(topology.ranks, 12);

      final tiles = topology.buildAllTiles();
      expect(tiles, hasLength(132));
      expect(tiles.map((t) => t.coord).toSet(), hasLength(132));

      final estuaryCoords = <BoardCoord>{
        BoardCoord.fromAlgebraic('d6'),
        BoardCoord.fromAlgebraic('e6'),
        BoardCoord.fromAlgebraic('d7'),
        BoardCoord.fromAlgebraic('e7'),
      };

      for (var file = 0; file < topology.files; file++) {
        for (var rank = 0; rank < topology.ranks; rank++) {
          final coord = BoardCoord(file: file, rank: rank);
          expect(topology.isValidCoord(coord), isTrue);

          if (file <= 1) {
            expect(topology.terrainAt(coord), TerrainType.deepSea);
            expect(topology.isEstuary(coord), isFalse);
          } else if (file == 2 || estuaryCoords.contains(coord)) {
            expect(topology.terrainAt(coord), TerrainType.mixed);
            expect(topology.isEstuary(coord), estuaryCoords.contains(coord));
          } else {
            expect(topology.terrainAt(coord), TerrainType.land);
            expect(topology.isEstuary(coord), isFalse);
          }
        }
      }

      expect(
        () => topology.terrainAt(const BoardCoord(file: -1, rank: 0)),
        throwsRangeError,
      );
      expect(
        () => topology.terrainAt(const BoardCoord(file: 11, rank: 0)),
        throwsRangeError,
      );
    });

    test('identifies river crossings, f/h shallow fords, and heavy piece river restriction', () {
      final f6 = BoardCoord.fromAlgebraic('f6');
      final f7 = BoardCoord.fromAlgebraic('f7');
      final h6 = BoardCoord.fromAlgebraic('h6');
      final h7 = BoardCoord.fromAlgebraic('h7');
      final g6 = BoardCoord.fromAlgebraic('g6');
      final g7 = BoardCoord.fromAlgebraic('g7');
      final a6 = BoardCoord.fromAlgebraic('a6');
      final a7 = BoardCoord.fromAlgebraic('a7');

      expect(topology.isRiverCrossing(f6, f7), isTrue);
      expect(topology.isRiverCrossing(g6, g7), isTrue);
      expect(topology.isRiverCrossing(h7, h6), isTrue);
      // Open sea files a/b are not inland river crossings.
      expect(topology.isRiverCrossing(a6, a7), isFalse);
      // Same-side step does not cross the river.
      expect(
        topology.isRiverCrossing(
          BoardCoord.fromAlgebraic('g5'),
          g6,
        ),
        isFalse,
      );

      expect(topology.isFordCrossing(f6, f7), isTrue);
      expect(topology.isFordCrossing(f7, f6), isTrue);
      expect(topology.isFordCrossing(h6, h7), isTrue);
      expect(topology.isFordCrossing(g6, g7), isFalse);
      expect(topology.isFordCrossing(f6, g7), isFalse);

      // Heavy pieces can cross only at f6<->f7 and h6<->h7.
      for (final heavy in <PieceType>[
        PieceType.artillery,
        PieceType.antiAircraft,
        PieceType.missile,
      ]) {
        expect(topology.canCrossStep(heavy, f6, f7), isTrue);
        expect(topology.canCrossStep(heavy, h6, h7), isTrue);
        expect(topology.canCrossStep(heavy, g6, g7), isFalse);
      }

      // Light units can cross at any river bank intersection.
      expect(topology.canCrossStep(PieceType.infantry, g6, g7), isTrue);
      expect(topology.canCrossStep(PieceType.tank, g6, g7), isTrue);
    });

    test('enforces Navy diagonal corner-cut prohibition into estuary and passability', () {
      final c5 = BoardCoord.fromAlgebraic('c5');
      final c6 = BoardCoord.fromAlgebraic('c6');
      final c7 = BoardCoord.fromAlgebraic('c7');
      final c8 = BoardCoord.fromAlgebraic('c8');
      final d6 = BoardCoord.fromAlgebraic('d6');
      final d7 = BoardCoord.fromAlgebraic('d7');
      final b5 = BoardCoord.fromAlgebraic('b5');

      // Land corner cut c5->d6 (d5 is land) and c8->d7 (d8 is land) are blocked.
      expect(topology.canCrossStep(PieceType.navy, c5, d6), isFalse);
      expect(topology.canCrossStep(PieceType.navy, c8, d7), isFalse);

      // Moving inside mixed/deepSea diagonal is allowed: c6->d7 and b5->c6,
      // as well as orthogonal coast step c6->c7.
      expect(topology.canCrossStep(PieceType.navy, c6, d7), isTrue);
      expect(topology.canCrossStep(PieceType.navy, c6, c7), isTrue);
      expect(topology.canCrossStep(PieceType.navy, b5, c6), isTrue);

      // Passability by terrain.
      expect(topology.isPassableFor(PieceType.navy, b5), isTrue);
      expect(topology.isPassableFor(PieceType.navy, d6), isTrue);
      expect(
        topology.isPassableFor(PieceType.navy, BoardCoord.fromAlgebraic('d5')),
        isFalse,
      );
      expect(topology.isPassableFor(PieceType.infantry, b5), isFalse);
      expect(topology.isPassableFor(PieceType.airForce, b5), isTrue);
    });

    test('parses kStandardCommanderFen into 38 valid pieces (19 Red + 19 Blue)', () {
      final pieces = parseFenPieces(kStandardCommanderFen);
      expect(pieces, hasLength(38));

      final redPieces = pieces.where((p) => p.side == PlayerSide.red).toList();
      final bluePieces = pieces.where((p) => p.side == PlayerSide.blue).toList();
      expect(redPieces, hasLength(19));
      expect(bluePieces, hasLength(19));

      // All coordinates unique and passable.
      expect(pieces.map((p) => p.position).toSet(), hasLength(38));
      for (final piece in pieces) {
        expect(topology.isValidCoord(piece.position), isTrue);
        expect(topology.isPassableFor(piece.type, piece.position), isTrue);
      }

      // Check exact Red Commander / Navy / HQ positions.
      expect(
        redPieces.singleWhere((p) => p.type == PieceType.commander).position,
        BoardCoord.fromAlgebraic('g1'),
      );
      expect(
        bluePieces.singleWhere((p) => p.type == PieceType.commander).position,
        BoardCoord.fromAlgebraic('g12'),
      );
      expect(
        redPieces.where((p) => p.type == PieceType.navy).map((p) => p.position),
        unorderedEquals(<BoardCoord>[
          BoardCoord.fromAlgebraic('b2'),
          BoardCoord.fromAlgebraic('c4'),
        ]),
      );

      // Rejects malformed FEN inputs, including 64-bit integer overflow and leading zeros.
      for (final badFen in <String>[
        '',
        '11/11',
        '11/11/11/11/11/11/11/11/11/11/11/10',
        '11/11/11/11/11/11/11/11/11/11/11/0C9',
        '011/11/11/11/11/11/11/11/11/11/11/11',
        '18446744073709551627/11/11/11/11/11/11/11/11/11/11/11',
        '11/11/11/11/11/11/11/11/11/11/11/10Z',
        '11/11/11/11/11/11/11/11/11/11/11/12',
      ]) {
        expect(
          () => parseFenPieces(badFen),
          throwsFormatException,
          reason: 'Expected FormatException for bad FEN "$badFen"',
        );
      }
    });
  });

  group('StarterCommanderRulesEngine', () {
    test('enforces turn order and Headquarters immobility', () {
      final session = engine.createInitialSession(matchId: 'm1');
      expect(session.currentTurn, PlayerSide.red);
      expect(session.phase, MatchPhase.playing);
      expect(session.pieces, hasLength(38));

      // Headquarters cannot move.
      final hqCoord = BoardCoord.fromAlgebraic('f2');
      final hq = session.pieceAt(hqCoord)!;
      expect(hq.type, PieceType.headquarters);
      expect(engine.legalActionsFor(state: session, from: hqCoord), isEmpty);

      final hqMove = GameMove(
        side: PlayerSide.red,
        pieceId: hq.id,
        from: hqCoord,
        to: BoardCoord.fromAlgebraic('f3'),
        kind: ActionKind.move,
        timestampUtc: fixedUtc,
      );
      expect(
        engine.validateMove(state: session, move: hqMove).isValid,
        isFalse,
      );
      final hqApply = engine.applyMove(state: session, move: hqMove);
      expect(hqApply.isErr, isTrue);
      expect(hqApply.failureOrNull, isA<RulesViolationFailure>());

      // Blue cannot move during Red's turn.
      final blueInfantryCoord = BoardCoord.fromAlgebraic('c8');
      final blueInfantry = session.pieceAt(blueInfantryCoord)!;
      expect(
        engine.legalActionsFor(state: session, from: blueInfantryCoord),
        isEmpty,
      );
      final wrongTurnMove = GameMove(
        side: PlayerSide.blue,
        pieceId: blueInfantry.id,
        from: blueInfantryCoord,
        to: BoardCoord.fromAlgebraic('c7'),
        kind: ActionKind.move,
        timestampUtc: fixedUtc,
      );
      final wrongTurnValidation = engine.validateMove(
        state: session,
        move: wrongTurnMove,
      );
      expect(wrongTurnValidation.isValid, isFalse);
      expect(wrongTurnValidation.reason, contains('red'));
    });

    test('enforces heavy piece river ford restriction in move generation', () {
      final state = GameSessionState(
        matchId: 'heavy_ford',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
        pieces: <PieceEntity>[
          PieceEntity(
            id: 'red_commander',
            side: PlayerSide.red,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('k1'),
          ),
          PieceEntity(
            id: 'blue_commander',
            side: PlayerSide.blue,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('d12'),
          ),
          PieceEntity(
            id: 'red_artillery_g6',
            side: PlayerSide.red,
            type: PieceType.artillery,
            position: BoardCoord.fromAlgebraic('g6'),
          ),
          PieceEntity(
            id: 'red_artillery_f6',
            side: PlayerSide.red,
            type: PieceType.artillery,
            position: BoardCoord.fromAlgebraic('f6'),
          ),
        ],
      );

      // Artillery at g6 cannot cross directly to g7 (deep river).
      final g6Hints = engine.legalActionsFor(
        state: state,
        from: BoardCoord.fromAlgebraic('g6'),
      );
      expect(
        g6Hints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('g7')),
        isFalse,
      );
      expect(
        g6Hints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('f7')),
        isFalse,
      );

      // Artillery at f6 CAN cross the shallow ford f6 -> f7 (and f8).
      final f6Hints = engine.legalActionsFor(
        state: state,
        from: BoardCoord.fromAlgebraic('f6'),
      );
      expect(
        f6Hints.any(
          (h) =>
              h.targetCoord == BoardCoord.fromAlgebraic('f7') &&
              h.kind == ActionKind.move,
        ),
        isTrue,
      );
      expect(
        f6Hints.any(
          (h) =>
              h.targetCoord == BoardCoord.fromAlgebraic('f8') &&
              h.kind == ActionKind.move,
        ),
        isTrue,
      );
    });

    test('Artillery moves 1-3 unblocked and jumps blockers to capture', () {
      final state = GameSessionState(
        matchId: 'artillery_jump',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
        pieces: <PieceEntity>[
          PieceEntity(
            id: 'red_commander',
            side: PlayerSide.red,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('k1'),
          ),
          PieceEntity(
            id: 'blue_commander',
            side: PlayerSide.blue,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('d12'),
          ),
          PieceEntity(
            id: 'red_artillery',
            side: PlayerSide.red,
            type: PieceType.artillery,
            position: BoardCoord.fromAlgebraic('g2'),
          ),
          // Friendly blocker at g3 prevents empty movement to g4/g5,
          // but Artillery can still jump g3 to capture enemy at g5!
          PieceEntity(
            id: 'red_infantry_screen',
            side: PlayerSide.red,
            type: PieceType.infantry,
            position: BoardCoord.fromAlgebraic('g3'),
          ),
          PieceEntity(
            id: 'blue_tank_target',
            side: PlayerSide.blue,
            type: PieceType.tank,
            position: BoardCoord.fromAlgebraic('g5'),
          ),
        ],
      );

      final hints = engine.legalActionsFor(
        state: state,
        from: BoardCoord.fromAlgebraic('g2'),
      );

      // Cannot move to empty g4 through g3 blocker.
      expect(
        hints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('g4')),
        isFalse,
      );
      // Can jump g3 to capture enemy at g5.
      expect(
        hints,
        contains(
          LegalActionHint(
            targetCoord: BoardCoord.fromAlgebraic('g5'),
            kind: ActionKind.capture,
            targetPieceId: 'blue_tank_target',
          ),
        ),
      );
      // Unblocked horizontal move up to 3 steps (h2, i2, j2).
      expect(
        hints.any(
          (h) =>
              h.targetCoord == BoardCoord.fromAlgebraic('j2') &&
              h.kind == ActionKind.move,
        ),
        isTrue,
      );
    });

    test('AirForce flies over obstacles, cannot land on empty deepSea, and supports stayCapture bombing', () {
      final state = GameSessionState(
        matchId: 'air_force_rules',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
        pieces: <PieceEntity>[
          PieceEntity(
            id: 'red_commander',
            side: PlayerSide.red,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('k1'),
          ),
          PieceEntity(
            id: 'blue_commander',
            side: PlayerSide.blue,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('j12'),
          ),
          PieceEntity(
            id: 'red_air',
            side: PlayerSide.red,
            type: PieceType.airForce,
            position: BoardCoord.fromAlgebraic('d5'),
          ),
          // Friendly blocker at e5 on the way to f5.
          PieceEntity(
            id: 'red_blocker',
            side: PlayerSide.red,
            type: PieceType.infantry,
            position: BoardCoord.fromAlgebraic('e5'),
          ),
          // Enemy land piece at f5 (both stayCapture and capture available).
          PieceEntity(
            id: 'blue_tank_f5',
            side: PlayerSide.blue,
            type: PieceType.tank,
            position: BoardCoord.fromAlgebraic('f5'),
          ),
          // Enemy Navy at b5 in deepSea (stayCapture only, cannot displace onto deepSea).
          PieceEntity(
            id: 'blue_navy_b5',
            side: PlayerSide.blue,
            type: PieceType.navy,
            position: BoardCoord.fromAlgebraic('b5'),
          ),
        ],
      );

      final hints = engine.legalActionsFor(
        state: state,
        from: BoardCoord.fromAlgebraic('d5'),
      );

      // Cannot land on empty deepSea intersections (a5, b4, b6).
      expect(
        hints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('a5')),
        isFalse,
      );
      expect(
        hints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('b4')),
        isFalse,
      );

      // Flies over blocker e5 and can move to empty g5.
      expect(
        hints.any(
          (h) =>
              h.targetCoord == BoardCoord.fromAlgebraic('g5') &&
              h.kind == ActionKind.move,
        ),
        isTrue,
      );

      // Supports both stayCapture and capture on land target f5.
      expect(
        hints,
        containsAll(<LegalActionHint>[
          LegalActionHint(
            targetCoord: BoardCoord.fromAlgebraic('f5'),
            kind: ActionKind.stayCapture,
            targetPieceId: 'blue_tank_f5',
          ),
          LegalActionHint(
            targetCoord: BoardCoord.fromAlgebraic('f5'),
            kind: ActionKind.capture,
            targetPieceId: 'blue_tank_f5',
          ),
        ]),
      );

      // Enemy Navy on deepSea b5: stayCapture is allowed, capture displacement is NOT.
      expect(
        hints,
        contains(
          LegalActionHint(
            targetCoord: BoardCoord.fromAlgebraic('b5'),
            kind: ActionKind.stayCapture,
            targetPieceId: 'blue_navy_b5',
          ),
        ),
      );
      expect(
        hints.any(
          (h) =>
              h.targetCoord == BoardCoord.fromAlgebraic('b5') &&
              h.kind == ActionKind.capture,
        ),
        isFalse,
      );

      // Applying stayCapture keeps AirForce at d5 and defeats blue_navy_b5.
      final bombMove = GameMove(
        side: PlayerSide.red,
        pieceId: 'red_air',
        from: BoardCoord.fromAlgebraic('d5'),
        to: BoardCoord.fromAlgebraic('b5'),
        kind: ActionKind.stayCapture,
        targetPieceId: 'blue_navy_b5',
        timestampUtc: fixedUtc,
      );
      final applied = engine.applyMove(state: state, move: bombMove);
      expect(applied.isOk, isTrue);
      final next = applied.valueOrNull!;
      expect(next.pieceById('red_air')!.position, BoardCoord.fromAlgebraic('d5'));
      expect(next.pieceById('blue_navy_b5')!.isAlive, isFalse);
      expect(next.currentTurn, PlayerSide.blue);
      expect(next.turnNumber, 2);
    });

    test('enforces Commander face-to-face LoS prohibition', () {
      final state = GameSessionState(
        matchId: 'commander_los',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
        pieces: <PieceEntity>[
          PieceEntity(
            id: 'red_commander',
            side: PlayerSide.red,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('g1'),
          ),
          PieceEntity(
            id: 'blue_commander',
            side: PlayerSide.blue,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('g12'),
          ),
          // Sole screen piece between g1 and g12.
          PieceEntity(
            id: 'red_infantry_screen',
            side: PlayerSide.red,
            type: PieceType.infantry,
            position: BoardCoord.fromAlgebraic('g5'),
          ),
        ],
      );

      final screenHints = engine.legalActionsFor(
        state: state,
        from: BoardCoord.fromAlgebraic('g5'),
      );
      // Moving sideways to f5 or h5 would leave Commanders facing on file g!
      expect(
        screenHints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('f5')),
        isFalse,
      );
      expect(
        screenHints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('h5')),
        isFalse,
      );
      // Staying on file g (g4 / g6) keeps the screen intact and is legal.
      expect(
        screenHints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('g6')),
        isTrue,
      );

      // Commander cannot move into unobstructed facing rank either.
      final rankFacingState = GameSessionState(
        matchId: 'commander_rank_los',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
        pieces: <PieceEntity>[
          PieceEntity(
            id: 'red_commander',
            side: PlayerSide.red,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('g1'),
          ),
          PieceEntity(
            id: 'blue_commander',
            side: PlayerSide.blue,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('k2'),
          ),
        ],
      );
      final cmdHints = engine.legalActionsFor(
        state: rankFacingState,
        from: BoardCoord.fromAlgebraic('g1'),
      );
      expect(
        cmdHints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('g2')),
        isFalse,
      );
    });

    test('applyMove & evaluateMatchOutcome detect check and Commander capture victory', () {
      final state = GameSessionState(
        matchId: 'victory_check',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
        pieces: <PieceEntity>[
          PieceEntity(
            id: 'red_commander',
            side: PlayerSide.red,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('f1'),
          ),
          PieceEntity(
            id: 'blue_commander',
            side: PlayerSide.blue,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('g10'),
          ),
          PieceEntity(
            id: 'red_tank',
            side: PlayerSide.red,
            type: PieceType.tank,
            position: BoardCoord.fromAlgebraic('g8'),
          ),
        ],
      );

      // Moving tank g8 -> g9 puts Blue Commander at g10 in check.
      final checkMove = GameMove(
        side: PlayerSide.red,
        pieceId: 'red_tank',
        from: BoardCoord.fromAlgebraic('g8'),
        to: BoardCoord.fromAlgebraic('g9'),
        kind: ActionKind.move,
        timestampUtc: fixedUtc,
      );
      final checkedResult = engine.applyMove(state: state, move: checkMove);
      expect(checkedResult.isOk, isTrue);
      final checkedState = checkedResult.valueOrNull!;
      expect(checkedState.phase, MatchPhase.check);
      expect(checkedState.winner, isNull);

      // Capturing Blue Commander from g8 -> g10 ends the match with Red winning.
      final captureCommanderMove = GameMove(
        side: PlayerSide.red,
        pieceId: 'red_tank',
        from: BoardCoord.fromAlgebraic('g8'),
        to: BoardCoord.fromAlgebraic('g10'),
        kind: ActionKind.capture,
        targetPieceId: 'blue_commander',
        timestampUtc: fixedUtc,
      );
      final winResult = engine.applyMove(
        state: state,
        move: captureCommanderMove,
      );
      expect(winResult.isOk, isTrue);
      final wonState = winResult.valueOrNull!;
      expect(wonState.phase, MatchPhase.finished);
      expect(wonState.winner, PlayerSide.red);
      expect(wonState.victoryReason, VictoryReason.commanderCaptured);
      expect(wonState.moveHistory, hasLength(1));

      // No further moves allowed after match finishes.
      expect(
        engine.legalActionsFor(
          state: wonState,
          from: BoardCoord.fromAlgebraic('g10'),
        ),
        isEmpty,
      );
    });

    test('prevents pinned piece from exposing own Commander and Commander from walking into check', () {
      // Blue Tank at g3 pins Red Infantry at g2 against Red Commander at g1.
      final pinnedState = GameSessionState(
        matchId: 'pinned_piece',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
        pieces: <PieceEntity>[
          PieceEntity(
            id: 'red_commander',
            side: PlayerSide.red,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('g1'),
          ),
          PieceEntity(
            id: 'blue_commander',
            side: PlayerSide.blue,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('d12'),
          ),
          PieceEntity(
            id: 'red_infantry_pin',
            side: PlayerSide.red,
            type: PieceType.infantry,
            position: BoardCoord.fromAlgebraic('g2'),
          ),
          PieceEntity(
            id: 'blue_tank_pinner',
            side: PlayerSide.blue,
            type: PieceType.tank,
            position: BoardCoord.fromAlgebraic('g3'),
          ),
        ],
      );

      final infantryHints = engine.legalActionsFor(
        state: pinnedState,
        from: BoardCoord.fromAlgebraic('g2'),
      );
      // Moving sideways to f2 or h2 exposes g1 to Blue Tank at g3 (range 2).
      expect(
        infantryHints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('f2')),
        isFalse,
      );
      expect(
        infantryHints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('h2')),
        isFalse,
      );
      // Capturing the pinner g2 -> g3 is legal.
      expect(
        infantryHints,
        contains(
          LegalActionHint(
            targetCoord: BoardCoord.fromAlgebraic('g3'),
            kind: ActionKind.capture,
            targetPieceId: 'blue_tank_pinner',
          ),
        ),
      );

      // Commander cannot walk into check (f1 is attacked by Blue Tank at f3).
      final walkIntoCheckState = GameSessionState(
        matchId: 'commander_walk_check',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
        pieces: <PieceEntity>[
          PieceEntity(
            id: 'red_commander',
            side: PlayerSide.red,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('g1'),
          ),
          PieceEntity(
            id: 'blue_commander',
            side: PlayerSide.blue,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('d12'),
          ),
          PieceEntity(
            id: 'blue_tank_f3',
            side: PlayerSide.blue,
            type: PieceType.tank,
            position: BoardCoord.fromAlgebraic('f3'),
          ),
        ],
      );

      final commanderHints = engine.legalActionsFor(
        state: walkIntoCheckState,
        from: BoardCoord.fromAlgebraic('g1'),
      );
      expect(
        commanderHints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('f1')),
        isFalse,
      );
      expect(
        commanderHints.any((h) => h.targetCoord == BoardCoord.fromAlgebraic('h1')),
        isTrue,
      );
    });

    test('rejects ignoring MatchPhase.check and preserves check while Commander remains under attack', () {
      final inCheckState = GameSessionState(
        matchId: 'must_answer_check',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.check,
        pieces: <PieceEntity>[
          PieceEntity(
            id: 'red_commander',
            side: PlayerSide.red,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('g1'),
          ),
          PieceEntity(
            id: 'blue_commander',
            side: PlayerSide.blue,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('d12'),
          ),
          PieceEntity(
            id: 'blue_tank_attacker',
            side: PlayerSide.blue,
            type: PieceType.tank,
            position: BoardCoord.fromAlgebraic('g3'),
          ),
          PieceEntity(
            id: 'red_infantry_unrelated',
            side: PlayerSide.red,
            type: PieceType.infantry,
            position: BoardCoord.fromAlgebraic('c5'),
          ),
        ],
      );

      // Unrelated piece cannot move while Red Commander is in check.
      expect(
        engine.legalActionsFor(
          state: inCheckState,
          from: BoardCoord.fromAlgebraic('c5'),
        ),
        isEmpty,
      );
      final ignoredCheckMove = GameMove(
        side: PlayerSide.red,
        pieceId: 'red_infantry_unrelated',
        from: BoardCoord.fromAlgebraic('c5'),
        to: BoardCoord.fromAlgebraic('c6'),
        kind: ActionKind.move,
        timestampUtc: fixedUtc,
      );
      final rejected = engine.applyMove(
        state: inCheckState,
        move: ignoredCheckMove,
      );
      expect(rejected.isErr, isTrue);
      expect(rejected.failureOrNull, isA<RulesViolationFailure>());

      // evaluateMatchOutcome keeps MatchPhase.check while Commander is attacked.
      final outcome = engine.evaluateMatchOutcome(inCheckState);
      expect(outcome.phase, MatchPhase.check);
      expect(outcome.winner, isNull);

      // Even if turn belongs to the attacking side while opponent Commander is
      // under attack, evaluateMatchOutcome must never clear MatchPhase.check.
      final blueTurnStillChecked = inCheckState.copyWith(
        currentTurn: PlayerSide.blue,
      );
      expect(
        engine.evaluateMatchOutcome(blueTurnStillChecked).phase,
        MatchPhase.check,
      );
    });

    test('rejects non-capture ActionKind.move with non-null targetPieceId', () {
      final session = engine.createInitialSession(matchId: 'non_capture_target');
      final g5 = BoardCoord.fromAlgebraic('g5');
      final g6 = BoardCoord.fromAlgebraic('g6');
      final militia = session.pieceAt(g5)!;

      final invalidMove = GameMove(
        side: PlayerSide.red,
        pieceId: militia.id,
        from: g5,
        to: g6,
        kind: ActionKind.move,
        targetPieceId: 'bogus_target_id',
        timestampUtc: fixedUtc,
      );

      final validation = engine.validateMove(state: session, move: invalidMove);
      expect(validation.isValid, isFalse);
      expect(validation.reason, contains('targetPieceId'));

      final applied = engine.applyMove(state: session, move: invalidMove);
      expect(applied.isErr, isTrue);
      expect(applied.failureOrNull, isA<RulesViolationFailure>());
    });

    test('AirForce attacking enemy AirForce over deepSea emits stayCapture only (no landing capture)', () {
      final state = GameSessionState(
        matchId: 'air_vs_air_deep_sea',
        mode: GameMode.localPassAndPlay,
        currentTurn: PlayerSide.red,
        phase: MatchPhase.playing,
        pieces: <PieceEntity>[
          PieceEntity(
            id: 'red_commander',
            side: PlayerSide.red,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('k1'),
          ),
          PieceEntity(
            id: 'blue_commander',
            side: PlayerSide.blue,
            type: PieceType.commander,
            position: BoardCoord.fromAlgebraic('j12'),
          ),
          PieceEntity(
            id: 'red_air',
            side: PlayerSide.red,
            type: PieceType.airForce,
            position: BoardCoord.fromAlgebraic('d5'),
          ),
          PieceEntity(
            id: 'blue_air_deep_sea',
            side: PlayerSide.blue,
            type: PieceType.airForce,
            position: BoardCoord.fromAlgebraic('b5'),
          ),
        ],
      );

      final hints = engine.legalActionsFor(
        state: state,
        from: BoardCoord.fromAlgebraic('d5'),
      );
      final b5Hints = hints
          .where((h) => h.targetCoord == BoardCoord.fromAlgebraic('b5'))
          .toList();

      expect(b5Hints, hasLength(1));
      expect(b5Hints.single.kind, ActionKind.stayCapture);
      expect(b5Hints.single.targetPieceId, 'blue_air_deep_sea');
      expect(
        b5Hints.any((h) => h.kind == ActionKind.capture),
        isFalse,
      );
    });
  });
}
