import 'dart:math' as math;

import '../../../core/result/app_failure.dart';
import '../../../core/result/result.dart';
import '../models/action_model.dart';
import '../models/board_coord.dart';
import '../models/game_state_model.dart';
import '../models/piece_model.dart';
import 'board_topology.dart';

/// Pure-Dart rules engine contract for Cờ Tư Lệnh.
abstract interface class CommanderRulesEngine {
  GameSessionState createInitialSession({
    required String matchId,
    GameMode mode = GameMode.localPassAndPlay,
    RuleVariantConfig? variantConfig,
  });

  List<LegalActionHint> legalActionsFor({
    required GameSessionState state,
    required BoardCoord from,
  });

  MoveValidationResult validateMove({
    required GameSessionState state,
    required GameMove move,
  });

  Result<GameSessionState> applyMove({
    required GameSessionState state,
    required GameMove move,
  });

  ({MatchPhase phase, PlayerSide? winner, VictoryReason? reason})
      evaluateMatchOutcome(GameSessionState state);
}

/// Starter Cờ Tư Lệnh rules engine implementing 11×12 terrain/estuary/ford
/// admissibility, baseline movement & captures for all 11 piece types,
/// Headquarters immobility, Commander face-to-face prohibition, and victory.
final class StarterCommanderRulesEngine implements CommanderRulesEngine {
  const StarterCommanderRulesEngine({
    this.topology = const StandardCommanderBoardTopology(),
  });

  final BoardTopology topology;

  static const List<(int df, int dr)> _orthogonalDirs = <(int, int)>[
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
  ];

  static const List<(int df, int dr)> _diagonalDirs = <(int, int)>[
    (1, 1),
    (1, -1),
    (-1, 1),
    (-1, -1),
  ];

  static const List<(int df, int dr)> _allEightDirs = <(int, int)>[
    ..._orthogonalDirs,
    ..._diagonalDirs,
  ];

  @override
  GameSessionState createInitialSession({
    required String matchId,
    GameMode mode = GameMode.localPassAndPlay,
    RuleVariantConfig? variantConfig,
  }) {
    final pieces = topology.createInitialPieces();
    return GameSessionState(
      matchId: matchId,
      mode: mode,
      boardRanks: topology.ranks,
      boardFiles: topology.files,
      pieces: List<PieceEntity>.unmodifiable(pieces),
      currentTurn: PlayerSide.red,
      phase: MatchPhase.playing,
      turnNumber: 1,
      variantConfig: variantConfig ?? const RuleVariantConfig(),
    );
  }

  @override
  List<LegalActionHint> legalActionsFor({
    required GameSessionState state,
    required BoardCoord from,
  }) {
    if (state.phase == MatchPhase.finished || !topology.isValidCoord(from)) {
      return const <LegalActionHint>[];
    }

    final board = _buildBoardMap(state.pieces);
    final piece = board[from];
    if (piece == null || !piece.isAlive || piece.side != state.currentTurn) {
      return const <LegalActionHint>[];
    }
    if (piece.type == PieceType.headquarters) {
      return const <LegalActionHint>[];
    }

    final candidates = _generateRawHints(board, piece);
    final legal = <LegalActionHint>[];
    final seen = <(BoardCoord, ActionKind)>{};

    for (final hint in candidates) {
      if (_wouldCommandersFaceAfterAction(
        board,
        piece,
        hint.targetCoord,
        hint.kind,
      )) {
        continue;
      }
      if (_wouldLeaveOwnCommanderInCheck(
        board,
        piece,
        hint.targetCoord,
        hint.kind,
      )) {
        continue;
      }
      if (seen.add((hint.targetCoord, hint.kind))) {
        legal.add(hint);
      }
    }

    return List<LegalActionHint>.unmodifiable(legal);
  }

