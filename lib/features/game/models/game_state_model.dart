import 'package:equatable/equatable.dart';

import 'action_model.dart';
import 'board_coord.dart';
import 'piece_model.dart';

enum GameMode {
  localPassAndPlay,
  vsAi,
  onlineMultiplayer;

  static GameMode fromJsonValue(
    Object? raw, {
    GameMode fallback = GameMode.localPassAndPlay,
  }) {
    if (raw is String) {
      final normalized = raw.trim().toLowerCase().replaceAll('_', '');
      for (final value in GameMode.values) {
        if (value.name.toLowerCase() == normalized) return value;
      }
    }
    return fallback;
  }
}

enum MatchPhase {
  setup,
  playing,
  check,
  finished;

  static MatchPhase fromJsonValue(
    Object? raw, {
    MatchPhase fallback = MatchPhase.playing,
  }) {
    if (raw is String) {
      final normalized = raw.trim().toLowerCase().replaceAll('_', '');
      for (final value in MatchPhase.values) {
        if (value.name.toLowerCase() == normalized) return value;
      }
    }
    return fallback;
  }
}

enum VictoryReason {
  commanderCaptured,
  divisionEliminated,
  resignation,
  timeout,
  draw;

  static VictoryReason? fromJsonValue(Object? raw) {
    if (raw is String) {
      final normalized = raw.trim().toLowerCase().replaceAll('_', '');
      for (final value in VictoryReason.values) {
        if (value.name.toLowerCase() == normalized) return value;
      }
    }
    return null;
  }
}

/// Configurable rule policy flags defaulting to `commanderchess.app` v1.3.
final class RuleVariantConfig extends Equatable {
  const RuleVariantConfig({
    this.hqShelterEnabled = true,
    this.fourBattleMode = false,
    this.allowDrawByRepetition = true,
  });

  final bool hqShelterEnabled;
  final bool fourBattleMode;
  final bool allowDrawByRepetition;

  RuleVariantConfig copyWith({
    bool? hqShelterEnabled,
    bool? fourBattleMode,
    bool? allowDrawByRepetition,
  }) {
    return RuleVariantConfig(
      hqShelterEnabled: hqShelterEnabled ?? this.hqShelterEnabled,
      fourBattleMode: fourBattleMode ?? this.fourBattleMode,
      allowDrawByRepetition:
          allowDrawByRepetition ?? this.allowDrawByRepetition,
    );
  }

