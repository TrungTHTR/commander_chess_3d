import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../models/action_model.dart';
import '../../models/board_coord.dart';
import '../animation/camera_rig_3d.dart';
import '../assets/piece_asset_provider.dart';
import '../loop/board_3d_scene_controller.dart';
import '../shaders/board_shader_handle.dart';
import '../world/board_3d_scene_state.dart';
import 'board_scene_renderer.dart';

/// CustomPainter bound directly to [Board3DSceneController] so 60/120Hz camera
/// orbits and piece animations repaint the canvas with zero widget rebuilds.
final class Board3DCustomPainter extends CustomPainter {
  Board3DCustomPainter({required this.controller}) : super(repaint: controller);

  final Board3DSceneController controller;

  @override
  void paint(Canvas canvas, Size size) {
    controller.render(canvas, size);
  }

  @override
  bool shouldRepaint(covariant Board3DCustomPainter oldDelegate) {
    return oldDelegate.controller != controller;
  }
}

/// Starter 3D software-projected renderer (`CustomPainter` + `vector_math_64` +
/// optional Impeller `FragmentShader`) implementing [BoardSceneRenderer].
///
/// Renders the 11×12 Cờ Tư Lệnh intersection board (deep sea `a,b`, coastal
/// mixed `c` + estuary `d6,e6,d7,e7`, inland `d..k`, river trench, and stone
/// ford bridges `f6-f7`, `h6-h7`), selection/legal-hint rings, and depth-sorted
/// extruded 3D piece meshes with directional key+fill shading.
final class Placeholder3DBoardRenderer implements BoardSceneRenderer {
  Placeholder3DBoardRenderer({
    required this.assetProvider,
    this.shaderHandle,
    this.mapper = const BoardCoordinateMapper(),
  });

  final PieceAssetProvider assetProvider;
  final BoardShaderHandle? shaderHandle;
  final BoardCoordinateMapper mapper;

  // Pre-allocated scratch math & drawing objects for low-GC 60/120Hz painting.
  final Matrix4 _vpMatrix = Matrix4.identity();
  final Vector3 _eyePos = Vector3.zero();
  final Vector4 _projVec = Vector4.zero();
  final Vector3 _keyLightDir = Vector3(-0.45, 0.82, 0.35)..normalize();
  final Vector3 _fillLightDir = Vector3(0.55, 0.42, -0.45)..normalize();

  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Path _quadPath = Path();
  final Path _ringPath = Path();

  // Dynamic grow-only flat buffers for projecting piece vertices and sorting faces.
  Float32List _projScreenX = Float32List(128);
  Float32List _projScreenY = Float32List(128);
  Float32List _projDepth = Float32List(128);
  Float32List _worldVertX = Float32List(128);
  Float32List _worldVertY = Float32List(128);
  Float32List _worldVertZ = Float32List(128);
  Int32List _visibleFaces = Int32List(128);
  Float32List _visibleFaceDepths = Float32List(128);
  final List<_SortablePieceRef> _sortedPieces = <_SortablePieceRef>[];

  bool _disposed = false;

  @override
  Future<void> initialize() async {
    _disposed = false;
  }

  @override
  BoardCoord? hitTestBoardCoord({
    required Offset localPosition,
    required Size viewportSize,
    required SpringOrbitCamera3D camera,
    required int files,
    required int ranks,
  }) {
    if (_disposed) return null;
    final worldPoint = camera.unprojectRayToGroundPlane(
      localPosition,
      viewportSize,
      planeY: 0.0,
    );
    if (worldPoint == null) return null;
    return mapper.worldToCoord(worldPoint);
  }