  @override
  MoveValidationResult validateMove({
    required GameSessionState state,
    required GameMove move,
  }) {
    if (state.phase == MatchPhase.finished) {
      return const MoveValidationResult(
        isValid: false,
        reason: 'Match is already finished.',
      );
    }

    if (move.side != state.currentTurn) {
      return MoveValidationResult(
        isValid: false,
        reason: "It is ${state.currentTurn.name}'s turn.",
      );
    }

    if (!topology.isValidCoord(move.from) ||
        !topology.isValidCoord(move.to)) {
      return const MoveValidationResult(
        isValid: false,
        reason: 'Move coordinates are out of board bounds.',
      );
    }

    if (move.from == move.to) {
      return const MoveValidationResult(
        isValid: false,
        reason: 'Origin and destination coordinates must differ.',
      );
    }

    if (move.kind == ActionKind.embark || move.kind == ActionKind.disembark) {
      return MoveValidationResult(
        isValid: false,
        reason: 'ActionKind.${move.kind.name} is not enabled in starter rules.',
      );
    }

    final piece = state.pieceAt(move.from);
    if (piece == null || !piece.isAlive) {
      return MoveValidationResult(
        isValid: false,
        reason: 'No active piece at ${move.from.toAlgebraic()}.',
      );
    }

    if (piece.id != move.pieceId) {
      return MoveValidationResult(
        isValid: false,
        reason:
            'Piece ID mismatch at ${move.from.toAlgebraic()}: expected ${piece.id}.',
      );
    }

    if (piece.side != move.side) {
      return MoveValidationResult(
        isValid: false,
        reason: 'Piece ${piece.id} does not belong to ${move.side.name}.',
      );
    }

    if (piece.type == PieceType.headquarters) {
      return const MoveValidationResult(
        isValid: false,
        reason: 'Headquarters is stationary and cannot move or capture.',
      );
    }

    final hints = legalActionsFor(state: state, from: move.from);
    LegalActionHint? exactMatch;
    LegalActionHint? coordMatch;

    for (final hint in hints) {
      if (hint.targetCoord == move.to) {
        coordMatch ??= hint;
        if (hint.kind == move.kind) {
          exactMatch = hint;
          break;
        }
      }
    }

    if (exactMatch == null) {
      if (coordMatch != null) {
        return MoveValidationResult(
          isValid: false,
          reason:
              'Action kind ${move.kind.name} is not valid for ${move.to.toAlgebraic()}; expected ${coordMatch.kind.name}.',
        );
      }
      return MoveValidationResult(
        isValid: false,
        reason:
            '${piece.type.displayNameEn} at ${move.from.toAlgebraic()} cannot ${move.kind.name} to ${move.to.toAlgebraic()}.',
      );
    }

    if (exactMatch.targetPieceId == null) {
      if (move.targetPieceId != null) {
        return MoveValidationResult(
          isValid: false,
          reason:
              'Non-capture move to ${move.to.toAlgebraic()} must not specify targetPieceId.',
        );
      }
    } else if (move.targetPieceId != null &&
        move.targetPieceId != exactMatch.targetPieceId) {
      return MoveValidationResult(
        isValid: false,
        reason:
            'Target piece mismatch at ${move.to.toAlgebraic()}: expected ${exactMatch.targetPieceId}.',
      );
    }

    final normalizedMove = move.targetPieceId == null &&
            exactMatch.targetPieceId != null
        ? move.copyWith(targetPieceId: exactMatch.targetPieceId)
        : move;

    return MoveValidationResult(
      isValid: true,
      normalizedMove: normalizedMove,
    );
  }

  @override
  Result<GameSessionState> applyMove({
    required GameSessionState state,
    required GameMove move,
  }) {
    final validation = validateMove(state: state, move: move);
    if (!validation.isValid) {
      return Err<GameSessionState>(
        RulesViolationFailure(
          validation.reason ?? 'Illegal move.',
          code: 'ILLEGAL_MOVE',
        ),
      );
    }

    final effectiveMove = validation.normalizedMove ?? move;
    final updatedPieces = <PieceEntity>[];

    for (final entity in state.pieces) {
      if (!entity.isAlive) {
        updatedPieces.add(entity);
        continue;
      }

      if (entity.id == effectiveMove.pieceId) {
        if (effectiveMove.kind == ActionKind.stayCapture) {
          updatedPieces.add(entity);
        } else {
          updatedPieces.add(entity.copyWith(position: effectiveMove.to));
        }
        continue;
      }

      if ((effectiveMove.kind == ActionKind.capture ||
              effectiveMove.kind == ActionKind.stayCapture) &&
          entity.position == effectiveMove.to) {
        updatedPieces.add(_markStackDefeated(entity));
        continue;
      }

      updatedPieces.add(entity);
    }

    final nextState = state.copyWith(
      pieces: List<PieceEntity>.unmodifiable(updatedPieces),
      currentTurn: state.currentTurn.opponent,
      turnNumber: state.turnNumber + 1,
      moveHistory: List<GameMove>.unmodifiable(
        <GameMove>[...state.moveHistory, effectiveMove],
      ),
    );

    final outcome = evaluateMatchOutcome(nextState);
    return Ok<GameSessionState>(
      nextState.copyWith(
        phase: outcome.phase,
        winner: outcome.winner,
        victoryReason: outcome.reason,
      ),
    );
  }

