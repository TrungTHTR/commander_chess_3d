import '../models/board_coord.dart';
import '../models/piece_model.dart';

/// Official standard 19-piece-per-side Cờ Tư Lệnh starting position FEN.
const String kStandardCommanderFen =
    '6c4/1n2fh1hf2/3a2s2a1/2n1gt1tg2/2ie2m2ei/11/11/2IE2M2EI/2N1GT1TG2/3A2S2A1/1N2FH1HF2/6C4 r - - 0 1';

/// Parses the piece-placement section of a Commander Chess FEN string.
///
/// Supports multi-digit empty file counts (such as `11` for an empty rank)
/// across the 12 ranks (`rank 11` down to `rank 0`) and 11 files (`0..10`).
List<PieceEntity> parseFenPieces(String fen) {
  final trimmed = fen.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('FEN string must not be empty.');
  }

  final fields = trimmed.split(RegExp(r'\s+'));
  final placement = fields.first;
  final rankSegments = placement.split('/');
  if (rankSegments.length != BoardCoord.rankCount) {
    throw FormatException(
      'Expected ${BoardCoord.rankCount} FEN ranks, got ${rankSegments.length}.',
    );
  }

  final pieces = <PieceEntity>[];

  for (var fenRankIdx = 0; fenRankIdx < rankSegments.length; fenRankIdx++) {
    final rankStr = rankSegments[fenRankIdx];
    final boardRank = BoardCoord.rankCount - 1 - fenRankIdx;
    var file = 0;
    var charIdx = 0;

    while (charIdx < rankStr.length) {
      final code = rankStr.codeUnitAt(charIdx);
      if (code >= _digitZeroCode && code <= _digitNineCode) {
        if (code == _digitZeroCode) {
          throw FormatException(
            'Leading zero empty count in FEN rank "$rankStr".',
          );
        }
        var emptyCount = 0;
        while (charIdx < rankStr.length) {
          final digitCode = rankStr.codeUnitAt(charIdx);
          if (digitCode < _digitZeroCode || digitCode > _digitNineCode) {
            break;
          }
          emptyCount = emptyCount * 10 + (digitCode - _digitZeroCode);
          if (emptyCount > BoardCoord.fileCount) {
            throw FormatException(
              'Empty count "$emptyCount" exceeds ${BoardCoord.fileCount} files in FEN rank "$rankStr".',
            );
          }
          charIdx++;
        }
        file += emptyCount;
        if (file > BoardCoord.fileCount) {
          throw FormatException(
            'Rank "$rankStr" exceeds ${BoardCoord.fileCount} files.',
          );
        }
        continue;
      }

      final symbol = rankStr[charIdx];
      final type = PieceType.tryFromFenChar(symbol);
      if (type == null) {
        throw FormatException(
          'Unknown piece symbol "$symbol" in FEN rank "$rankStr".',
        );
      }
      if (file >= BoardCoord.fileCount) {
        throw FormatException(
          'Rank "$rankStr" exceeds ${BoardCoord.fileCount} files.',
        );
      }

      final side = symbol == symbol.toUpperCase()
          ? PlayerSide.red
          : PlayerSide.blue;
      final coord = BoardCoord(file: file, rank: boardRank);
      pieces.add(
        PieceEntity(
          id: '${side.name}_${type.snakeCaseName}_${coord.toAlgebraic()}',
          side: side,
          type: type,
          position: coord,
        ),
      );
      file++;
      charIdx++;
    }

    if (file != BoardCoord.fileCount) {
      throw FormatException(
        'FEN rank "$rankStr" resolved to $file files; expected ${BoardCoord.fileCount}.',
      );
    }
  }

  return List<PieceEntity>.unmodifiable(pieces);
}

const int _digitZeroCode = 48;
const int _digitNineCode = 57;

/// Pure-Dart spatial topology contract for the 11×12 Commander Chess board.
abstract interface class BoardTopology {
  int get ranks;
  int get files;

  bool isValidCoord(BoardCoord coord);
  TerrainType terrainAt(BoardCoord coord);
  bool isEstuary(BoardCoord coord);
  bool isRiverCrossing(BoardCoord from, BoardCoord to);
  bool isFordCrossing(BoardCoord from, BoardCoord to);
  bool isPassableFor(PieceType type, BoardCoord coord);
  bool canCrossStep(PieceType type, BoardCoord from, BoardCoord to);
  List<BoardTileSpec> buildAllTiles();
  List<PieceEntity> createInitialPieces();
}

/// Standard 11×12 (132-intersection) Cờ Tư Lệnh board topology.
///
/// - Files `a, b` (`0, 1`): [TerrainType.deepSea].
/// - File `c` (`2`) + estuary (`d6, e6, d7, e7`): [TerrainType.mixed].
/// - Files `d..k` (`3..10`) excluding estuary: [TerrainType.land].
/// - River gap between `rank == 5` (rank 6) and `rank == 6` (rank 7), with
///   two shallow fords at `f6<->f7` (`file == 5`) and `h6<->h7` (`file == 7`).
final class StandardCommanderBoardTopology implements BoardTopology {
  const StandardCommanderBoardTopology();

