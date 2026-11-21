import 'package:equatable/equatable.dart';

import 'action_model.dart';
import 'game_state_model.dart';
import 'piece_model.dart';

/// Client-to-server DTO for submitting a move over REST or WebSocket.
final class MoveSubmissionDto extends Equatable {
  static const Object _unset = Object();

  const MoveSubmissionDto({
    required this.matchId,
    required this.playerId,
    required this.expectedTurnNumber,
    required this.move,
    this.clientRequestId,
  });

  final String matchId;
  final String playerId;
  final int expectedTurnNumber;
  final GameMove move;
  final String? clientRequestId;

  MoveSubmissionDto copyWith({
    String? matchId,
    String? playerId,
    int? expectedTurnNumber,
    GameMove? move,
    Object? clientRequestId = _unset,
  }) {
    return MoveSubmissionDto(
      matchId: matchId ?? this.matchId,
      playerId: playerId ?? this.playerId,
      expectedTurnNumber: expectedTurnNumber ?? this.expectedTurnNumber,
      move: move ?? this.move,
      clientRequestId: identical(clientRequestId, _unset)
          ? this.clientRequestId
          : clientRequestId as String?,
    );
  }

  factory MoveSubmissionDto.fromJson(Map<String, dynamic> json) {
    return MoveSubmissionDto(
      matchId: _asString(json['matchId'] ?? json['match_id']),
      playerId: _asString(json['playerId'] ?? json['player_id']),
      expectedTurnNumber: _asInt(
        json['expectedTurnNumber'] ?? json['expected_turn_number'],
        1,
      ),
      move: GameMove.fromJson(_asMap(json['move'])),
      clientRequestId: _asNullableString(
        json['clientRequestId'] ?? json['client_request_id'],
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'matchId': matchId,
        'playerId': playerId,
        'expectedTurnNumber': expectedTurnNumber,
        'move': move.toJson(),
        if (clientRequestId != null) 'clientRequestId': clientRequestId,
      };

  @override
  List<Object?> get props => <Object?>[
        matchId,
        playerId,
        expectedTurnNumber,
        move,
        clientRequestId,
      ];
}

/// Real-time server-to-client synchronization event payload.
final class MatchSyncEventDto extends Equatable {
  static const Object _unset = Object();

  const MatchSyncEventDto({
    required this.matchId,
    required this.sequenceNumber,
    required this.eventType,
    required this.occurredAtUtc,
    this.move,
    this.sessionSnapshot,
    this.errorMessage,
  });

  final String matchId;
  final int sequenceNumber;
  final String eventType;
  final DateTime occurredAtUtc;
  final GameMove? move;
  final GameSessionState? sessionSnapshot;
  final String? errorMessage;

  MatchSyncEventDto copyWith({
    String? matchId,
    int? sequenceNumber,
    String? eventType,
    DateTime? occurredAtUtc,
    Object? move = _unset,
    Object? sessionSnapshot = _unset,
    Object? errorMessage = _unset,
  }) {
    return MatchSyncEventDto(
      matchId: matchId ?? this.matchId,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      eventType: eventType ?? this.eventType,
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      move: identical(move, _unset) ? this.move : move as GameMove?,
      sessionSnapshot: identical(sessionSnapshot, _unset)
          ? this.sessionSnapshot
          : sessionSnapshot as GameSessionState?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  factory MatchSyncEventDto.fromJson(Map<String, dynamic> json) {
    final rawMove = json['move'];
    final rawSnapshot = json['sessionSnapshot'] ?? json['session_snapshot'];
    return MatchSyncEventDto(
      matchId: _asString(json['matchId'] ?? json['match_id']),
      sequenceNumber: _asInt(
        json['sequenceNumber'] ?? json['sequence_number'],
        0,
      ),
      eventType: _asString(json['eventType'] ?? json['event_type']),
      occurredAtUtc: _asUtcDateTime(
        json['occurredAtUtc'] ?? json['occurred_at_utc'],
      ),
      move: rawMove == null ? null : GameMove.fromJson(_asMap(rawMove)),
      sessionSnapshot: rawSnapshot == null
          ? null
          : GameSessionState.fromJson(_asMap(rawSnapshot)),
      errorMessage: _asNullableString(
        json['errorMessage'] ?? json['error_message'],
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'matchId': matchId,
        'sequenceNumber': sequenceNumber,
        'eventType': eventType,
        'occurredAtUtc': occurredAtUtc.toUtc().toIso8601String(),
        if (move != null) 'move': move!.toJson(),
        if (sessionSnapshot != null)
          'sessionSnapshot': sessionSnapshot!.toJson(),
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  @override
  List<Object?> get props => <Object?>[
        matchId,
        sequenceNumber,
        eventType,
        occurredAtUtc.toUtc(),
        move,
        sessionSnapshot,
        errorMessage,
      ];
}

/// Request payload for creating a new remote match.
final class CreateMatchRequestDto extends Equatable {
  static const Object _unset = Object();

  const CreateMatchRequestDto({
    this.mode = GameMode.onlineMultiplayer,
    this.preferredSide,
    this.variantConfig = const RuleVariantConfig(),
    this.timeControlSeconds = 900,
    this.incrementSeconds = 10,
  });

  final GameMode mode;
  final PlayerSide? preferredSide;
  final RuleVariantConfig variantConfig;
  final int timeControlSeconds;
  final int incrementSeconds;

  CreateMatchRequestDto copyWith({
    GameMode? mode,
    Object? preferredSide = _unset,
    RuleVariantConfig? variantConfig,
    int? timeControlSeconds,
    int? incrementSeconds,
  }) {
    return CreateMatchRequestDto(
      mode: mode ?? this.mode,
      preferredSide: identical(preferredSide, _unset)
          ? this.preferredSide
          : preferredSide as PlayerSide?,
      variantConfig: variantConfig ?? this.variantConfig,
      timeControlSeconds: timeControlSeconds ?? this.timeControlSeconds,
      incrementSeconds: incrementSeconds ?? this.incrementSeconds,
    );
  }

  factory CreateMatchRequestDto.fromJson(Map<String, dynamic> json) {
    final rawSide = json['preferredSide'] ?? json['preferred_side'];
    final rawConfig = json['variantConfig'] ?? json['variant_config'];
    return CreateMatchRequestDto(
      mode: GameMode.fromJsonValue(
        json['mode'],
        fallback: GameMode.onlineMultiplayer,
      ),
      preferredSide: PlayerSide.tryFromJsonValue(rawSide),
      variantConfig: rawConfig == null
          ? const RuleVariantConfig()
          : RuleVariantConfig.fromJson(_asMap(rawConfig)),
      timeControlSeconds: _asInt(
        json['timeControlSeconds'] ?? json['time_control_seconds'],
        900,
      ),
      incrementSeconds: _asInt(
        json['incrementSeconds'] ?? json['increment_seconds'],
        10,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode.name,
        if (preferredSide != null) 'preferredSide': preferredSide!.name,
        'variantConfig': variantConfig.toJson(),
        'timeControlSeconds': timeControlSeconds,
        'incrementSeconds': incrementSeconds,
      };

  @override
  List<Object?> get props => <Object?>[
        mode,
        preferredSide,
        variantConfig,
        timeControlSeconds,
        incrementSeconds,
      ];
}

/// Summary projection returned by match listing and lobby endpoints.
final class MatchSummaryDto extends Equatable {
  static const Object _unset = Object();

  const MatchSummaryDto({
    required this.matchId,
    required this.mode,
    required this.phase,
    required this.currentTurn,
    this.turnNumber = 1,
    this.redPlayerId,
    this.bluePlayerId,
    this.winner,
    this.victoryReason,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String matchId;
  final GameMode mode;
  final MatchPhase phase;
  final PlayerSide currentTurn;
  final int turnNumber;
  final String? redPlayerId;
  final String? bluePlayerId;
  final PlayerSide? winner;
  final VictoryReason? victoryReason;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  MatchSummaryDto copyWith({
    String? matchId,
    GameMode? mode,
    MatchPhase? phase,
    PlayerSide? currentTurn,
    int? turnNumber,
    Object? redPlayerId = _unset,
    Object? bluePlayerId = _unset,
    Object? winner = _unset,
    Object? victoryReason = _unset,
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
  }) {
    return MatchSummaryDto(
      matchId: matchId ?? this.matchId,
      mode: mode ?? this.mode,
      phase: phase ?? this.phase,
      currentTurn: currentTurn ?? this.currentTurn,
      turnNumber: turnNumber ?? this.turnNumber,
      redPlayerId: identical(redPlayerId, _unset)
          ? this.redPlayerId
          : redPlayerId as String?,
      bluePlayerId: identical(bluePlayerId, _unset)
          ? this.bluePlayerId
          : bluePlayerId as String?,
      winner: identical(winner, _unset) ? this.winner : winner as PlayerSide?,
      victoryReason: identical(victoryReason, _unset)
          ? this.victoryReason
          : victoryReason as VictoryReason?,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }

  factory MatchSummaryDto.fromJson(Map<String, dynamic> json) {
    final rawWinner = json['winner'];
    return MatchSummaryDto(
      matchId: _asString(json['matchId'] ?? json['match_id']),
      mode: GameMode.fromJsonValue(
        json['mode'],
        fallback: GameMode.onlineMultiplayer,
      ),
      phase: MatchPhase.fromJsonValue(json['phase']),
      currentTurn: PlayerSide.fromJsonValue(
        json['currentTurn'] ?? json['current_turn'],
      ),
      turnNumber: _asInt(json['turnNumber'] ?? json['turn_number'], 1),
      redPlayerId: _asNullableString(
        json['redPlayerId'] ?? json['red_player_id'],
      ),
      bluePlayerId: _asNullableString(
        json['bluePlayerId'] ?? json['blue_player_id'],
      ),
      winner: PlayerSide.tryFromJsonValue(rawWinner),
      victoryReason: VictoryReason.fromJsonValue(
        json['victoryReason'] ?? json['victory_reason'],
      ),
      createdAtUtc: _asUtcDateTime(
        json['createdAtUtc'] ?? json['created_at_utc'],
      ),
      updatedAtUtc: _asUtcDateTime(
        json['updatedAtUtc'] ?? json['updated_at_utc'],
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'matchId': matchId,
        'mode': mode.name,
        'phase': phase.name,
        'currentTurn': currentTurn.name,
        'turnNumber': turnNumber,
        if (redPlayerId != null) 'redPlayerId': redPlayerId,
        if (bluePlayerId != null) 'bluePlayerId': bluePlayerId,
        if (winner != null) 'winner': winner!.name,
        if (victoryReason != null) 'victoryReason': victoryReason!.name,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
      };

  @override
  List<Object?> get props => <Object?>[
        matchId,
        mode,
        phase,
        currentTurn,
        turnNumber,
        redPlayerId,
        bluePlayerId,
        winner,
        victoryReason,
        createdAtUtc.toUtc(),
        updatedAtUtc.toUtc(),
      ];
}

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}

String _asString(Object? raw, [String fallback = '']) =>
    raw == null ? fallback : raw.toString();

String? _asNullableString(Object? raw) {
  if (raw == null) return null;
  final str = raw.toString();
  return str.isEmpty ? null : str;
}

int _asInt(Object? raw, int fallback) {
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

DateTime _asUtcDateTime(Object? raw) {
  if (raw is DateTime) return raw.toUtc();
  if (raw is String) {
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