  @override
  ({MatchPhase phase, PlayerSide? winner, VictoryReason? reason})
      evaluateMatchOutcome(GameSessionState state) {
    if (state.phase == MatchPhase.finished && state.winner != null) {
      return (
        phase: MatchPhase.finished,
        winner: state.winner,
        reason: state.victoryReason,
      );
    }

    final redCommander = _findAliveCommander(state.pieces, PlayerSide.red);
    if (redCommander == null) {
      return (
        phase: MatchPhase.finished,
        winner: PlayerSide.blue,
        reason: VictoryReason.commanderCaptured,
      );
    }

    final blueCommander = _findAliveCommander(state.pieces, PlayerSide.blue);
    if (blueCommander == null) {
      return (
        phase: MatchPhase.finished,
        winner: PlayerSide.red,
        reason: VictoryReason.commanderCaptured,
      );
    }

    final turnCommander = state.currentTurn == PlayerSide.red
        ? redCommander
        : blueCommander;
    final otherCommander = state.currentTurn == PlayerSide.red
        ? blueCommander
        : redCommander;
    final board = _buildBoardMap(state.pieces);

    if (_isCoordUnderAttack(
          board: board,
          targetCoord: turnCommander.position,
          attackerSide: state.currentTurn.opponent,
        ) ||
        _isCoordUnderAttack(
          board: board,
          targetCoord: otherCommander.position,
          attackerSide: state.currentTurn,
        )) {
      return (
        phase: MatchPhase.check,
        winner: null,
        reason: null,
      );
    }

    return (
      phase: MatchPhase.playing,
      winner: null,
      reason: null,
    );
  }

  List<LegalActionHint> _generateRawHints(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity piece,
  ) {
    return switch (piece.type) {
      PieceType.headquarters => const <LegalActionHint>[],
      PieceType.commander => _commanderHints(board, piece),
      PieceType.infantry ||
      PieceType.engineer =>
        _singleStepLandHints(board, piece, _orthogonalDirs),
      PieceType.militia =>
        _singleStepLandHints(board, piece, _allEightDirs),
      PieceType.antiAircraft => _antiAircraftHints(board, piece),
      PieceType.tank => _tankHints(board, piece),
      PieceType.missile => _missileHints(board, piece),
      PieceType.artillery => _artilleryHints(board, piece),
      PieceType.airForce => _airForceHints(board, piece),
      PieceType.navy => _navyHints(board, piece),
    };
  }

  List<LegalActionHint> _commanderHints(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity piece,
  ) {
    final hints = <LegalActionHint>[];
    final from = piece.position;
    final maxSpan = math.max(topology.files, topology.ranks);

    for (final (df, dr) in _orthogonalDirs) {
      var prev = from;
      for (var step = 1; step <= maxSpan; step++) {
        final curr = BoardCoord(
          file: from.file + df * step,
          rank: from.rank + dr * step,
        );
        if (!topology.isValidCoord(curr)) {
          break;
        }
        final occ = board[curr];
        if (occ == null) {
          if (!topology.canCrossStep(PieceType.commander, prev, curr)) {
            break;
          }
          // §10.2: Commander cannot move through or into enemy Commander LoS.
          if (_wouldCommandersFaceAfterAction(
            board,
            piece,
            curr,
            ActionKind.move,
          )) {
            break;
          }
          hints.add(
            LegalActionHint(targetCoord: curr, kind: ActionKind.move),
          );
          prev = curr;
        } else {
          if (step == 1 &&
              occ.side != piece.side &&
              topology.isPassableFor(PieceType.commander, curr)) {
            hints.add(
              LegalActionHint(
                targetCoord: curr,
                kind: ActionKind.capture,
                targetPieceId: occ.id,
              ),
            );
          }
          break;
        }
      }
    }

    return hints;
  }

