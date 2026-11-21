import 'package:equatable/equatable.dart';

import 'board_coord.dart';
import 'piece_model.dart';

/// Distinct action modes supported by Commander Chess rules.
enum ActionKind {
  move,
  capture,
  stayCapture,
  embark,
  disembark;

  static ActionKind fromJsonValue(
    Object? raw, {
    ActionKind fallback = ActionKind.move,
  }) {
    if (raw is String) {
      final normalized = raw.trim().toLowerCase().replaceAll('_', '');
      for (final value in ActionKind.values) {
        if (value.name.toLowerCase() == normalized) return value;
      }
    }
    return fallback;
  }
}

/// Immutable representation of a submitted or historical turn action.
final class GameMove extends Equatable {
  static const Object _unset = Object();

  const GameMove({
    required this.side,
    required this.pieceId,
    required this.from,
    required this.to,
    required this.kind,
    this.targetPieceId,
    this.carriedPieceId,
    required this.timestampUtc,
  });

  final PlayerSide side;
  final String pieceId;
  final BoardCoord from;
  final BoardCoord to;
  final ActionKind kind;
  final String? targetPieceId;
  final String? carriedPieceId;
  final DateTime timestampUtc;

  GameMove copyWith({
    PlayerSide? side,
    String? pieceId,
    BoardCoord? from,
    BoardCoord? to,
    ActionKind? kind,
    Object? targetPieceId = _unset,
    Object? carriedPieceId = _unset,
    DateTime? timestampUtc,
  }) {
    return GameMove(
      side: side ?? this.side,
      pieceId: pieceId ?? this.pieceId,
      from: from ?? this.from,
      to: to ?? this.to,
      kind: kind ?? this.kind,
      targetPieceId: identical(targetPieceId, _unset)
          ? this.targetPieceId
          : targetPieceId as String?,
      carriedPieceId: identical(carriedPieceId, _unset)
          ? this.carriedPieceId
          : carriedPieceId as String?,
      timestampUtc: timestampUtc ?? this.timestampUtc,
    );
  }

  factory GameMove.fromJson(Map<String, dynamic> json) {
    return GameMove(
      side: PlayerSide.fromJsonValue(json['side']),
      pieceId: _asString(json['pieceId'] ?? json['piece_id']),
      from: BoardCoord.fromJson(_asMap(json['from'])),
      to: BoardCoord.fromJson(_asMap(json['to'])),
      kind: ActionKind.fromJsonValue(json['kind']),
      targetPieceId: _asNullableString(
        json['targetPieceId'] ?? json['target_piece_id'],
      ),
      carriedPieceId: _asNullableString(
        json['carriedPieceId'] ?? json['carried_piece_id'],
      ),
      timestampUtc: _asUtcDateTime(
        json['timestampUtc'] ?? json['timestamp_utc'],
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'side': side.name,
        'pieceId': pieceId,
        'from': from.toJson(),
        'to': to.toJson(),
        'kind': kind.name,
        if (targetPieceId != null) 'targetPieceId': targetPieceId,
        if (carriedPieceId != null) 'carriedPieceId': carriedPieceId,
        'timestampUtc': timestampUtc.toUtc().toIso8601String(),
      };

  static Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  static String _asString(Object? raw, [String fallback = '']) =>
      raw == null ? fallback : raw.toString();

  static String? _asNullableString(Object? raw) {
    if (raw == null) return null;
    final str = raw.toString();
    return str.isEmpty ? null : str;
  }

  static DateTime _asUtcDateTime(Object? raw) {
    if (raw is DateTime) return raw.toUtc();
    if (raw is String) {
      final parsed = DateTime.tryParse(raw.trim());
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  @override
  List<Object?> get props => <Object?>[
        side,
        pieceId,
        from,
        to,
        kind,
        targetPieceId,
        carriedPieceId,
        timestampUtc.toUtc(),
      ];
}

/// UI/engine hint describing a single legal destination for a selected piece.
final class LegalActionHint extends Equatable {
  const LegalActionHint({
    required this.targetCoord,
    required this.kind,
    this.targetPieceId,
  });

  final BoardCoord targetCoord;
  final ActionKind kind;
  final String? targetPieceId;

  LegalActionHint copyWith({
    BoardCoord? targetCoord,
    ActionKind? kind,
    String? targetPieceId,
  }) {
    return LegalActionHint(
      targetCoord: targetCoord ?? this.targetCoord,
      kind: kind ?? this.kind,
      targetPieceId: targetPieceId ?? this.targetPieceId,
    );
  }

  factory LegalActionHint.fromJson(Map<String, dynamic> json) {
    final rawCoord = json['targetCoord'] ?? json['target_coord'];
    final coordMap = rawCoord is Map<String, dynamic>
        ? rawCoord
        : rawCoord is Map
            ? Map<String, dynamic>.from(rawCoord)
            : const <String, dynamic>{};
    final rawTarget = json['targetPieceId'] ?? json['target_piece_id'];
    return LegalActionHint(
      targetCoord: BoardCoord.fromJson(coordMap),
      kind: ActionKind.fromJsonValue(json['kind']),
      targetPieceId: rawTarget?.toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'targetCoord': targetCoord.toJson(),
        'kind': kind.name,
        if (targetPieceId != null) 'targetPieceId': targetPieceId,
      };

  @override
  List<Object?> get props => <Object?>[targetCoord, kind, targetPieceId];
}

/// Pure rules validation output for a candidate [GameMove].
final class MoveValidationResult extends Equatable {
  const MoveValidationResult({
    required this.isValid,
    this.reason,
    this.normalizedMove,
  });

  final bool isValid;
  final String? reason;
  final GameMove? normalizedMove;

  @override
  List<Object?> get props => <Object?>[isValid, reason, normalizedMove];
}