  factory RuleVariantConfig.fromJson(Map<String, dynamic> json) {
    return RuleVariantConfig(
      hqShelterEnabled: _asBool(
        json['hqShelterEnabled'] ?? json['hq_shelter_enabled'],
        true,
      ),
      fourBattleMode: _asBool(
        json['fourBattleMode'] ?? json['four_battle_mode'],
        false,
      ),
      allowDrawByRepetition: _asBool(
        json['allowDrawByRepetition'] ?? json['allow_draw_by_repetition'],
        true,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hqShelterEnabled': hqShelterEnabled,
        'fourBattleMode': fourBattleMode,
        'allowDrawByRepetition': allowDrawByRepetition,
      };

  static bool _asBool(Object? raw, bool fallback) {
    if (raw is bool) return raw;
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return fallback;
  }

  @override
  List<Object?> get props => <Object?>[
        hqShelterEnabled,
        fourBattleMode,
        allowDrawByRepetition,
      ];
}

/// Complete immutable snapshot of an active or finished Commander Chess match.
final class GameSessionState extends Equatable {
  static const Object _unset = Object();

  const GameSessionState({
    required this.matchId,
    required this.mode,
    this.boardRanks = BoardCoord.rankCount,
    this.boardFiles = BoardCoord.fileCount,
    required this.pieces,
    required this.currentTurn,
    required this.phase,
    this.winner,
    this.victoryReason,
    this.moveHistory = const <GameMove>[],
    this.turnNumber = 1,
    this.variantConfig = const RuleVariantConfig(),
  });

  final String matchId;
  final GameMode mode;
  final int boardRanks;
  final int boardFiles;
  final List<PieceEntity> pieces;
  final PlayerSide currentTurn;
  final MatchPhase phase;
  final PlayerSide? winner;
  final VictoryReason? victoryReason;
  final List<GameMove> moveHistory;
  final int turnNumber;
  final RuleVariantConfig variantConfig;

  /// Returns the alive top-level piece occupying [coord], or `null` if empty.
  PieceEntity? pieceAt(BoardCoord coord) {
    for (final piece in pieces) {
      if (piece.isAlive && piece.position == coord) {
        return piece;
      }
    }
    return null;
  }

  /// Finds a piece by [id] across top-level pieces and carried stacks.
  PieceEntity? pieceById(String id) {
    for (final piece in pieces) {
      final found = _findInStack(piece, id);
      if (found != null) return found;
    }
    return null;
  }

  static PieceEntity? _findInStack(PieceEntity piece, String id) {
    if (piece.id == id) return piece;
    for (final carried in piece.carriedPieces) {
      final found = _findInStack(carried, id);
      if (found != null) return found;
    }
    return null;
  }

  GameSessionState copyWith({
    String? matchId,
    GameMode? mode,
    int? boardRanks,
    int? boardFiles,
    List<PieceEntity>? pieces,
    PlayerSide? currentTurn,
    MatchPhase? phase,
    Object? winner = _unset,
    Object? victoryReason = _unset,
    List<GameMove>? moveHistory,
    int? turnNumber,
    RuleVariantConfig? variantConfig,
  }) {
    return GameSessionState(
      matchId: matchId ?? this.matchId,
      mode: mode ?? this.mode,
      boardRanks: boardRanks ?? this.boardRanks,
      boardFiles: boardFiles ?? this.boardFiles,
      pieces: pieces != null
          ? List<PieceEntity>.unmodifiable(pieces)
          : this.pieces,
      currentTurn: currentTurn ?? this.currentTurn,
      phase: phase ?? this.phase,
      winner: identical(winner, _unset) ? this.winner : winner as PlayerSide?,
      victoryReason: identical(victoryReason, _unset)
          ? this.victoryReason
          : victoryReason as VictoryReason?,
      moveHistory: moveHistory != null
          ? List<GameMove>.unmodifiable(moveHistory)
          : this.moveHistory,
      turnNumber: turnNumber ?? this.turnNumber,
      variantConfig: variantConfig ?? this.variantConfig,
    );
  }

  factory GameSessionState.fromJson(Map<String, dynamic> json) {
    final rawPieces = json['pieces'];
    final parsedPieces = <PieceEntity>[];
    if (rawPieces is List) {
      for (final item in rawPieces) {
        if (item is Map<String, dynamic>) {
          parsedPieces.add(PieceEntity.fromJson(item));
        } else if (item is Map) {
          parsedPieces
              .add(PieceEntity.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final rawHistory = json['moveHistory'] ?? json['move_history'];
    final parsedHistory = <GameMove>[];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (item is Map<String, dynamic>) {
          parsedHistory.add(GameMove.fromJson(item));
        } else if (item is Map) {
          parsedHistory.add(GameMove.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final rawWinner = json['winner'];
    final rawConfig = json['variantConfig'] ?? json['variant_config'];
    final configMap = rawConfig is Map<String, dynamic>
        ? rawConfig
        : rawConfig is Map
            ? Map<String, dynamic>.from(rawConfig)
            : null;

    return GameSessionState(
      matchId: _asString(json['matchId'] ?? json['match_id']),
      mode: GameMode.fromJsonValue(json['mode']),
      boardRanks: _asInt(
        json['boardRanks'] ?? json['board_ranks'],
        BoardCoord.rankCount,
      ),
      boardFiles: _asInt(
        json['boardFiles'] ?? json['board_files'],
        BoardCoord.fileCount,
      ),
      pieces: List<PieceEntity>.unmodifiable(parsedPieces),
      currentTurn: PlayerSide.fromJsonValue(
        json['currentTurn'] ?? json['current_turn'],
      ),
      phase: MatchPhase.fromJsonValue(json['phase']),
      winner: PlayerSide.tryFromJsonValue(rawWinner),
      victoryReason: VictoryReason.fromJsonValue(
        json['victoryReason'] ?? json['victory_reason'],
      ),
      moveHistory: List<GameMove>.unmodifiable(parsedHistory),
      turnNumber: _asInt(json['turnNumber'] ?? json['turn_number'], 1),
      variantConfig: configMap == null
          ? const RuleVariantConfig()
          : RuleVariantConfig.fromJson(configMap),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'matchId': matchId,
        'mode': mode.name,
        'boardRanks': boardRanks,
        'boardFiles': boardFiles,
        'pieces': pieces.map((e) => e.toJson()).toList(growable: false),
        'currentTurn': currentTurn.name,
        'phase': phase.name,
        if (winner != null) 'winner': winner!.name,
        if (victoryReason != null) 'victoryReason': victoryReason!.name,
        'moveHistory':
            moveHistory.map((e) => e.toJson()).toList(growable: false),
        'turnNumber': turnNumber,
        'variantConfig': variantConfig.toJson(),
      };

  static String _asString(Object? raw, [String fallback = '']) =>
      raw == null ? fallback : raw.toString();

  static int _asInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) {
      if (!raw.isFinite) {
        throw FormatException('Expected finite numeric value, got $raw');
      }
      return raw.toInt();
    }
    if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
    return fallback;
  }

  @override
  List<Object?> get props => <Object?>[
        matchId,
        mode,
        boardRanks,
        boardFiles,
        pieces,
        currentTurn,
        phase,
        winner,
        victoryReason,
        moveHistory,
        turnNumber,
        variantConfig,
      ];
}