  @override
  void render(
    Canvas canvas,
    Size size,
    RenderBoardSnapshot snapshot,
    SpringOrbitCamera3D camera,
  ) {
    if (_disposed || size.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }

    camera.viewProjectionMatrixInto(size, _vpMatrix);
    camera.eyePositionInto(_eyePos);

    _drawBackground(canvas, size);
    _drawBoardBaseSlab(canvas, size);
    _drawTerrainTiles(canvas, size, snapshot);
    _drawRiverAndFords(canvas, size);
    _drawShaderWaterOverlay(canvas, size, snapshot);
    _drawIntersectionGrid(canvas, size, snapshot.files, snapshot.ranks);
    _drawSelectionAndHints(canvas, size, snapshot);
    _drawPieces(canvas, size, snapshot);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _fillPaint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0.0, size.height),
      const <Color>[Color(0xFF0C1520), Color(0xFF172638)],
    );
    canvas.drawRect(rect, _fillPaint);
    _fillPaint.shader = null;
  }

  void _drawBoardBaseSlab(Canvas canvas, Size size) {
    // Outer frame from [-5.9, -6.4] to [+5.9, +6.4], slab thickness [-0.40 .. -0.02].
    const x0 = -5.9;
    const x1 = 5.9;
    const z0 = -6.4;
    const z1 = 6.4;
    const yTop = -0.02;
    const yBot = -0.42;

    // Draw outer deck shadow on ground plane y = -0.42.
    _drawWorldQuad(
      canvas,
      size,
      x0 - 0.15, yBot, z1 + 0.15,
      x1 + 0.15, yBot, z1 + 0.15,
      x1 + 0.15, yBot, z0 - 0.15,
      x0 - 0.15, yBot, z0 - 0.15,
      const Color(0x66000000),
    );

    // Side skirts (only draw camera-facing sides via dot product with eye).
    if (_eyePos.z > z1) {
      _drawWorldQuad(
        canvas,
        size,
        x0, yBot, z1,
        x1, yBot, z1,
        x1, yTop, z1,
        x0, yTop, z1,
        const Color(0xFF3E3026),
      );
    }
    if (_eyePos.z < z0) {
      _drawWorldQuad(
        canvas,
        size,
        x1, yBot, z0,
        x0, yBot, z0,
        x0, yTop, z0,
        x1, yTop, z0,
        const Color(0xFF2D221B),
      );
    }
    if (_eyePos.x > x1) {
      _drawWorldQuad(
        canvas,
        size,
        x1, yBot, z1,
        x1, yBot, z0,
        x1, yTop, z0,
        x1, yTop, z1,
        const Color(0xFF352920),
      );
    }
    if (_eyePos.x < x0) {
      _drawWorldQuad(
        canvas,
        size,
        x0, yBot, z0,
        x0, yBot, z1,
        x0, yTop, z1,
        x0, yTop, z0,
        const Color(0xFF47372B),
      );
    }

    // Top wooden/tactical border deck.
    _drawWorldQuad(
      canvas,
      size,
      x0, yTop, z1,
      x1, yTop, z1,
      x1, yTop, z0,
      x0, yTop, z0,
      const Color(0xFF5A4332),
      strokeColor: const Color(0xFF7D5F47),
      strokeWidth: 1.0,
    );
  }

  void _drawTerrainTiles(
    Canvas canvas,
    Size size,
    RenderBoardSnapshot snapshot,
  ) {
    final tiles = snapshot.tiles;
    if (tiles.isEmpty) {
      // Fallback fill covering 11×12 terrain bands.
      _drawWorldQuad(
        canvas,
        size,
        -5.5, 0.0, 6.0,
        -3.5, 0.0, 6.0,
        -3.5, 0.0, -6.0,
        -5.5, 0.0, -6.0,
        const Color(0xFF164B7A),
      );
      _drawWorldQuad(
        canvas,
        size,
        -3.5, 0.0, 6.0,
        -2.5, 0.0, 6.0,
        -2.5, 0.0, -6.0,
        -3.5, 0.0, -6.0,
        const Color(0xFF3C7871),
      );
      _drawWorldQuad(
        canvas,
        size,
        -2.5, 0.0, 6.0,
        5.5, 0.0, 6.0,
        5.5, 0.0, -6.0,
        -2.5, 0.0, -6.0,
        const Color(0xFF606E4D),
      );
      return;
    }

    for (final tile in tiles) {
      final f = tile.coord.file;
      final r = tile.coord.rank;
      final cx = f - 5.0;
      final cz = -(r - 5.5);
      final isEven = ((f + r) & 1) == 0;

      final Color tileColor;
      switch (tile.terrain) {
        case TerrainType.deepSea:
          tileColor =
              isEven ? const Color(0xFF144775) : const Color(0xFF185082);
        case TerrainType.mixed:
          if (tile.isEstuary) {
            tileColor =
                isEven ? const Color(0xFF286C77) : const Color(0xFF2E7782);
          } else {
            tileColor =
                isEven ? const Color(0xFF3A756D) : const Color(0xFF438178);
          }
        case TerrainType.land:
          tileColor =
              isEven ? const Color(0xFF596846) : const Color(0xFF63734E);
      }

      _drawWorldQuad(
        canvas,
        size,
        cx - 0.5, 0.0, cz + 0.5,
        cx + 0.5, 0.0, cz + 0.5,
        cx + 0.5, 0.0, cz - 0.5,
        cx - 0.5, 0.0, cz - 0.5,
        tileColor,
      );
    }
  }

  void _drawRiverAndFords(Canvas canvas, Size size) {
    // River channel separating rank 6 (rankIdx 5, Z=+0.5) & rank 7 (rankIdx 6, Z=-0.5)
    // across coast file c (-3.0) through land file k (+5.5).
    _drawWorldQuad(
      canvas,
      size,
      -3.0, 0.002, 0.20,
      5.5, 0.002, 0.20,
      5.5, 0.002, -0.20,
      -3.0, 0.002, -0.20,
      const Color(0xFF1D6DA4),
      strokeColor: const Color(0xFF81D4FA),
      strokeWidth: 0.7,
    );

    // Two shallow stone ford bridges at f6-f7 (file 5 => X=0.0) and h6-h7 (file 7 => X=2.0).
    for (final fordX in const <double>[0.0, 2.0]) {
      _drawWorldQuad(
        canvas,
        size,
        fordX - 0.34, 0.006, 0.42,
        fordX + 0.34, 0.006, 0.42,
        fordX + 0.34, 0.006, -0.42,
        fordX - 0.34, 0.006, -0.42,
        const Color(0xFFBBA37B),
        strokeColor: const Color(0xFF5D4C36),
        strokeWidth: 1.1,
      );
    }
  }

  void _drawShaderWaterOverlay(
    Canvas canvas,
    Size size,
    RenderBoardSnapshot snapshot,
  ) {
    final handle = shaderHandle;
    if (handle == null || !handle.isReady) return;

    final shaderPaint = handle.updateAndBind(
      size: size,
      timeSeconds: snapshot.elapsedSeconds,
      baseColor: const Color(0x2829B6F6),
      accentColor: const Color(0x4A80DEEA),
    );
    if (shaderPaint == null) return;

    // Water shimmer over deep sea & coast strip (files a..c, X in [-5.5, -2.5]).
    if (_buildProjectedQuadPath(
      size,
      -5.5, 0.004, 6.0,
      -2.5, 0.004, 6.0,
      -2.5, 0.004, -6.0,
      -5.5, 0.004, -6.0,
    )) {
      canvas.drawPath(_quadPath, shaderPaint);
    }

    // Selection pulse accent quad if a coordinate is selected.
    final sel = snapshot.selectedCoord;
    if (sel != null) {
      final wx = sel.file - 5.0;
      final wz = -(sel.rank - 5.5);
      final selPaint = handle.updateAndBind(
        size: size,
        timeSeconds: snapshot.elapsedSeconds * 1.6,
        baseColor: const Color(0x38FFD54F),
        accentColor: const Color(0x60FFF59D),
      );
      if (selPaint != null &&
          _buildProjectedQuadPath(
            size,
            wx - 0.48, 0.012, wz + 0.48,
            wx + 0.48, 0.012, wz + 0.48,
            wx + 0.48, 0.012, wz - 0.48,
            wx - 0.48, 0.012, wz - 0.48,
          )) {
        canvas.drawPath(_quadPath, selPaint);
      }
    }
  }

  void _drawIntersectionGrid(
    Canvas canvas,
    Size size,
    int files,
    int ranks,
  ) {
    final minX = -((files - 1) * 0.5);
    final maxX = (files - 1) * 0.5;
    final minZ = -((ranks - 1) * 0.5);
    final maxZ = (ranks - 1) * 0.5;

    _strokePaint
      ..color = const Color(0x88E8F0E8)
      ..strokeWidth = 0.9;

    // 11 vertical file lines (pieces sit on intersections!).
    for (var f = 0; f < files; f++) {
      final wx = f - 5.0;
      final p0 = _projectPoint(size, wx, 0.004, minZ);
      final p1 = _projectPoint(size, wx, 0.004, maxZ);
      if (p0 != null && p1 != null) {
        if (f == 2) {
          // Emphasize coast boundary file `c`.
          _strokePaint
            ..color = const Color(0xCCA5D6A7)
            ..strokeWidth = 1.4;
          canvas.drawLine(p0, p1, _strokePaint);
          _strokePaint
            ..color = const Color(0x88E8F0E8)
            ..strokeWidth = 0.9;
        } else {
          canvas.drawLine(p0, p1, _strokePaint);
        }
      }
    }

    // 12 horizontal rank lines.
    for (var r = 0; r < ranks; r++) {
      final wz = -(r - 5.5);
      final p0 = _projectPoint(size, minX, 0.004, wz);
      final p1 = _projectPoint(size, maxX, 0.004, wz);
      if (p0 != null && p1 != null) {
        canvas.drawLine(p0, p1, _strokePaint);
      }
    }

    // Crisp intersection node markers.
    _fillPaint.color = const Color(0xAAFFFFFF);
    for (var r = 0; r < ranks; r++) {
      final wz = -(r - 5.5);
      for (var f = 0; f < files; f++) {
        final wx = f - 5.0;
        final pt = _projectPoint(size, wx, 0.005, wz);
        if (pt != null) {
          canvas.drawCircle(pt, 1.8, _fillPaint);
        }
      }
    }
  }

  void _drawSelectionAndHints(
    Canvas canvas,
    Size size,
    RenderBoardSnapshot snapshot,
  ) {
    final pulse = 0.88 + 0.12 * math.sin(snapshot.elapsedSeconds * 5.0);

    final selected = snapshot.selectedCoord;
    if (selected != null) {
      final wx = selected.file - 5.0;
      final wz = -(selected.rank - 5.5);
      _drawWorldRing(
        canvas,
        size,
        wx,
        0.015,
        wz,
        0.44 * pulse,
        const Color(0xFFFFD54F),
        strokeWidth: 2.6,
        fillColor: const Color(0x33FFD54F),
      );
    }

    for (final hint in snapshot.legalHints) {
      final wx = hint.targetCoord.file - 5.0;
      final wz = -(hint.targetCoord.rank - 5.5);
      switch (hint.kind) {
        case ActionKind.move:
          _drawWorldRing(
            canvas,
            size,
            wx,
            0.014,
            wz,
            0.34 * pulse,
            const Color(0xFF4CAF50),
            strokeWidth: 2.2,
            fillColor: const Color(0x444CAF50),
          );
        case ActionKind.capture:
          _drawWorldRing(
            canvas,
            size,
            wx,
            0.014,
            wz,
            0.40 * pulse,
            const Color(0xFFEF5350),
            strokeWidth: 2.6,
            fillColor: const Color(0x44EF5350),
          );
        case ActionKind.stayCapture:
          _drawWorldRing(
            canvas,
            size,
            wx,
            0.014,
            wz,
            0.38 * pulse,
            const Color(0xFFFFB300),
            strokeWidth: 2.5,
            fillColor: const Color(0x44FFB300),
          );
        case ActionKind.embark:
        case ActionKind.disembark:
          _drawWorldRing(
            canvas,
            size,
            wx,
            0.014,
            wz,
            0.36 * pulse,
            const Color(0xFF29B6F6),
            strokeWidth: 2.2,
            fillColor: const Color(0x4429B6F6),
          );
      }
    }
  }

  void _drawPieces(
    Canvas canvas,
    Size size,
    RenderBoardSnapshot snapshot,
  ) {
    if (snapshot.pieces.isEmpty) return;

    _sortedPieces.clear();
    for (final node in snapshot.pieces) {
      final dx = node.worldPosition.x - _eyePos.x;
      final dy = node.worldPosition.y - _eyePos.y;
      final dz = node.worldPosition.z - _eyePos.z;
      _sortedPieces.add(
        _SortablePieceRef(node: node, distSq: dx * dx + dy * dy + dz * dz),
      );
    }

    // Painter's sort: farthest piece drawn first, nearest drawn last.
    _sortedPieces.sort((a, b) => b.distSq.compareTo(a.distSq));

    for (final item in _sortedPieces) {
      final node = item.node;

      // Ground contact shadow at y = 0.006.
      _drawWorldRing(
        canvas,
        size,
        node.worldPosition.x,
        0.007,
        node.worldPosition.z,
        0.38,
        const Color(0x00000000),
        strokeWidth: 0.0,
        fillColor: const Color(0x55000000),
      );

      // Heroic gold aura ring.
      if (node.visualKey.isHero) {
        final auraPulse = 0.42 + 0.04 * math.sin(snapshot.elapsedSeconds * 4.0);
        _drawWorldRing(
          canvas,
          size,
          node.worldPosition.x,
          0.013,
          node.worldPosition.z,
          auraPulse,
          const Color(0xFFFFD54F),
          strokeWidth: 2.2,
          fillColor: const Color(0x28FFD54F),
        );
      }

      final handle = assetProvider.resolvePiece(node.visualKey);
      if (handle is ProceduralPieceVisualHandle) {
        _drawProceduralPiece(canvas, size, node, handle);
      }

      // Stack / carried passenger badge pips above piece pedestal.
      if (node.stackCount > 1) {
        final pipCenter = _projectPoint(
          size,
          node.worldPosition.x + 0.28,
          node.worldPosition.y + 0.88,
          node.worldPosition.z,
        );
        if (pipCenter != null) {
          _fillPaint.color = const Color(0xFFFFD54F);
          canvas.drawCircle(pipCenter, 4.5, _fillPaint);
          _strokePaint
            ..color = const Color(0xFF1A1A1A)
            ..strokeWidth = 1.2;
          canvas.drawCircle(pipCenter, 4.5, _strokePaint);
        }
      }
    }
  }

  void _drawProceduralPiece(
    Canvas canvas,
    Size size,
    RenderPieceNode node,
    ProceduralPieceVisualHandle handle,
  ) {
    final mesh = handle.mesh;
    final vertCount = mesh.vertices.length ~/ 3;
    final faceCount = mesh.faceCount;
    if (vertCount == 0 || faceCount == 0) return;

    _ensureCapacity(vertCount, faceCount);

    final cosYaw = math.cos(node.yawRadians);
    final sinYaw = math.sin(node.yawRadians);
    final scale = node.isSelected ? 1.07 : 1.0;
    final wxBase = node.worldPosition.x;
    final wyBase = node.worldPosition.y;
    final wzBase = node.worldPosition.z;

    final verts = mesh.vertices;
    final halfW = size.width * 0.5;
    final halfH = size.height * 0.5;
    final m = _vpMatrix.storage;

    for (var i = 0; i < vertCount; i++) {
      final lx = verts[i * 3] * scale;
      final ly = verts[i * 3 + 1] * scale;
      final lz = verts[i * 3 + 2] * scale;

      // Rotate around +Y by yawRadians (standard right-handed Y rotation).
      final rx = lx * cosYaw + lz * sinYaw;
      final rz = -lx * sinYaw + lz * cosYaw;

      final wx = wxBase + rx;
      final wy = wyBase + ly;
      final wz = wzBase + rz;

      _worldVertX[i] = wx;
      _worldVertY[i] = wy;
      _worldVertZ[i] = wz;

      // Inline Matrix4 * (wx, wy, wz, 1.0) without allocating Vector4.
      final cx = m[0] * wx + m[4] * wy + m[8] * wz + m[12];
      final cy = m[1] * wx + m[5] * wy + m[9] * wz + m[13];
      final cz = m[2] * wx + m[6] * wy + m[10] * wz + m[14];
      final cw = m[3] * wx + m[7] * wy + m[11] * wz + m[15];

      final safeW = cw.abs() < 1e-5 ? (cw < 0 ? -1e-5 : 1e-5) : cw;
      final invW = 1.0 / safeW;
      _projScreenX[i] = halfW + (cx * invW) * halfW;
      _projScreenY[i] = halfH - (cy * invW) * halfH;
      _projDepth[i] = cz * invW;
    }

    final indices = mesh.faceIndices;
    final normals = mesh.faceNormals;
    var visibleCount = 0;

    for (var f = 0; f < faceCount; f++) {
      final base = f * 4;
      final i0 = indices[base];
      final i1 = indices[base + 1];
      final i2 = indices[base + 2];
      final i3 = indices[base + 3];

      // Rotate local normal by piece yaw.
      final lnx = normals[f * 3];
      final lny = normals[f * 3 + 1];
      final lnz = normals[f * 3 + 2];
      final wnx = lnx * cosYaw + lnz * sinYaw;
      final wny = lny;
      final wnz = -lnx * sinYaw + lnz * cosYaw;

      // Face center in world space for world-space backface culling.
      final fcx =
          (_worldVertX[i0] + _worldVertX[i1] + _worldVertX[i2] + _worldVertX[i3]) *
              0.25;
      final fcy =
          (_worldVertY[i0] + _worldVertY[i1] + _worldVertY[i2] + _worldVertY[i3]) *
              0.25;
      final fcz =
          (_worldVertZ[i0] + _worldVertZ[i1] + _worldVertZ[i2] + _worldVertZ[i3]) *
              0.25;

      final vx = _eyePos.x - fcx;
      final vy = _eyePos.y - fcy;
      final vz = _eyePos.z - fcz;
      if (wnx * vx + wny * vy + wnz * vz <= 0.0) {
        continue;
      }

      _visibleFaces[visibleCount] = f;
      _visibleFaceDepths[visibleCount] =
          (_projDepth[i0] + _projDepth[i1] + _projDepth[i2] + _projDepth[i3]) *
              0.25;
      visibleCount++;
    }

    // Insertion sort visible faces back-to-front (painter's order).
    for (var i = 1; i < visibleCount; i++) {
      final keyFace = _visibleFaces[i];
      final keyDepth = _visibleFaceDepths[i];
      var j = i - 1;
      while (j >= 0 && _visibleFaceDepths[j] < keyDepth) {
        _visibleFaces[j + 1] = _visibleFaces[j];
        _visibleFaceDepths[j + 1] = _visibleFaceDepths[j];
        j--;
      }
      _visibleFaces[j + 1] = keyFace;
      _visibleFaceDepths[j + 1] = keyDepth;
    }

    final faceSlots = mesh.faceSlots;
    _strokePaint.strokeWidth = 0.65;

    for (var v = 0; v < visibleCount; v++) {
      final f = _visibleFaces[v];
      final base = f * 4;
      final i0 = indices[base];
      final i1 = indices[base + 1];
      final i2 = indices[base + 2];
      final i3 = indices[base + 3];

      final lnx = normals[f * 3];
      final lny = normals[f * 3 + 1];
      final lnz = normals[f * 3 + 2];
      final wnx = lnx * cosYaw + lnz * sinYaw;
      final wny = lny;
      final wnz = -lnx * sinYaw + lnz * cosYaw;

      final keyDot = math.max(
        0.0,
        wnx * _keyLightDir.x + wny * _keyLightDir.y + wnz * _keyLightDir.z,
      );
      final fillDot = math.max(
        0.0,
        wnx * _fillLightDir.x + wny * _fillLightDir.y + wnz * _fillLightDir.z,
      );
      final isHeroicGlow =
          node.visualKey.isHero &&
          faceSlots[f] == ProceduralMaterialSlot.heroicEmissive.index;
      final brightness = isHeroicGlow
          ? 1.15
          : (0.48 + 0.56 * keyDot + 0.18 * fillDot).clamp(0.35, 1.15);

      final baseColor = handle.colorForSlot(faceSlots[f]);
      final shaded = _shadeColor(baseColor, brightness);

      _quadPath
        ..reset()
        ..moveTo(_projScreenX[i0], _projScreenY[i0])
        ..lineTo(_projScreenX[i1], _projScreenY[i1])
        ..lineTo(_projScreenX[i2], _projScreenY[i2]);
      if (i3 != i2) {
        _quadPath.lineTo(_projScreenX[i3], _projScreenY[i3]);
      }
      _quadPath.close();

      _fillPaint.color = shaded;
      canvas.drawPath(_quadPath, _fillPaint);

      _strokePaint.color = _shadeColor(baseColor, brightness * 0.62);
      canvas.drawPath(_quadPath, _strokePaint);
    }
  }

  void _ensureCapacity(int vertCount, int faceCount) {
    if (vertCount > _projScreenX.length) {
      final cap = vertCount * 2;
      _projScreenX = Float32List(cap);
      _projScreenY = Float32List(cap);
      _projDepth = Float32List(cap);
      _worldVertX = Float32List(cap);
      _worldVertY = Float32List(cap);
      _worldVertZ = Float32List(cap);
    }
    if (faceCount > _visibleFaces.length) {
      final cap = faceCount * 2;
      _visibleFaces = Int32List(cap);
      _visibleFaceDepths = Float32List(cap);
    }
  }

  Offset? _projectPoint(Size size, double wx, double wy, double wz) {
    _projVec.setValues(wx, wy, wz, 1.0);
    _vpMatrix.transform(_projVec);
    if (_projVec.w <= 1e-4) return null;
    final invW = 1.0 / _projVec.w;
    final ndcX = _projVec.x * invW;
    final ndcY = _projVec.y * invW;
    return Offset(
      (ndcX * 0.5 + 0.5) * size.width,
      (0.5 - ndcY * 0.5) * size.height,
    );
  }

  bool _buildProjectedQuadPath(
    Size size,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    double x2,
    double y2,
    double z2,
    double x3,
    double y3,
    double z3,
  ) {
    final p0 = _projectPoint(size, x0, y0, z0);
    final p1 = _projectPoint(size, x1, y1, z1);
    final p2 = _projectPoint(size, x2, y2, z2);
    final p3 = _projectPoint(size, x3, y3, z3);
    if (p0 == null || p1 == null || p2 == null || p3 == null) {
      return false;
    }
    _quadPath
      ..reset()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    return true;
  }

  void _drawWorldQuad(
    Canvas canvas,
    Size size,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    double x2,
    double y2,
    double z2,
    double x3,
    double y3,
    double z3,
    Color fillColor, {
    Color? strokeColor,
    double strokeWidth = 0.0,
  }) {
    if (!_buildProjectedQuadPath(
      size,
      x0, y0, z0,
      x1, y1, z1,
      x2, y2, z2,
      x3, y3, z3,
    )) {
      return;
    }
    _fillPaint.color = fillColor;
    canvas.drawPath(_quadPath, _fillPaint);
    if (strokeColor != null && strokeWidth > 0.0) {
      _strokePaint
        ..color = strokeColor
        ..strokeWidth = strokeWidth;
      canvas.drawPath(_quadPath, _strokePaint);
    }
  }

  void _drawWorldRing(
    Canvas canvas,
    Size size,
    double cx,
    double cy,
    double cz,
    double radius,
    Color strokeColor, {
    double strokeWidth = 2.0,
    Color? fillColor,
  }) {
    const segments = 16;
    _ringPath.reset();
    var started = false;
    for (var i = 0; i < segments; i++) {
      final angle = i * (2.0 * math.pi / segments);
      final pt = _projectPoint(
        size,
        cx + math.cos(angle) * radius,
        cy,
        cz + math.sin(angle) * radius,
      );
      if (pt == null) return;
      if (!started) {
        _ringPath.moveTo(pt.dx, pt.dy);
        started = true;
      } else {
        _ringPath.lineTo(pt.dx, pt.dy);
      }
    }
    _ringPath.close();

    if (fillColor != null) {
      _fillPaint.color = fillColor;
      canvas.drawPath(_ringPath, _fillPaint);
    }
    if (strokeWidth > 0.0 && strokeColor.a > 0.0) {
      _strokePaint
        ..color = strokeColor
        ..strokeWidth = strokeWidth;
      canvas.drawPath(_ringPath, _strokePaint);
    }
  }

  static Color _shadeColor(Color c, double factor) {
    final r = (c.r * factor).clamp(0.0, 1.0);
    final g = (c.g * factor).clamp(0.0, 1.0);
    final b = (c.b * factor).clamp(0.0, 1.0);
    return Color.from(alpha: c.a, red: r, green: g, blue: b);
  }

  @override
  void dispose() {
    _disposed = true;
    _sortedPieces.clear();
  }
}

final class _SortablePieceRef {
  _SortablePieceRef({required this.node, required this.distSq});
  final RenderPieceNode node;
  final double distSq;
}