  List<LegalActionHint> _singleStepLandHints(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity piece,
    List<(int df, int dr)> dirs,
  ) {
    final hints = <LegalActionHint>[];
    final from = piece.position;

    for (final (df, dr) in dirs) {
      final to = BoardCoord(file: from.file + df, rank: from.rank + dr);
      if (!topology.isValidCoord(to)) {
        continue;
      }
      final occ = board[to];
      if (occ == null) {
        if (topology.canCrossStep(piece.type, from, to)) {
          hints.add(
            LegalActionHint(targetCoord: to, kind: ActionKind.move),
          );
        }
      } else if (occ.side != piece.side) {
        if (topology.terrainAt(to) == TerrainType.deepSea) {
          hints.add(
            LegalActionHint(
              targetCoord: to,
              kind: ActionKind.stayCapture,
              targetPieceId: occ.id,
            ),
          );
        } else if (topology.canCrossStep(piece.type, from, to)) {
          hints.add(
            LegalActionHint(
              targetCoord: to,
              kind: ActionKind.capture,
              targetPieceId: occ.id,
            ),
          );
        }
      }
    }

    return hints;
  }

  List<LegalActionHint> _antiAircraftHints(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity piece,
  ) {
    final hints = <LegalActionHint>[];
    final from = piece.position;

    for (final (df, dr) in _orthogonalDirs) {
      final to = BoardCoord(file: from.file + df, rank: from.rank + dr);
      if (!topology.isValidCoord(to)) {
        continue;
      }
      final occ = board[to];
      if (occ == null) {
        if (topology.canCrossStep(PieceType.antiAircraft, from, to)) {
          hints.add(
            LegalActionHint(targetCoord: to, kind: ActionKind.move),
          );
        }
      } else if (occ.side != piece.side) {
        if (topology.terrainAt(to) == TerrainType.deepSea) {
          hints.add(
            LegalActionHint(
              targetCoord: to,
              kind: ActionKind.stayCapture,
              targetPieceId: occ.id,
            ),
          );
        } else {
          // Heavy piece may capture across the river bank onto passable terrain.
          hints.add(
            LegalActionHint(
              targetCoord: to,
              kind: ActionKind.capture,
              targetPieceId: occ.id,
            ),
          );
        }
      }
    }

    return hints;
  }

  List<LegalActionHint> _tankHints(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity piece,
  ) {
    final hints = <LegalActionHint>[];
    final from = piece.position;

    for (final (df, dr) in _orthogonalDirs) {
      var prev = from;
      var canMoveFurther = true;

      for (var step = 1; step <= 2; step++) {
        final curr = BoardCoord(
          file: from.file + df * step,
          rank: from.rank + dr * step,
        );
        if (!topology.isValidCoord(curr)) {
          break;
        }
        final occ = board[curr];
        if (occ == null) {
          if (canMoveFurther &&
              topology.canCrossStep(PieceType.tank, prev, curr)) {
            hints.add(
              LegalActionHint(targetCoord: curr, kind: ActionKind.move),
            );
            prev = curr;
          } else {
            canMoveFurther = false;
          }
        } else {
          if (occ.side != piece.side) {
            if (topology.terrainAt(curr) == TerrainType.deepSea) {
              hints.add(
                LegalActionHint(
                  targetCoord: curr,
                  kind: ActionKind.stayCapture,
                  targetPieceId: occ.id,
                ),
              );
            } else if (canMoveFurther &&
                topology.canCrossStep(PieceType.tank, prev, curr)) {
              hints.add(
                LegalActionHint(
                  targetCoord: curr,
                  kind: ActionKind.capture,
                  targetPieceId: occ.id,
                ),
              );
            }
          }
          break;
        }
      }
    }

    return hints;
  }

