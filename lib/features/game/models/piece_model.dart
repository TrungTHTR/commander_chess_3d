import 'package:equatable/equatable.dart';

import 'board_coord.dart';

/// Active player factions. Red occupies bottom ranks (1..5) and moves first.
enum PlayerSide {
  red,
  blue;

  PlayerSide get opponent =>
      this == PlayerSide.red ? PlayerSide.blue : PlayerSide.red;

  static PlayerSide? tryFromJsonValue(Object? raw) {
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      for (final side in PlayerSide.values) {
        if (side.name == normalized) return side;
      }
    }
    return null;
  }

  static PlayerSide fromJsonValue(
    Object? raw, {
    PlayerSide fallback = PlayerSide.red,
  }) =>
      tryFromJsonValue(raw) ?? fallback;
}

/// The 11 canonical Commander Chess (Cờ Tư Lệnh) unit types.
enum PieceType {
  commander,
  headquarters,
  infantry,
  militia,
  engineer,
  tank,
  artillery,
  antiAircraft,
  missile,
  airForce,
  navy;

  /// Uppercase FEN symbol (lowercase is used for Blue in FEN strings).
  String get fenChar => switch (this) {
        PieceType.commander => 'C',
        PieceType.headquarters => 'H',
        PieceType.infantry => 'I',
        PieceType.militia => 'M',
        PieceType.engineer => 'E',
        PieceType.tank => 'T',
        PieceType.artillery => 'A',
        PieceType.antiAircraft => 'G',
        PieceType.missile => 'S',
        PieceType.airForce => 'F',
        PieceType.navy => 'N',
      };

  /// Side-aware FEN character (uppercase for Red, lowercase for Blue).
  String fenCharFor(PlayerSide side) =>
      side == PlayerSide.red ? fenChar : fenChar.toLowerCase();

  /// Canonical `snake_case` identifier used in Blender node names and JSON.
  String get snakeCaseName => switch (this) {
        PieceType.antiAircraft => 'anti_aircraft',
        PieceType.airForce => 'air_force',
        _ => name,
      };

  String get displayNameEn => switch (this) {
        PieceType.commander => 'Commander',
        PieceType.headquarters => 'Headquarters',
        PieceType.infantry => 'Infantry',
        PieceType.militia => 'Militia',
        PieceType.engineer => 'Engineer',
        PieceType.tank => 'Tank',
        PieceType.artillery => 'Artillery',
        PieceType.antiAircraft => 'Anti-Aircraft',
        PieceType.missile => 'Missile',
        PieceType.airForce => 'Air Force',
        PieceType.navy => 'Navy',
      };

  String get displayNameVi => switch (this) {
        PieceType.commander => 'Tư lệnh',
        PieceType.headquarters => 'Sở chỉ huy',
        PieceType.infantry => 'Bộ binh',
        PieceType.militia => 'Dân quân',
        PieceType.engineer => 'Công binh',
        PieceType.tank => 'Xe tăng',
        PieceType.artillery => 'Pháo binh',
        PieceType.antiAircraft => 'Pháo cao xạ',
        PieceType.missile => 'Tên lửa',
        PieceType.airForce => 'Không quân',
        PieceType.navy => 'Hải quân',
      };

  /// Material point value per official v1.3 scoring rules (before Hero +10).
  int get basePoints => switch (this) {
        PieceType.commander => 100,
        PieceType.navy => 80,
        PieceType.airForce => 40,
        PieceType.artillery => 30,
        PieceType.tank => 20,
        PieceType.missile => 20,
        PieceType.headquarters => 10,
        PieceType.infantry => 10,
        PieceType.militia => 10,
        PieceType.engineer => 10,
        PieceType.antiAircraft => 10,
      };

  /// Heavy units (`Artillery`, `Anti-Aircraft`, `Missile`) cannot cross the
  /// deep river unassisted; they require fords (`f`/`h`), an `Engineer` ferry,
  /// or capturing across the bank.
  bool get isHeavy => switch (this) {
        PieceType.artillery ||
        PieceType.antiAircraft ||
        PieceType.missile =>
          true,
        _ => false,
      };

