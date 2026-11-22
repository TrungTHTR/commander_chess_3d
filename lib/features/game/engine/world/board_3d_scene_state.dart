import 'package:vector_math/vector_math_64.dart';

import '../../models/action_model.dart';
import '../../models/asset_manifest_model.dart';
import '../../models/board_coord.dart';

/// Single source of truth converting between logical 11×12 [BoardCoord]
/// intersections and 3D world-space coordinates (`1.0` unit = `1` tile, `+Y` up).
///
/// Matches `docs/BLENDER_ASSET_CONTRACT.md`:
/// - Files `a..k` (`0..10`) map to `X ∈ [-5.0, +5.0]`.
/// - Ranks `1..12` (`0..11`) map to `Z ∈ [+5.5, -5.5]` (Red at `+Z`, Blue at `-Z`).
final class BoardCoordinateMapper {
  const BoardCoordinateMapper({
    this.files = BoardCoord.fileCount,
    this.ranks = BoardCoord.rankCount,
    this.tileSize = 1.0,
  });

  final int files;
  final int ranks;
  final double tileSize;

  double get _halfFiles => (files - 1) * 0.5;
  double get _halfRanks => (ranks - 1) * 0.5;

  /// Converts a logical [BoardCoord] to a new 3D world-space [Vector3].
  Vector3 coordToWorld(BoardCoord coord, {double elevation = 0.0}) {
    return Vector3(
      (coord.file - _halfFiles) * tileSize,
      elevation,
      -(coord.rank - _halfRanks) * tileSize,
    );
  }

  /// Zero-allocation variant writing world coordinates into [out].
  void coordToWorldInto(
    BoardCoord coord,
    Vector3 out, {
    double elevation = 0.0,
  }) {
    out.setValues(
      (coord.file - _halfFiles) * tileSize,
      elevation,
      -(coord.rank - _halfRanks) * tileSize,
    );
  }

  /// Maps a world-space point on/near the board plane back to the nearest
  /// valid [BoardCoord] intersection, or `null` if outside the playable board.
  BoardCoord? worldToCoord(Vector3 worldPosition, {double pickMargin = 0.55}) {
    if (!worldPosition.x.isFinite ||
        !worldPosition.y.isFinite ||
        !worldPosition.z.isFinite ||
        !pickMargin.isFinite ||
        !tileSize.isFinite ||
        tileSize <= 0.0) {
      return null;
    }

    final halfWidth = _halfFiles * tileSize + pickMargin;
    final halfDepth = _halfRanks * tileSize + pickMargin;
    if (worldPosition.x < -halfWidth ||
        worldPosition.x > halfWidth ||
        worldPosition.z < -halfDepth ||
        worldPosition.z > halfDepth) {
      return null;
    }

    final file = (worldPosition.x / tileSize + _halfFiles).round();
    final rank = (-worldPosition.z / tileSize + _halfRanks).round();
    if (file < 0 || file >= files || rank < 0 || rank >= ranks) {
      return null;
    }
    return BoardCoord(file: file, rank: rank);
  }

  /// Generates default 11×12 [BoardTileSpec] metadata for standalone engine
  /// previews when caller does not supply tiles from the rules layer.
  List<BoardTileSpec> buildDefaultTiles() {
    final result = <BoardTileSpec>[];
    for (var rank = 0; rank < ranks; rank++) {
      for (var file = 0; file < files; file++) {
        final coord = BoardCoord(file: file, rank: rank);
        final isEstuary =
            (file == 3 || file == 4) && (rank == 5 || rank == 6);
        final TerrainType terrain;
        if (file <= 1) {
          terrain = TerrainType.deepSea;
        } else if (file == 2 || isEstuary) {
          terrain = TerrainType.mixed;
        } else {
          terrain = TerrainType.land;
        }
        final isBankRank = rank == 5 || rank == 6;
        result.add(
          BoardTileSpec(
            coord: coord,
            terrain: terrain,
            isEstuary: isEstuary,
            isRiverBorder: isBankRank && file >= 2,
            isFordAdjacent: isBankRank && (file == 5 || file == 7),
          ),
        );
      }
    }
    return List<BoardTileSpec>.unmodifiable(result);
  }
}

/// Engine-space render transform and animation state for a single board piece.
final class RenderPieceNode {
  RenderPieceNode({
    required this.pieceId,
    required this.visualKey,
    required this.worldPosition,
    required this.yawRadians,
    this.stackCount = 1,
    this.carriedVisualKeys = const <PieceVisualKey>[],
    this.isSelected = false,
    this.animClip = PieceAnimClip.idle,
    this.animProgress = 0.0,
    this.phaseSeed = 0.0,
    this.movePitchRadians = 0.0,
    this.moveRollRadians = 0.0,
  });

  final String pieceId;
  final PieceVisualKey visualKey;
  final Vector3 worldPosition;
  final double yawRadians;
  final int stackCount;
  final List<PieceVisualKey> carriedVisualKeys;
  final bool isSelected;
  final PieceAnimClip animClip;
  final double animProgress;
  final double phaseSeed;
  final double movePitchRadians;
  final double moveRollRadians;
}

/// Immutable per-frame scene snapshot consumed by [BoardSceneRenderer].
final class RenderBoardSnapshot {
  const RenderBoardSnapshot({
    this.ranks = BoardCoord.rankCount,
    this.files = BoardCoord.fileCount,
    this.tiles = const <BoardTileSpec>[],
    this.pieces = const <RenderPieceNode>[],
    this.legalHints = const <LegalActionHint>[],
    this.selectedCoord,
    this.elapsedSeconds = 0.0,
  });

  final int ranks;
  final int files;
  final List<BoardTileSpec> tiles;
  final List<RenderPieceNode> pieces;
  final List<LegalActionHint> legalHints;
  final BoardCoord? selectedCoord;
  final double elapsedSeconds;

  RenderBoardSnapshot copyWith({
    int? ranks,
    int? files,
    List<BoardTileSpec>? tiles,
    List<RenderPieceNode>? pieces,
    List<LegalActionHint>? legalHints,
    BoardCoord? selectedCoord,
    bool clearSelectedCoord = false,
    double? elapsedSeconds,
  }) {
    return RenderBoardSnapshot(
      ranks: ranks ?? this.ranks,
      files: files ?? this.files,
      tiles: tiles ?? this.tiles,
      pieces: pieces ?? this.pieces,
      legalHints: legalHints ?? this.legalHints,
      selectedCoord:
          clearSelectedCoord ? null : (selectedCoord ?? this.selectedCoord),
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    );
  }
}