  List<LegalActionHint> _missileHints(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity piece,
  ) {
    final hints = <LegalActionHint>[];
    final from = piece.position;

    // 1-2 steps orthogonal (blocked by intervening pieces).
    for (final (df, dr) in _orthogonalDirs) {
      var prev = from;
      var canMoveFurther = true;

      for (var step = 1; step <= 2; step++) {
        final curr = BoardCoord(
          file: from.file + df * step,
          rank: from.rank + dr * step,
        );
        if (!topology.isValidCoord(curr)) {
          break;
        }
        final occ = board[curr];
        if (occ == null) {
          if (canMoveFurther &&
              topology.canCrossStep(PieceType.missile, prev, curr)) {
            hints.add(
              LegalActionHint(targetCoord: curr, kind: ActionKind.move),
            );
            prev = curr;
          } else {
            canMoveFurther = false;
          }
        } else {
          if (occ.side != piece.side) {
            if (topology.terrainAt(curr) == TerrainType.deepSea) {
              hints.add(
                LegalActionHint(
                  targetCoord: curr,
                  kind: ActionKind.stayCapture,
                  targetPieceId: occ.id,
                ),
              );
            } else if (step == 1 ||
                (canMoveFurther &&
                    topology.canCrossStep(PieceType.missile, prev, curr))) {
              hints.add(
                LegalActionHint(
                  targetCoord: curr,
                  kind: ActionKind.capture,
                  targetPieceId: occ.id,
                ),
              );
            }
          }
          break;
        }
      }
    }

    // 1 step diagonal.
    for (final (df, dr) in _diagonalDirs) {
      final curr = BoardCoord(file: from.file + df, rank: from.rank + dr);
      if (!topology.isValidCoord(curr)) {
        continue;
      }
      final occ = board[curr];
      if (occ == null) {
        if (topology.canCrossStep(PieceType.missile, from, curr)) {
          hints.add(
            LegalActionHint(targetCoord: curr, kind: ActionKind.move),
          );
        }
      } else if (occ.side != piece.side) {
        if (topology.terrainAt(curr) == TerrainType.deepSea) {
          hints.add(
            LegalActionHint(
              targetCoord: curr,
              kind: ActionKind.stayCapture,
              targetPieceId: occ.id,
            ),
          );
        } else {
          hints.add(
            LegalActionHint(
              targetCoord: curr,
              kind: ActionKind.capture,
              targetPieceId: occ.id,
            ),
          );
        }
      }
    }

    return hints;
  }

  List<LegalActionHint> _artilleryHints(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity piece,
  ) {
    final hints = <LegalActionHint>[];
    final from = piece.position;

    for (final (df, dr) in _allEightDirs) {
      var prev = from;
      var moveBlocked = false;

      for (var step = 1; step <= 3; step++) {
        final curr = BoardCoord(
          file: from.file + df * step,
          rank: from.rank + dr * step,
        );
        if (!topology.isValidCoord(curr)) {
          break;
        }
        final occ = board[curr];
        if (occ == null) {
          if (!moveBlocked &&
              topology.canCrossStep(PieceType.artillery, prev, curr)) {
            hints.add(
              LegalActionHint(targetCoord: curr, kind: ActionKind.move),
            );
            prev = curr;
          } else {
            moveBlocked = true;
          }
        } else {
          moveBlocked = true;
          if (occ.side != piece.side) {
            if (topology.terrainAt(curr) == TerrainType.deepSea) {
              hints.add(
                LegalActionHint(
                  targetCoord: curr,
                  kind: ActionKind.stayCapture,
                  targetPieceId: occ.id,
                ),
              );
            } else {
              hints.add(
                LegalActionHint(
                  targetCoord: curr,
                  kind: ActionKind.capture,
                  targetPieceId: occ.id,
                ),
              );
            }
          }
        }
      }
    }

    return hints;
  }