  /// Maximum number of carried passengers/sheltered units (`0` for non-carriers).
  int get carrierCapacity => switch (this) {
        PieceType.navy || PieceType.airForce || PieceType.tank => 2,
        PieceType.engineer || PieceType.headquarters => 1,
        _ => 0,
      };

  /// Base air-defense zone radius (`0` = no air-defense bubble).
  int get airDefenseRadius => switch (this) {
        PieceType.antiAircraft || PieceType.navy => 1,
        PieceType.missile => 2,
        _ => 0,
      };

  static PieceType? tryFromFenChar(String ch) {
    if (ch.length != 1) return null;
    final upper = ch.toUpperCase();
    for (final type in PieceType.values) {
      if (type.fenChar == upper) return type;
    }
    return null;
  }

  static PieceType? tryFromJsonValue(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.length == 1) {
        return tryFromFenChar(trimmed);
      }
      final normalized = trimmed.toLowerCase().replaceAll('_', '');
      for (final type in PieceType.values) {
        if (type.name.toLowerCase() == normalized) return type;
      }
    }
    return null;
  }

  static PieceType fromJsonValue(
    Object? raw, {
    PieceType fallback = PieceType.infantry,
  }) =>
      tryFromJsonValue(raw) ?? fallback;
}

/// Immutable domain entity representing a single piece (and optional carried stack).
final class PieceEntity extends Equatable {
  const PieceEntity({
    required this.id,
    required this.side,
    required this.type,
    required this.position,
    this.isHero = false,
    this.carriedPieces = const <PieceEntity>[],
    this.isAlive = true,
  });

  final String id;
  final PlayerSide side;
  final PieceType type;
  final BoardCoord position;
  final bool isHero;
  final List<PieceEntity> carriedPieces;
  final bool isAlive;

  /// Total point value of this piece (including +10 Hero bonus and passengers).
  int get totalPoints {
    var total = type.basePoints + (isHero ? 10 : 0);
    for (final passenger in carriedPieces) {
      total += passenger.totalPoints;
    }
    return total;
  }

  PieceEntity copyWith({
    String? id,
    PlayerSide? side,
    PieceType? type,
    BoardCoord? position,
    bool? isHero,
    List<PieceEntity>? carriedPieces,
    bool? isAlive,
  }) {
    return PieceEntity(
      id: id ?? this.id,
      side: side ?? this.side,
      type: type ?? this.type,
      position: position ?? this.position,
      isHero: isHero ?? this.isHero,
      carriedPieces: carriedPieces != null
          ? List<PieceEntity>.unmodifiable(carriedPieces)
          : this.carriedPieces,
      isAlive: isAlive ?? this.isAlive,
    );
  }

  factory PieceEntity.fromJson(Map<String, dynamic> json) {
    final rawPosition = json['position'];
    final posMap = rawPosition is Map<String, dynamic>
        ? rawPosition
        : rawPosition is Map
            ? Map<String, dynamic>.from(rawPosition)
            : const <String, dynamic>{};

    final rawCarried = json['carriedPieces'] ?? json['carried_pieces'];
    final carried = <PieceEntity>[];
    if (rawCarried is List) {
      for (final item in rawCarried) {
        if (item is Map<String, dynamic>) {
          carried.add(PieceEntity.fromJson(item));
        } else if (item is Map) {
          carried.add(PieceEntity.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return PieceEntity(
      id: _asString(json['id']),
      side: PlayerSide.fromJsonValue(json['side']),
      type: PieceType.fromJsonValue(json['type']),
      position: BoardCoord.fromJson(posMap),
      isHero: _asBool(json['isHero'] ?? json['is_hero']),
      carriedPieces: List<PieceEntity>.unmodifiable(carried),
      isAlive: _asBool(json['isAlive'] ?? json['is_alive'], true),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'side': side.name,
        'type': type.name,
        'position': position.toJson(),
        'isHero': isHero,
        'carriedPieces':
            carriedPieces.map((e) => e.toJson()).toList(growable: false),
        'isAlive': isAlive,
      };

  static String _asString(Object? v, [String fallback = '']) =>
      v == null ? fallback : v.toString();

  static bool _asBool(Object? v, [bool fallback = false]) {
    if (v is bool) return v;
    if (v is String) {
      final normalized = v.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return fallback;
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        side,
        type,
        position,
        isHero,
        carriedPieces,
        isAlive,
      ];
}
