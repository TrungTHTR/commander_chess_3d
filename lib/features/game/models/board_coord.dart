import 'package:equatable/equatable.dart';

/// Terrain classification for each of the 132 (11x12) board intersections.
enum TerrainType {
  /// Files `a` and `b` (0..1): accessible by Navy and airborne AirForce.
  deepSea,

  /// Coast (`c`, file 2) and Estuary (`d6, e6, d7, e7`): shared naval/land zone.
  mixed,

  /// Inland files `d..k` (3..10), excluding estuary dual-use classification.
  land,
}

/// Edge classification between two adjacent intersections.
enum EdgeTerrainType {
  normal,
  riverGap,
  ford,
  coastBoundary,
}

/// Logical vertical domain layer for movement and interception checks.
enum DomainLayer {
  ground,
  sea,
  air,
}

/// Intersection coordinate on the 11x12 Commander Chess board.
///
/// [file] spans `0..10` (algebraic `a..k`, left sea flank to right land flank).
/// [rank] spans `0..11` (algebraic `1..12`, Red baseline `0..5` to Blue `6..11`).
final class BoardCoord extends Equatable {
  const BoardCoord({
    required this.file,
    required this.rank,
  });

  static const int fileCount = 11;
  static const int rankCount = 12;

  final int file;
  final int rank;

  bool get isValid =>
      file >= 0 && file < fileCount && rank >= 0 && rank < rankCount;

  /// Algebraic notation such as `'g1'` (file `6`, rank `0`) or `'k12'`.
  String toAlgebraic() {
    RangeError.checkValueInInterval(file, 0, fileCount - 1, 'file');
    RangeError.checkValueInInterval(rank, 0, rankCount - 1, 'rank');
    final fileChar = String.fromCharCode('a'.codeUnitAt(0) + file);
    return '$fileChar${rank + 1}';
  }

  static final RegExp _algebraicRegex = RegExp(r'^([a-k])([1-9]|1[0-2])$');

  /// Parses algebraic notation such as `'g1'` or `'k12'` (case-insensitive).
  factory BoardCoord.fromAlgebraic(String notation) {
    final trimmed = notation.trim().toLowerCase();
    final match = _algebraicRegex.firstMatch(trimmed);
    if (match == null) {
      throw FormatException('Invalid algebraic coordinate: "$notation"');
    }
    final fileCode = match.group(1)!.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rankNum = int.parse(match.group(2)!);
    return BoardCoord(file: fileCode, rank: rankNum - 1);
  }

  /// Author `(rank,file)` tuple notation.
  String toNotation() => '($rank,$file)';

  BoardCoord copyWith({
    int? file,
    int? rank,
  }) {
    return BoardCoord(
      file: file ?? this.file,
      rank: rank ?? this.rank,
    );
  }

  factory BoardCoord.fromJson(Map<String, dynamic> json) {
    final algebraic = json['algebraic'];
    if (algebraic is String && json['file'] == null && json['rank'] == null) {
      return BoardCoord.fromAlgebraic(algebraic);
    }
    return BoardCoord(
      file: _asInt(json['file']),
      rank: _asInt(json['rank']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'file': file,
        'rank': rank,
      };

  static int _asInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) {
      if (!value.isFinite) {
        throw FormatException('Expected finite numeric value, got $value');
      }
      return value.toInt();
    }
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  @override
  List<Object?> get props => <Object?>[file, rank];
}

/// Static terrain metadata for a single board intersection.
final class BoardTileSpec extends Equatable {
  const BoardTileSpec({
    required this.coord,
    required this.terrain,
    this.isFordAdjacent = false,
    this.isEstuary = false,
    this.isRiverBorder = false,
  });

  final BoardCoord coord;
  final TerrainType terrain;
  final bool isFordAdjacent;
  final bool isEstuary;
  final bool isRiverBorder;

  BoardTileSpec copyWith({
    BoardCoord? coord,
    TerrainType? terrain,
    bool? isFordAdjacent,
    bool? isEstuary,
    bool? isRiverBorder,
  }) {
    return BoardTileSpec(
      coord: coord ?? this.coord,
      terrain: terrain ?? this.terrain,
      isFordAdjacent: isFordAdjacent ?? this.isFordAdjacent,
      isEstuary: isEstuary ?? this.isEstuary,
      isRiverBorder: isRiverBorder ?? this.isRiverBorder,
    );
  }

  factory BoardTileSpec.fromJson(Map<String, dynamic> json) {
    final rawCoord = json['coord'];
    final coordMap = rawCoord is Map<String, dynamic>
        ? rawCoord
        : rawCoord is Map
            ? Map<String, dynamic>.from(rawCoord)
            : const <String, dynamic>{};
    return BoardTileSpec(
      coord: BoardCoord.fromJson(coordMap),
      terrain: _parseTerrain(json['terrain']),
      isFordAdjacent: _asBool(
        json['isFordAdjacent'] ?? json['is_ford_adjacent'],
      ),
      isEstuary: _asBool(json['isEstuary'] ?? json['is_estuary']),
      isRiverBorder: _asBool(
        json['isRiverBorder'] ?? json['is_river_border'],
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'coord': coord.toJson(),
        'terrain': terrain.name,
        'isFordAdjacent': isFordAdjacent,
        'isEstuary': isEstuary,
        'isRiverBorder': isRiverBorder,
      };

  static TerrainType _parseTerrain(Object? raw) {
    if (raw is String) {
      final normalized = raw.trim().toLowerCase().replaceAll('_', '');
      for (final value in TerrainType.values) {
        if (value.name.toLowerCase() == normalized) {
          return value;
        }
      }
    }
    return TerrainType.land;
  }

  static bool _asBool(Object? raw, [bool fallback = false]) {
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
        coord,
        terrain,
        isFordAdjacent,
        isEstuary,
        isRiverBorder,
      ];
}