  List<LegalActionHint> _airForceHints(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity piece,
  ) {
    final hints = <LegalActionHint>[];
    final from = piece.position;

    for (final (df, dr) in _allEightDirs) {
      for (var step = 1; step <= 4; step++) {
        final curr = BoardCoord(
          file: from.file + df * step,
          rank: from.rank + dr * step,
        );
        if (!topology.isValidCoord(curr)) {
          break;
        }
        final occ = board[curr];
        if (occ == null) {
          // Air Force flies over deepSea but cannot land on empty deepSea.
          if (topology.terrainAt(curr) != TerrainType.deepSea) {
            hints.add(
              LegalActionHint(targetCoord: curr, kind: ActionKind.move),
            );
          }
        } else if (occ.side != piece.side) {
          if (occ.type == PieceType.airForce) {
            if (topology.terrainAt(curr) != TerrainType.deepSea) {
              hints.add(
                LegalActionHint(
                  targetCoord: curr,
                  kind: ActionKind.capture,
                  targetPieceId: occ.id,
                ),
              );
            } else {
              // Air Force cannot land on deepSea; only stayCapture is legal.
              hints.add(
                LegalActionHint(
                  targetCoord: curr,
                  kind: ActionKind.stayCapture,
                  targetPieceId: occ.id,
                ),
              );
            }
          } else {
            hints.add(
              LegalActionHint(
                targetCoord: curr,
                kind: ActionKind.stayCapture,
                targetPieceId: occ.id,
              ),
            );
            if (topology.terrainAt(curr) != TerrainType.deepSea) {
              hints.add(
                LegalActionHint(
                  targetCoord: curr,
                  kind: ActionKind.capture,
                  targetPieceId: occ.id,
                ),
              );
            }
          }
        }
      }
    }

    return hints;
  }

  List<LegalActionHint> _navyHints(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity piece,
  ) {
    final hints = <LegalActionHint>[];
    final from = piece.position;

    for (final (df, dr) in _allEightDirs) {
      var prev = from;
      var moveBlocked = false;

      for (var step = 1; step <= 4; step++) {
        final curr = BoardCoord(
          file: from.file + df * step,
          rank: from.rank + dr * step,
        );
        if (!topology.isValidCoord(curr)) {
          break;
        }

        final stepValid = !moveBlocked &&
            topology.canCrossStep(PieceType.navy, prev, curr);
        if (!stepValid) {
          moveBlocked = true;
        }

        final occ = board[curr];
        if (stepValid) {
          if (occ == null) {
            hints.add(
              LegalActionHint(targetCoord: curr, kind: ActionKind.move),
            );
            prev = curr;
          } else if (occ.side == piece.side) {
            // Navy ignores friendly units when sailing along water/coast.
            prev = curr;
          } else {
            if (occ.type == PieceType.navy) {
              hints.add(
                LegalActionHint(
                  targetCoord: curr,
                  kind: ActionKind.capture,
                  targetPieceId: occ.id,
                ),
              );
              // Anti-ship missile stops at the first enemy Navy ship.
              moveBlocked = true;
            } else {
              // Verified Cờ Tư Lệnh coastal rule: Navy ignores friendly pieces
              // and land pieces on `mixed` coast (blocked only by enemy Navy),
              // while capturing enemy land/coastal pieces within range 1-3.
              if (step <= 3) {
                hints.add(
                  LegalActionHint(
                    targetCoord: curr,
                    kind: ActionKind.capture,
                    targetPieceId: occ.id,
                  ),
                );
              }
              prev = curr;
            }
          }
        } else if (step <= 3 &&
            occ != null &&
            occ.side != piece.side &&
            occ.type != PieceType.navy) {
          // Naval gun bombards land/coastal targets (range 1-3, jumps blockers)
          // while remaining in place when displacement is blocked or on land.
          hints.add(
            LegalActionHint(
              targetCoord: curr,
              kind: ActionKind.stayCapture,
              targetPieceId: occ.id,
            ),
          );
        }
      }
    }

    return hints;
  }