  static const int _southRiverRank = 5;
  static const int _northRiverRank = 6;
  static const int _westFordFile = 5; // f
  static const int _eastFordFile = 7; // h

  @override
  int get ranks => BoardCoord.rankCount;

  @override
  int get files => BoardCoord.fileCount;

  @override
  bool isValidCoord(BoardCoord coord) =>
      coord.file >= 0 &&
      coord.file < files &&
      coord.rank >= 0 &&
      coord.rank < ranks;

  @override
  bool isEstuary(BoardCoord coord) =>
      isValidCoord(coord) &&
      (coord.file == 3 || coord.file == 4) &&
      (coord.rank == _southRiverRank || coord.rank == _northRiverRank);

  @override
  TerrainType terrainAt(BoardCoord coord) {
    if (!isValidCoord(coord)) {
      throw RangeError('Coordinate out of bounds: $coord');
    }
    if (coord.file <= 1) {
      return TerrainType.deepSea;
    }
    if (coord.file == 2 || isEstuary(coord)) {
      return TerrainType.mixed;
    }
    return TerrainType.land;
  }

  @override
  bool isRiverCrossing(BoardCoord from, BoardCoord to) {
    if (!isValidCoord(from) || !isValidCoord(to)) {
      return false;
    }
    final crossesGap =
        (from.rank <= _southRiverRank && to.rank >= _northRiverRank) ||
            (from.rank >= _northRiverRank && to.rank <= _southRiverRank);
    if (!crossesGap) {
      return false;
    }
    // Open ocean on files a/b (0..1) is deep sea, not the inland river gap.
    return from.file >= 2 || to.file >= 2;
  }

  @override
  bool isFordCrossing(BoardCoord from, BoardCoord to) {
    if (!isValidCoord(from) || !isValidCoord(to)) {
      return false;
    }
    if (from.file != to.file) {
      return false;
    }
    if (from.file != _westFordFile && from.file != _eastFordFile) {
      return false;
    }
    return (from.rank == _southRiverRank && to.rank == _northRiverRank) ||
        (from.rank == _northRiverRank && to.rank == _southRiverRank);
  }

  @override
  bool isPassableFor(PieceType type, BoardCoord coord) {
    if (!isValidCoord(coord)) {
      return false;
    }
    final terrain = terrainAt(coord);
    return switch (type) {
      PieceType.navy =>
        terrain == TerrainType.deepSea || terrain == TerrainType.mixed,
      PieceType.airForce => true,
      _ => terrain == TerrainType.mixed || terrain == TerrainType.land,
    };
  }

  @override
  bool canCrossStep(PieceType type, BoardCoord from, BoardCoord to) {
    if (!isValidCoord(from) || !isValidCoord(to)) {
      return false;
    }
    final df = (to.file - from.file).abs();
    final dr = (to.rank - from.rank).abs();
    if (df > 1 || dr > 1 || (df == 0 && dr == 0)) {
      return false;
    }

    if (!isPassableFor(type, from) || !isPassableFor(type, to)) {
      return false;
    }

    // Navy cannot cut across land corners diagonally (e.g. c5<->d6, c8<->d7).
    if (type == PieceType.navy && df == 1 && dr == 1) {
      final cornerA = BoardCoord(file: to.file, rank: from.rank);
      final cornerB = BoardCoord(file: from.file, rank: to.rank);
      if (!isPassableFor(PieceType.navy, cornerA) ||
          !isPassableFor(PieceType.navy, cornerB)) {
        return false;
      }
    }

    // Heavy pieces cannot cross the deep river except via shallow fords f/h.
    if (type.isHeavy &&
        isRiverCrossing(from, to) &&
        !isFordCrossing(from, to)) {
      return false;
    }

    return true;
  }

  @override
  List<BoardTileSpec> buildAllTiles() {
    final tiles = <BoardTileSpec>[];
    for (var rank = 0; rank < ranks; rank++) {
      for (var file = 0; file < files; file++) {
        final coord = BoardCoord(file: file, rank: rank);
        final isBankRank =
            rank == _southRiverRank || rank == _northRiverRank;
        tiles.add(
          BoardTileSpec(
            coord: coord,
            terrain: terrainAt(coord),
            isEstuary: isEstuary(coord),
            isRiverBorder: isBankRank && file >= 2,
            isFordAdjacent:
                isBankRank && (file == _westFordFile || file == _eastFordFile),
          ),
        );
      }
    }
    return List<BoardTileSpec>.unmodifiable(tiles);
  }

  @override
  List<PieceEntity> createInitialPieces() =>
      parseFenPieces(kStandardCommanderFen);
}