  bool _isCoordUnderAttack({
    required Map<BoardCoord, PieceEntity> board,
    required BoardCoord targetCoord,
    required PlayerSide attackerSide,
  }) {
    for (final piece in board.values) {
      if (!piece.isAlive || piece.side != attackerSide) {
        continue;
      }
      if (piece.type == PieceType.headquarters ||
          piece.type == PieceType.commander) {
        continue;
      }
      final hints = _generateRawHints(board, piece);
      for (final hint in hints) {
        if (hint.targetCoord == targetCoord &&
            (hint.kind == ActionKind.capture ||
                hint.kind == ActionKind.stayCapture)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _wouldCommandersFaceAfterAction(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity movingPiece,
    BoardCoord targetCoord,
    ActionKind kind,
  ) {
    final simulated = Map<BoardCoord, PieceEntity>.from(board);
    if (kind == ActionKind.stayCapture) {
      simulated.remove(targetCoord);
    } else {
      simulated.remove(movingPiece.position);
      simulated[targetCoord] = movingPiece.copyWith(position: targetCoord);
    }
    return _areCommandersFacing(simulated);
  }

  bool _wouldLeaveOwnCommanderInCheck(
    Map<BoardCoord, PieceEntity> board,
    PieceEntity movingPiece,
    BoardCoord targetCoord,
    ActionKind kind,
  ) {
    final simulated = Map<BoardCoord, PieceEntity>.from(board);
    if (kind == ActionKind.stayCapture) {
      simulated.remove(targetCoord);
    } else {
      simulated.remove(movingPiece.position);
      simulated[targetCoord] = movingPiece.copyWith(position: targetCoord);
    }

    PieceEntity? ownCommander;
    for (final entity in simulated.values) {
      if (!entity.isAlive || entity.side != movingPiece.side) continue;
      if (entity.type == PieceType.commander) {
        ownCommander = entity;
        break;
      }
      for (final carried in entity.carriedPieces) {
        if (carried.isAlive &&
            carried.type == PieceType.commander &&
            carried.side == movingPiece.side) {
          ownCommander = entity;
          break;
        }
      }
      if (ownCommander != null) break;
    }

    if (ownCommander == null) {
      return false;
    }

    return _isCoordUnderAttack(
      board: simulated,
      targetCoord: ownCommander.position,
      attackerSide: movingPiece.side.opponent,
    );
  }

  bool _areCommandersFacing(Map<BoardCoord, PieceEntity> board) {
    PieceEntity? redCommander;
    PieceEntity? blueCommander;

    for (final piece in board.values) {
      if (!piece.isAlive) continue;
      if (piece.type == PieceType.commander) {
        if (piece.side == PlayerSide.red) {
          redCommander = piece;
        } else {
          blueCommander = piece;
        }
      }
    }

    if (redCommander == null || blueCommander == null) {
      return false;
    }

    final a = redCommander.position;
    final b = blueCommander.position;

    if (a.file == b.file) {
      final minRank = math.min(a.rank, b.rank);
      final maxRank = math.max(a.rank, b.rank);
      for (var rank = minRank + 1; rank < maxRank; rank++) {
        if (board.containsKey(BoardCoord(file: a.file, rank: rank))) {
          return false;
        }
      }
      return true;
    }

    if (a.rank == b.rank) {
      final minFile = math.min(a.file, b.file);
      final maxFile = math.max(a.file, b.file);
      for (var file = minFile + 1; file < maxFile; file++) {
        if (board.containsKey(BoardCoord(file: file, rank: a.rank))) {
          return false;
        }
      }
      return true;
    }

    return false;
  }

  static Map<BoardCoord, PieceEntity> _buildBoardMap(
    List<PieceEntity> pieces,
  ) {
    final board = <BoardCoord, PieceEntity>{};
    for (final piece in pieces) {
      if (piece.isAlive) {
        board[piece.position] = piece;
      }
    }
    return board;
  }

  static PieceEntity? _findAliveCommander(
    List<PieceEntity> pieces,
    PlayerSide side,
  ) {
    for (final piece in pieces) {
      if (!piece.isAlive) continue;
      if (piece.type == PieceType.commander && piece.side == side) {
        return piece;
      }
      for (final carried in piece.carriedPieces) {
        if (carried.isAlive &&
            carried.type == PieceType.commander &&
            carried.side == side) {
          return carried;
        }
      }
    }
    return null;
  }

  static PieceEntity _markStackDefeated(PieceEntity piece) {
    final defeatedCarried = piece.carriedPieces
        .map(_markStackDefeated)
        .toList(growable: false);
    return piece.copyWith(
      isAlive: false,
      carriedPieces: defeatedCarried,
    );
  }
}
