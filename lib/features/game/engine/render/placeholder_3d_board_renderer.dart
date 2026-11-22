import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../models/action_model.dart';
import '../../models/asset_manifest_model.dart';
import '../../models/board_coord.dart';
import '../../models/piece_model.dart';
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

  static const int _maxVerticesPerBatch = 65000; // < 65535 Uint16 limit
  static final Expando<_MeshEdgeTopology> _edgeTopologyCache =
      Expando<_MeshEdgeTopology>('meshEdgeTopology');

  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _vertexPaint = Paint();
  final Path _quadPath = Path();
  final Path _ringPath = Path();

  // Pre-allocated batched drawVertices buffers (zero per-frame heap allocs).
  Float32List _batchPositions = Float32List(16384 * 2);
  Int32List _batchColors = Int32List(16384);
  Uint16List _batchIndices = Uint16List(24576);
  int _batchVertCount = 0;
  int _batchIndexCount = 0;
  int _lastDrawVerticesCallCount = 0;

  // Dynamic grow-only flat buffers for projecting unit (carrier + passengers).
  Float32List _unitScreenX = Float32List(1536);
  Float32List _unitScreenY = Float32List(1536);
  Float32List _unitDepth = Float32List(1536);
  Uint8List _unitValid = Uint8List(1536);
  Float32List _unitWorldX = Float32List(1536);
  Float32List _unitWorldY = Float32List(1536);
  Float32List _unitWorldZ = Float32List(1536);

  Int32List _unitFaceV0 = Int32List(1536);
  Int32List _unitFaceV1 = Int32List(1536);
  Int32List _unitFaceV2 = Int32List(1536);
  Int32List _unitFaceV3 = Int32List(1536);
  Int32List _unitFaceArgb = Int32List(1536);
  Uint8List _unitFaceVisible = Uint8List(1536);
  Int32List _visibleOrder = Int32List(1536);
  Float32List _visibleDepths = Float32List(1536);
  final List<_SortablePieceRef> _sortedPieces = <_SortablePieceRef>[];

  // Per-unit animation pose scratch scalars (zero allocations).
  double _bodyPitch = 0.0;
  double _bodyRoll = 0.0;
  double _bodyLiftY = 0.0;
  double _bodyScale = 1.0;
  double _turretYaw = 0.0;
  double _barrelPitch = 0.0;
  double _barrelRecoilZ = 0.0;
  double _wingRotorYaw = 0.0;
  double _wingRotorRoll = 0.0;
  double _insigniaYaw = 0.0;
  double _insigniaLiftY = 0.0;
  double _insigniaScale = 1.0;

  bool _disposed = false;

  @visibleForTesting
  int get debugLastDrawVerticesCallCount => _lastDrawVerticesCallCount;

  @visibleForTesting
  static List<({int v0, int v1, int faceA, int faceB, bool isCrease})>
  debugExtractEdges(ProceduralMeshPrimitive mesh) {
    final topo = _getEdgeTopology(mesh);
    return List<({int v0, int v1, int faceA, int faceB, bool isCrease})>.generate(
      topo.edgeCount,
      (i) => (
        v0: topo.edgeV0[i],
        v1: topo.edgeV1[i],
        faceA: topo.edgeFaceA[i],
        faceB: topo.edgeFaceB[i],
        isCrease: topo.edgeIsCrease[i] == 1,
      ),
      growable: false,
    );
  }

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

    final safeElapsed =
        snapshot.elapsedSeconds.isFinite ? snapshot.elapsedSeconds : 0.0;

    camera.viewProjectionMatrixInto(size, _vpMatrix);
    camera.eyePositionInto(_eyePos);

    _drawBackground(canvas, size);
    _drawBoardBaseSlab(canvas, size);
    _drawTerrainTiles(canvas, size, snapshot);
    _drawRiverAndFords(canvas, size);
    _drawShaderWaterOverlay(canvas, size, snapshot, safeElapsed);
    _drawIntersectionGrid(canvas, size, snapshot.files, snapshot.ranks);
    _drawSelectionAndHints(canvas, size, snapshot, safeElapsed);
    _drawPieces(canvas, size, snapshot, safeElapsed);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _fillPaint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
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
    double elapsedSeconds,
  ) {
    final handle = shaderHandle;
    if (handle == null || !handle.isReady) return;

    final shaderPaint = handle.updateAndBind(
      size: size,
      timeSeconds: elapsedSeconds,
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
      final selTime = elapsedSeconds * 1.6;
      final selPaint = handle.updateAndBind(
        size: size,
        timeSeconds: selTime.isFinite ? selTime : elapsedSeconds,
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
    double elapsedSeconds,
  ) {
    final rawSin = math.sin(elapsedSeconds * 5.0);
    final pulse = 0.88 + 0.12 * (rawSin.isFinite ? rawSin : 0.0);

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
    double elapsedSeconds,
  ) {
    if (snapshot.pieces.isEmpty) {
      _lastDrawVerticesCallCount = 0;
      return;
    }

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

    // Pass 1: Ground contact shadows and heroic aura rings underneath all meshes.
    for (final item in _sortedPieces) {
      final node = item.node;
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

      if (node.visualKey.isHero) {
        final rawAuraSin = math.sin(elapsedSeconds * 4.0);
        final auraPulse =
            0.42 + 0.04 * (rawAuraSin.isFinite ? rawAuraSin : 0.0);
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
    }

    // Pass 2: Batched Canvas.drawVertices over carrier + socket passengers + creases.
    _batchVertCount = 0;
    _batchIndexCount = 0;
    _lastDrawVerticesCallCount = 0;

    for (final item in _sortedPieces) {
      final node = item.node;
      final handle = assetProvider.resolvePiece(node.visualKey);
      if (handle is ProceduralPieceVisualHandle) {
        _batchUnitWithPassengers(canvas, size, node, handle, elapsedSeconds);
      }
    }

    _flushBatch(canvas);

    // Pass 3: Fallback stack pip when stackCount > 1 lacks passenger keys.
    for (final item in _sortedPieces) {
      final node = item.node;
      final renderedPassengers = math.min(node.carriedVisualKeys.length, 2);
      if (node.stackCount > 1 &&
          (renderedPassengers == 0 || node.stackCount > 1 + renderedPassengers)) {
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

  void _batchUnitWithPassengers(
    Canvas canvas,
    Size size,
    RenderPieceNode node,
    ProceduralPieceVisualHandle carrierHandle,
    double elapsedSeconds,
  ) {
    final carrierMesh = carrierHandle.mesh;
    final carrierVerts = carrierMesh.vertices.length ~/ 3;
    final carrierFaces = carrierMesh.faceCount;
    if (carrierVerts == 0 || carrierFaces == 0) return;

    final passengerCount = math.min(node.carriedVisualKeys.length, 2);
    var totalVerts = carrierVerts;
    var totalFaces = carrierFaces;
    ProceduralPieceVisualHandle? p0Handle;
    ProceduralPieceVisualHandle? p1Handle;

    if (passengerCount >= 1) {
      final rawKey = node.carriedVisualKeys[0];
      final resolvedKey = rawKey.faction != null
          ? rawKey
          : rawKey.copyWith(faction: node.visualKey.faction);
      final h = assetProvider.resolvePiece(resolvedKey);
      if (h is ProceduralPieceVisualHandle &&
          h.mesh.faceCount > 0 &&
          h.mesh.vertices.isNotEmpty) {
        p0Handle = h;
        totalVerts += h.mesh.vertices.length ~/ 3;
        totalFaces += h.mesh.faceCount;
      }
    }
    if (passengerCount >= 2) {
      final rawKey = node.carriedVisualKeys[1];
      final resolvedKey = rawKey.faction != null
          ? rawKey
          : rawKey.copyWith(faction: node.visualKey.faction);
      final h = assetProvider.resolvePiece(resolvedKey);
      if (h is ProceduralPieceVisualHandle &&
          h.mesh.faceCount > 0 &&
          h.mesh.vertices.isNotEmpty) {
        p1Handle = h;
        totalVerts += h.mesh.vertices.length ~/ 3;
        totalFaces += h.mesh.faceCount;
      }
    }

    _ensureUnitCapacity(totalVerts, totalFaces);
    _computeAnimPose(node, elapsedSeconds);

    final cosYaw = math.cos(node.yawRadians);
    final sinYaw = math.sin(node.yawRadians);
    final selectedScale = node.isSelected ? 1.07 : 1.0;

    var visibleCount = 0;
    final carrierTopo = _getEdgeTopology(carrierMesh);

    final carrierResult = _projectSubMesh(
      mesh: carrierMesh,
      topology: carrierTopo,
      handle: carrierHandle,
      isHero: node.visualKey.isHero,
      vertOffset: 0,
      faceOffset: 0,
      visibleStart: visibleCount,
      cosYaw: cosYaw,
      sinYaw: sinYaw,
      selectedScale: selectedScale,
      worldOrigin: node.worldPosition,
      size: size,
      elapsedSeconds: elapsedSeconds,
      applySubPartAnim: true,
      localSubScale: 1.0,
      socketOffset: null,
    );
    visibleCount = carrierResult.visibleEnd;
    final pieceScreenH = carrierResult.screenHeight;

    var nextVertOffset = carrierVerts;
    var nextFaceOffset = carrierFaces;
    _MeshEdgeTopology? p0Topo;
    var p0VertOffset = 0;
    var p0FaceOffset = 0;
    _MeshEdgeTopology? p1Topo;
    var p1VertOffset = 0;
    var p1FaceOffset = 0;

    if (p0Handle != null) {
      p0Topo = _getEdgeTopology(p0Handle.mesh);
      p0VertOffset = nextVertOffset;
      p0FaceOffset = nextFaceOffset;
      final sock0 = carrierMesh.passengerSockets.isNotEmpty
          ? carrierMesh.passengerSockets[0]
          : _fallbackSocket(node.visualKey.type, 0);
      final res0 = _projectSubMesh(
        mesh: p0Handle.mesh,
        topology: p0Topo,
        handle: p0Handle,
        isHero: p0Handle.visualKey.isHero,
        vertOffset: p0VertOffset,
        faceOffset: p0FaceOffset,
        visibleStart: visibleCount,
        cosYaw: cosYaw,
        sinYaw: sinYaw,
        selectedScale: selectedScale,
        worldOrigin: node.worldPosition,
        size: size,
        elapsedSeconds: elapsedSeconds,
        applySubPartAnim: false,
        localSubScale: 0.42,
        socketOffset: sock0,
      );
      visibleCount = res0.visibleEnd;
      nextVertOffset += p0Handle.mesh.vertices.length ~/ 3;
      nextFaceOffset += p0Handle.mesh.faceCount;
    }

    if (p1Handle != null) {
      p1Topo = _getEdgeTopology(p1Handle.mesh);
      p1VertOffset = nextVertOffset;
      p1FaceOffset = nextFaceOffset;
      final sock1 = carrierMesh.passengerSockets.length >= 2
          ? carrierMesh.passengerSockets[1]
          : _fallbackSocket(node.visualKey.type, 1);
      final res1 = _projectSubMesh(
        mesh: p1Handle.mesh,
        topology: p1Topo,
        handle: p1Handle,
        isHero: p1Handle.visualKey.isHero,
        vertOffset: p1VertOffset,
        faceOffset: p1FaceOffset,
        visibleStart: visibleCount,
        cosYaw: cosYaw,
        sinYaw: sinYaw,
        selectedScale: selectedScale,
        worldOrigin: node.worldPosition,
        size: size,
        elapsedSeconds: elapsedSeconds,
        applySubPartAnim: false,
        localSubScale: 0.42,
        socketOffset: sock1,
      );
      visibleCount = res1.visibleEnd;
    }

    // Painter's sort all visible faces of (carrier + passengers) together.
    for (var i = 1; i < visibleCount; i++) {
      final keyFace = _visibleOrder[i];
      final keyDepth = _visibleDepths[i];
      var j = i - 1;
      while (j >= 0 && _visibleDepths[j] < keyDepth) {
        _visibleOrder[j + 1] = _visibleOrder[j];
        _visibleDepths[j + 1] = _visibleDepths[j];
        j--;
      }
      _visibleOrder[j + 1] = keyFace;
      _visibleDepths[j + 1] = keyDepth;
    }

    // Append sorted flat-shaded triangles/quads into global drawVertices batch.
    for (var v = 0; v < visibleCount; v++) {
      final f = _visibleOrder[v];
      final i0 = _unitFaceV0[f];
      final i1 = _unitFaceV1[f];
      final i2 = _unitFaceV2[f];
      final i3 = _unitFaceV3[f];
      final argb = _unitFaceArgb[f];

      if (i3 == i2) {
        _ensureBatchCapacity(canvas, 3, 3);
        final vb = _batchVertCount;
        final pb = vb * 2;
        _batchPositions[pb] = _unitScreenX[i0];
        _batchPositions[pb + 1] = _unitScreenY[i0];
        _batchPositions[pb + 2] = _unitScreenX[i1];
        _batchPositions[pb + 3] = _unitScreenY[i1];
        _batchPositions[pb + 4] = _unitScreenX[i2];
        _batchPositions[pb + 5] = _unitScreenY[i2];

        _batchColors[vb] = argb;
        _batchColors[vb + 1] = argb;
        _batchColors[vb + 2] = argb;

        final ib = _batchIndexCount;
        _batchIndices[ib] = vb;
        _batchIndices[ib + 1] = vb + 1;
        _batchIndices[ib + 2] = vb + 2;

        _batchVertCount += 3;
        _batchIndexCount += 3;
      } else {
        _ensureBatchCapacity(canvas, 4, 6);
        final vb = _batchVertCount;
        final pb = vb * 2;
        _batchPositions[pb] = _unitScreenX[i0];
        _batchPositions[pb + 1] = _unitScreenY[i0];
        _batchPositions[pb + 2] = _unitScreenX[i1];
        _batchPositions[pb + 3] = _unitScreenY[i1];
        _batchPositions[pb + 4] = _unitScreenX[i2];
        _batchPositions[pb + 5] = _unitScreenY[i2];
        _batchPositions[pb + 6] = _unitScreenX[i3];
        _batchPositions[pb + 7] = _unitScreenY[i3];

        _batchColors[vb] = argb;
        _batchColors[vb + 1] = argb;
        _batchColors[vb + 2] = argb;
        _batchColors[vb + 3] = argb;

        final ib = _batchIndexCount;
        _batchIndices[ib] = vb;
        _batchIndices[ib + 1] = vb + 1;
        _batchIndices[ib + 2] = vb + 2;
        _batchIndices[ib + 3] = vb;
        _batchIndices[ib + 4] = vb + 2;
        _batchIndices[ib + 5] = vb + 3;

        _batchVertCount += 4;
        _batchIndexCount += 6;
      }
    }

    // Append selective silhouette & hard-crease quads for carrier and passengers.
    _emitSelectiveEdges(
      canvas: canvas,
      topology: carrierTopo,
      vertOffset: 0,
      faceOffset: 0,
      pieceScreenH: pieceScreenH,
    );
    if (p0Topo != null && pieceScreenH >= 20.0) {
      _emitSelectiveEdges(
        canvas: canvas,
        topology: p0Topo,
        vertOffset: p0VertOffset,
        faceOffset: p0FaceOffset,
        pieceScreenH: pieceScreenH * 0.45,
      );
    }
    if (p1Topo != null && pieceScreenH >= 20.0) {
      _emitSelectiveEdges(
        canvas: canvas,
        topology: p1Topo,
        vertOffset: p1VertOffset,
        faceOffset: p1FaceOffset,
        pieceScreenH: pieceScreenH * 0.45,
      );
    }
  }

  ({int visibleEnd, double screenHeight}) _projectSubMesh({
    required ProceduralMeshPrimitive mesh,
    required _MeshEdgeTopology topology,
    required ProceduralPieceVisualHandle handle,
    required bool isHero,
    required int vertOffset,
    required int faceOffset,
    required int visibleStart,
    required double cosYaw,
    required double sinYaw,
    required double selectedScale,
    required Vector3 worldOrigin,
    required Size size,
    required double elapsedSeconds,
    required bool applySubPartAnim,
    required double localSubScale,
    required Vector3? socketOffset,
  }) {
    final vertCount = mesh.vertices.length ~/ 3;
    final faceCount = mesh.faceCount;
    final verts = mesh.vertices;
    final halfW = size.width * 0.5;
    final halfH = size.height * 0.5;
    final m = _vpMatrix.storage;

    final cosBodyPitch = math.cos(_bodyPitch);
    final sinBodyPitch = math.sin(_bodyPitch);
    final cosBodyRoll = math.cos(_bodyRoll);
    final sinBodyRoll = math.sin(_bodyRoll);

    final turretPivot = mesh.partPivots[MeshPartTag.turret];
    final barrelPivot = mesh.partPivots[MeshPartTag.barrel];
    final wingPivot = mesh.partPivots[MeshPartTag.wingRotor];
    final insigniaPivot = mesh.partPivots[MeshPartTag.insigniaStar];

    var minSY = double.infinity;
    var maxSY = double.negativeInfinity;

    for (var i = 0; i < vertCount; i++) {
      var lx = verts[i * 3] * localSubScale;
      var ly = verts[i * 3 + 1] * localSubScale;
      var lz = verts[i * 3 + 2] * localSubScale;

      if (socketOffset != null) {
        lx += socketOffset.x;
        ly += socketOffset.y;
        lz += socketOffset.z;
      }

      final partIdx = topology.vertexPartTags[i];
      final isPedestal = applySubPartAnim && partIdx == MeshPartTag.basePedestal.index;

      if (applySubPartAnim && !isPedestal) {
        if (partIdx == MeshPartTag.turret.index) {
          if (_turretYaw != 0.0) {
            final px = turretPivot?.x ?? 0.0;
            final pz = turretPivot?.z ?? 0.0;
            final dx = lx - px;
            final dz = lz - pz;
            final cy = math.cos(_turretYaw);
            final sy = math.sin(_turretYaw);
            lx = px + dx * cy + dz * sy;
            lz = pz - dx * sy + dz * cy;
          }
        } else if (partIdx == MeshPartTag.barrel.index) {
          if (_barrelRecoilZ != 0.0) {
            lz += _barrelRecoilZ;
          }
          if (_barrelPitch != 0.0) {
            final py = barrelPivot?.y ?? 0.38;
            final pz = barrelPivot?.z ?? 0.0;
            final dy = ly - py;
            final dz = lz - pz;
            final cp = math.cos(_barrelPitch);
            final sp = math.sin(_barrelPitch);
            ly = py + dy * cp - dz * sp;
            lz = pz + dy * sp + dz * cp;
          }
          if (_turretYaw != 0.0) {
            final px = turretPivot?.x ?? 0.0;
            final pz = turretPivot?.z ?? 0.0;
            final dx = lx - px;
            final dz = lz - pz;
            final cy = math.cos(_turretYaw);
            final sy = math.sin(_turretYaw);
            lx = px + dx * cy + dz * sy;
            lz = pz - dx * sy + dz * cy;
          }
        } else if (partIdx == MeshPartTag.wingRotor.index) {
          if (_wingRotorRoll != 0.0) {
            final px = wingPivot?.x ?? 0.0;
            final py = wingPivot?.y ?? 0.58;
            final dx = lx - px;
            final dy = ly - py;
            final cr = math.cos(_wingRotorRoll);
            final sr = math.sin(_wingRotorRoll);
            lx = px + dx * cr - dy * sr;
            ly = py + dx * sr + dy * cr;
          }
          if (_wingRotorYaw != 0.0) {
            final px = wingPivot?.x ?? 0.0;
            final pz = wingPivot?.z ?? 0.0;
            final dx = lx - px;
            final dz = lz - pz;
            final cy = math.cos(_wingRotorYaw);
            final sy = math.sin(_wingRotorYaw);
            lx = px + dx * cy + dz * sy;
            lz = pz - dx * sy + dz * cy;
          }
        } else if (partIdx == MeshPartTag.insigniaStar.index) {
          if (_insigniaScale != 1.0 || _insigniaYaw != 0.0 || _insigniaLiftY != 0.0) {
            final px = insigniaPivot?.x ?? 0.0;
            final py = insigniaPivot?.y ?? 0.85;
            final pz = insigniaPivot?.z ?? 0.0;
            var dx = (lx - px) * _insigniaScale;
            final dy = (ly - py) * _insigniaScale;
            var dz = (lz - pz) * _insigniaScale;
            if (_insigniaYaw != 0.0) {
              final cy = math.cos(_insigniaYaw);
              final sy = math.sin(_insigniaYaw);
              final rx = dx * cy + dz * sy;
              final rz = -dx * sy + dz * cy;
              dx = rx;
              dz = rz;
            }
            lx = px + dx;
            ly = py + dy + _insigniaLiftY;
            lz = pz + dz;
          }
        }
      }

      // Apply carrier bodyHull banking, scale, and lift to non-pedestal parts
      // (and mounted passengers).
      if (!isPedestal) {
        var bx = lx * _bodyScale;
        var by = (ly - 0.12) * _bodyScale;
        var bz = lz * _bodyScale;

        if (_bodyRoll != 0.0) {
          final rx = bx * cosBodyRoll - by * sinBodyRoll;
          final ry = bx * sinBodyRoll + by * cosBodyRoll;
          bx = rx;
          by = ry;
        }
        if (_bodyPitch != 0.0) {
          final py = by * cosBodyPitch - bz * sinBodyPitch;
          final pz = by * sinBodyPitch + bz * cosBodyPitch;
          by = py;
          bz = pz;
        }
        lx = bx;
        ly = by + 0.12 + _bodyLiftY;
        lz = bz;
      }

      // Piece world transform: selectedScale -> yawRadians -> worldOrigin.
      final sx = lx * selectedScale;
      final sy = ly * selectedScale;
      final sz = lz * selectedScale;
      final wx = worldOrigin.x + (sx * cosYaw + sz * sinYaw);
      final wy = worldOrigin.y + sy;
      final wz = worldOrigin.z + (-sx * sinYaw + sz * cosYaw);

      final vi = vertOffset + i;
      _unitWorldX[vi] = wx;
      _unitWorldY[vi] = wy;
      _unitWorldZ[vi] = wz;

      final cx = m[0] * wx + m[4] * wy + m[8] * wz + m[12];
      final cy = m[1] * wx + m[5] * wy + m[9] * wz + m[13];
      final cz = m[2] * wx + m[6] * wy + m[10] * wz + m[14];
      final cw = m[3] * wx + m[7] * wy + m[11] * wz + m[15];

      if (!cw.isFinite ||
          !cx.isFinite ||
          !cy.isFinite ||
          !cz.isFinite ||
          cw <= 1e-4) {
        _unitValid[vi] = 0;
        _unitScreenX[vi] = 0.0;
        _unitScreenY[vi] = 0.0;
        _unitDepth[vi] = 1.0;
      } else {
        final invW = 1.0 / cw;
        final screenX = halfW + (cx * invW) * halfW;
        final screenY = halfH - (cy * invW) * halfH;
        _unitValid[vi] = 1;
        _unitScreenX[vi] = screenX;
        _unitScreenY[vi] = screenY;
        _unitDepth[vi] = cz * invW;
        if (screenY < minSY) minSY = screenY;
        if (screenY > maxSY) maxSY = screenY;
      }
    }

    final indices = mesh.faceIndices;
    final normals = mesh.faceNormals;
    final faceSlots = mesh.faceSlots;
    var visibleCount = visibleStart;

    for (var f = 0; f < faceCount; f++) {
      final base = f * 4;
      final i0 = vertOffset + indices[base];
      final i1 = vertOffset + indices[base + 1];
      final i2 = vertOffset + indices[base + 2];
      final i3 = vertOffset + indices[base + 3];
      final uf = faceOffset + f;

      if (_unitValid[i0] == 0 ||
          _unitValid[i1] == 0 ||
          _unitValid[i2] == 0 ||
          _unitValid[i3] == 0) {
        _unitFaceVisible[uf] = 0;
        continue;
      }

      var lnx = normals[f * 3];
      var lny = normals[f * 3 + 1];
      var lnz = normals[f * 3 + 2];

      final partIdx = mesh.partTagForFace(f).index;
      final isPedestal = applySubPartAnim && partIdx == MeshPartTag.basePedestal.index;

      if (applySubPartAnim && !isPedestal) {
        if (partIdx == MeshPartTag.turret.index && _turretYaw != 0.0) {
          final cy = math.cos(_turretYaw);
          final sy = math.sin(_turretYaw);
          final rx = lnx * cy + lnz * sy;
          final rz = -lnx * sy + lnz * cy;
          lnx = rx;
          lnz = rz;
        } else if (partIdx == MeshPartTag.barrel.index) {
          if (_barrelPitch != 0.0) {
            final cp = math.cos(_barrelPitch);
            final sp = math.sin(_barrelPitch);
            final py = lny * cp - lnz * sp;
            final pz = lny * sp + lnz * cp;
            lny = py;
            lnz = pz;
          }
          if (_turretYaw != 0.0) {
            final cy = math.cos(_turretYaw);
            final sy = math.sin(_turretYaw);
            final rx = lnx * cy + lnz * sy;
            final rz = -lnx * sy + lnz * cy;
            lnx = rx;
            lnz = rz;
          }
        } else if (partIdx == MeshPartTag.wingRotor.index) {
          if (_wingRotorRoll != 0.0) {
            final cr = math.cos(_wingRotorRoll);
            final sr = math.sin(_wingRotorRoll);
            final rx = lnx * cr - lny * sr;
            final ry = lnx * sr + lny * cr;
            lnx = rx;
            lny = ry;
          }
          if (_wingRotorYaw != 0.0) {
            final cy = math.cos(_wingRotorYaw);
            final sy = math.sin(_wingRotorYaw);
            final rx = lnx * cy + lnz * sy;
            final rz = -lnx * sy + lnz * cy;
            lnx = rx;
            lnz = rz;
          }
        } else if (partIdx == MeshPartTag.insigniaStar.index && _insigniaYaw != 0.0) {
          final cy = math.cos(_insigniaYaw);
          final sy = math.sin(_insigniaYaw);
          final rx = lnx * cy + lnz * sy;
          final rz = -lnx * sy + lnz * cy;
          lnx = rx;
          lnz = rz;
        }
      }

      if (!isPedestal) {
        if (_bodyRoll != 0.0) {
          final rx = lnx * cosBodyRoll - lny * sinBodyRoll;
          final ry = lnx * sinBodyRoll + lny * cosBodyRoll;
          lnx = rx;
          lny = ry;
        }
        if (_bodyPitch != 0.0) {
          final py = lny * cosBodyPitch - lnz * sinBodyPitch;
          final pz = lny * sinBodyPitch + lnz * cosBodyPitch;
          lny = py;
          lnz = pz;
        }
      }

      final wnx = lnx * cosYaw + lnz * sinYaw;
      final wny = lny;
      final wnz = -lnx * sinYaw + lnz * cosYaw;

      final fcx =
          (_unitWorldX[i0] + _unitWorldX[i1] + _unitWorldX[i2] + _unitWorldX[i3]) *
              0.25;
      final fcy =
          (_unitWorldY[i0] + _unitWorldY[i1] + _unitWorldY[i2] + _unitWorldY[i3]) *
              0.25;
      final fcz =
          (_unitWorldZ[i0] + _unitWorldZ[i1] + _unitWorldZ[i2] + _unitWorldZ[i3]) *
              0.25;

      final vx = _eyePos.x - fcx;
      final vy = _eyePos.y - fcy;
      final vz = _eyePos.z - fcz;
      if (wnx * vx + wny * vy + wnz * vz <= 0.0) {
        _unitFaceVisible[uf] = 0;
        continue;
      }

      final keyDot = math.max(
        0.0,
        wnx * _keyLightDir.x + wny * _keyLightDir.y + wnz * _keyLightDir.z,
      );
      final fillDot = math.max(
        0.0,
        wnx * _fillLightDir.x + wny * _fillLightDir.y + wnz * _fillLightDir.z,
      );
      final slotIdx = faceSlots[f];
      final isHeroicGlow =
          isHero && slotIdx == ProceduralMaterialSlot.heroicEmissive.index;
      final isTeamRing = slotIdx == ProceduralMaterialSlot.teamRing.index;

      final double brightness;
      if (isHeroicGlow) {
        final glowWave = math.sin(elapsedSeconds * 4.5);
        brightness = 1.12 + 0.08 * (glowWave.isFinite ? glowWave : 0.0);
      } else if (isTeamRing) {
        brightness =
            (0.75 + 0.34 * keyDot + 0.14 * fillDot).clamp(0.75, 1.12);
      } else {
        brightness =
            (0.38 + 0.56 * keyDot + 0.20 * fillDot + 0.14 * (wny * 0.5 + 0.5))
                .clamp(0.32, 1.18);
      }

      _unitFaceVisible[uf] = 1;
      _unitFaceV0[uf] = i0;
      _unitFaceV1[uf] = i1;
      _unitFaceV2[uf] = i2;
      _unitFaceV3[uf] = i3;
      _unitFaceArgb[uf] = _shadeColorToArgb32(
        handle.colorForSlot(slotIdx),
        brightness,
      );

      _visibleOrder[visibleCount] = uf;
      _visibleDepths[visibleCount] =
          (_unitDepth[i0] + _unitDepth[i1] + _unitDepth[i2] + _unitDepth[i3]) *
              0.25;
      visibleCount++;
    }

    final screenH = (maxSY.isFinite && minSY.isFinite)
        ? (maxSY - minSY).clamp(8.0, 240.0)
        : 24.0;
    return (visibleEnd: visibleCount, screenHeight: screenH);
  }

  void _emitSelectiveEdges({
    required Canvas canvas,
    required _MeshEdgeTopology topology,
    required int vertOffset,
    required int faceOffset,
    required double pieceScreenH,
  }) {
    final silHalfW = (pieceScreenH * 0.012).clamp(0.38, 0.62);
    final creaseHalfW = (pieceScreenH * 0.0085).clamp(0.28, 0.45);

    for (var e = 0; e < topology.edgeCount; e++) {
      final fa = topology.edgeFaceA[e];
      final fb = topology.edgeFaceB[e];
      final visA = _unitFaceVisible[faceOffset + fa] == 1;
      final visB = fb >= 0 && _unitFaceVisible[faceOffset + fb] == 1;
      if (!visA && !visB) continue;

      final isSilhouette = fb == -1 || visA != visB;
      final isCrease = topology.edgeIsCrease[e] == 1;
      if (!isSilhouette && !isCrease) continue;

      final va = vertOffset + topology.edgeV0[e];
      final vb = vertOffset + topology.edgeV1[e];
      if (_unitValid[va] == 0 || _unitValid[vb] == 0) continue;

      final ax = _unitScreenX[va];
      final ay = _unitScreenY[va];
      final bx = _unitScreenX[vb];
      final by = _unitScreenY[vb];
      final dx = bx - ax;
      final dy = by - ay;
      final lenSq = dx * dx + dy * dy;
      if (lenSq < 1e-4) continue;
      if (!isSilhouette && lenSq < 4.0) continue;

      final invLen = 1.0 / math.sqrt(lenSq);
      final halfW = isSilhouette ? silHalfW : creaseHalfW;
      final nx = -dy * invLen * halfW;
      final ny = dx * invLen * halfW;

      final refFace = visA ? (faceOffset + fa) : (faceOffset + fb);
      final edgeArgb = _scaleArgb(
        _unitFaceArgb[refFace],
        isSilhouette ? 0.40 : 0.56,
      );

      _ensureBatchCapacity(canvas, 4, 6);
      final vBase = _batchVertCount;
      final pBase = vBase * 2;
      _batchPositions[pBase] = ax + nx;
      _batchPositions[pBase + 1] = ay + ny;
      _batchPositions[pBase + 2] = bx + nx;
      _batchPositions[pBase + 3] = by + ny;
      _batchPositions[pBase + 4] = bx - nx;
      _batchPositions[pBase + 5] = by - ny;
      _batchPositions[pBase + 6] = ax - nx;
      _batchPositions[pBase + 7] = ay - ny;

      _batchColors[vBase] = edgeArgb;
      _batchColors[vBase + 1] = edgeArgb;
      _batchColors[vBase + 2] = edgeArgb;
      _batchColors[vBase + 3] = edgeArgb;

      final iBase = _batchIndexCount;
      _batchIndices[iBase] = vBase;
      _batchIndices[iBase + 1] = vBase + 1;
      _batchIndices[iBase + 2] = vBase + 2;
      _batchIndices[iBase + 3] = vBase;
      _batchIndices[iBase + 4] = vBase + 2;
      _batchIndices[iBase + 5] = vBase + 3;

      _batchVertCount += 4;
      _batchIndexCount += 6;
    }
  }

  void _computeAnimPose(RenderPieceNode node, double elapsedSeconds) {
    _bodyPitch = 0.0;
    _bodyRoll = 0.0;
    _bodyLiftY = 0.0;
    _bodyScale = 1.0;
    _turretYaw = 0.0;
    _barrelPitch = 0.0;
    _barrelRecoilZ = 0.0;
    _wingRotorYaw = 0.0;
    _wingRotorRoll = 0.0;
    _insigniaYaw = 0.0;
    _insigniaLiftY = 0.0;
    _insigniaScale = 1.0;

    final t = elapsedSeconds.isFinite ? elapsedSeconds : 0.0;
    final seed = node.phaseSeed.isFinite ? node.phaseSeed : 0.0;
    final p = node.animProgress.isFinite ? node.animProgress : 0.0;
    final type = node.visualKey.type;

    switch (node.animClip) {
      case PieceAnimClip.idle:
        if (type == PieceType.navy) {
          _bodyRoll = 0.04 * math.sin(t * 2.1 + seed);
          _wingRotorYaw = 0.45 * math.sin(t * 2.0 + seed);
        } else if (type == PieceType.airForce) {
          _bodyRoll = 0.03 * math.sin(t * 2.6 + seed);
        } else if (type == PieceType.tank || type == PieceType.antiAircraft) {
          _turretYaw = 0.12 * math.sin(t * 0.9 + seed);
          if (type == PieceType.antiAircraft) {
            _wingRotorYaw = t * 1.6 + seed;
          }
        } else if (type == PieceType.headquarters) {
          _wingRotorYaw = t * 1.4 + seed;
        } else if (type == PieceType.commander) {
          _insigniaLiftY = 0.015 * math.sin(t * 2.5 + seed);
        }
      case PieceAnimClip.select:
        _turretYaw = 0.35 * math.sin(t * 3.8);
        _barrelPitch = -0.08 * math.sin(t * 3.8);
        if (type == PieceType.navy) {
          _wingRotorYaw = 0.65 * math.sin(t * 4.0 + seed);
        } else if (type == PieceType.airForce) {
          _wingRotorRoll = 0.03 * math.sin(t * 5.0);
        } else {
          _wingRotorYaw = t * 4.5 + seed;
        }
        _insigniaYaw = t * 3.2;
        _insigniaLiftY = 0.04;
      case PieceAnimClip.move:
        _bodyPitch =
            node.movePitchRadians.isFinite ? node.movePitchRadians : 0.0;
        _bodyRoll = node.moveRollRadians.isFinite ? node.moveRollRadians : 0.0;
        if (type == PieceType.infantry ||
            type == PieceType.militia ||
            type == PieceType.commander) {
          _bodyLiftY = 0.035 * math.sin(p * math.pi * 4.0).abs();
        }
        if (type == PieceType.headquarters || type == PieceType.antiAircraft) {
          _wingRotorYaw = t * 8.0 + seed;
        } else if (type == PieceType.airForce) {
          _wingRotorRoll = 0.04 * math.sin(p * math.pi);
        }
      case PieceAnimClip.promote:
        final env = math.sin(p * math.pi);
        _bodyLiftY = 0.10 * env;
        _bodyScale = 1.0 + 0.06 * env;
        _insigniaYaw = p * 4.0 * math.pi;
        _insigniaLiftY = 0.08 * env;
        _insigniaScale = 1.0 + 0.28 * env;
      case PieceAnimClip.attack:
        final env = math.sin(p * math.pi);
        _barrelRecoilZ = -0.08 * env;
        _bodyPitch = -0.08 * env;
      case PieceAnimClip.capture:
        final env = math.sin(p * math.pi);
        _bodyLiftY = 0.06 * env;
        _bodyPitch = 0.12 * env;
      case PieceAnimClip.defeat:
        _bodyPitch = 0.45 * p;
        _bodyRoll = 0.25 * p;
        _bodyScale = (1.0 - 0.35 * p).clamp(0.4, 1.0);
    }
  }

  static Vector3 _fallbackSocket(PieceType carrierType, int slotIndex) {
    return switch (carrierType) {
      PieceType.navy =>
        slotIndex == 0 ? Vector3(0.0, 0.26, 0.07) : Vector3(0.0, 0.26, -0.24),
      PieceType.airForce =>
        slotIndex == 0 ? Vector3(-0.15, 0.59, -0.05) : Vector3(0.15, 0.59, -0.05),
      PieceType.tank =>
        slotIndex == 0 ? Vector3(-0.13, 0.33, -0.21) : Vector3(0.13, 0.33, -0.21),
      PieceType.engineer => Vector3(0.0, 0.51, -0.04),
      PieceType.headquarters => Vector3(0.0, 0.56, 0.0),
      _ => slotIndex == 0 ? Vector3(0.0, 0.52, 0.0) : Vector3(0.0, 0.78, 0.0),
    };
  }

  void _ensureUnitCapacity(int vertCount, int faceCount) {
    if (vertCount > _unitScreenX.length) {
      final cap = vertCount * 2;
      _unitScreenX = Float32List(cap);
      _unitScreenY = Float32List(cap);
      _unitDepth = Float32List(cap);
      _unitValid = Uint8List(cap);
      _unitWorldX = Float32List(cap);
      _unitWorldY = Float32List(cap);
      _unitWorldZ = Float32List(cap);
    }
    if (faceCount > _unitFaceV0.length) {
      final cap = faceCount * 2;
      _unitFaceV0 = Int32List(cap);
      _unitFaceV1 = Int32List(cap);
      _unitFaceV2 = Int32List(cap);
      _unitFaceV3 = Int32List(cap);
      _unitFaceArgb = Int32List(cap);
      _unitFaceVisible = Uint8List(cap);
      _visibleOrder = Int32List(cap);
      _visibleDepths = Float32List(cap);
    }
  }

  void _ensureBatchCapacity(Canvas canvas, int neededVerts, int neededIndices) {
    if (_batchVertCount + neededVerts > _maxVerticesPerBatch ||
        _batchIndexCount + neededIndices > 65535) {
      _flushBatch(canvas);
    }
    final requiredVerts = _batchVertCount + neededVerts;
    if (requiredVerts > _batchColors.length) {
      final newVertCap = math.min(
        _maxVerticesPerBatch,
        math.max(requiredVerts * 2, _batchColors.length * 2),
      );
      final newPos = Float32List(newVertCap * 2);
      newPos.setRange(0, _batchVertCount * 2, _batchPositions);
      _batchPositions = newPos;
      final newColors = Int32List(newVertCap);
      newColors.setRange(0, _batchVertCount, _batchColors);
      _batchColors = newColors;
    }
    final requiredIndices = _batchIndexCount + neededIndices;
    if (requiredIndices > _batchIndices.length) {
      final newCap = math.max(requiredIndices * 2, _batchIndices.length * 2);
      final newIdx = Uint16List(newCap);
      newIdx.setRange(0, _batchIndexCount, _batchIndices);
      _batchIndices = newIdx;
    }
  }

  void _flushBatch(Canvas canvas) {
    if (_batchIndexCount < 3 || _batchVertCount < 3) {
      _batchVertCount = 0;
      _batchIndexCount = 0;
      return;
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_batchPositions, 0, _batchVertCount * 2),
      colors: Int32List.sublistView(_batchColors, 0, _batchVertCount),
      indices: Uint16List.sublistView(_batchIndices, 0, _batchIndexCount),
    );
    canvas.drawVertices(vertices, ui.BlendMode.dst, _vertexPaint);
    vertices.dispose();
    _lastDrawVerticesCallCount++;
    _batchVertCount = 0;
    _batchIndexCount = 0;
  }

  static _MeshEdgeTopology _getEdgeTopology(ProceduralMeshPrimitive mesh) {
    final existing = _edgeTopologyCache[mesh];
    if (existing != null) return existing;
    final built = _MeshEdgeTopology.build(mesh);
    _edgeTopologyCache[mesh] = built;
    return built;
  }

  Offset? _projectPoint(Size size, double wx, double wy, double wz) {
    if (!wx.isFinite || !wy.isFinite || !wz.isFinite) return null;
    _projVec.setValues(wx, wy, wz, 1.0);
    _vpMatrix.transform(_projVec);
    if (!_projVec.w.isFinite ||
        !_projVec.x.isFinite ||
        !_projVec.y.isFinite ||
        _projVec.w <= 1e-4) {
      return null;
    }
    final invW = 1.0 / _projVec.w;
    final ndcX = _projVec.x * invW;
    final ndcY = _projVec.y * invW;
    if (!ndcX.isFinite || !ndcY.isFinite) return null;
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

  static int _shadeColorToArgb32(Color c, double factor) {
    final safeFactor = factor.isFinite ? factor.clamp(0.0, 255.0) : 1.0;
    final a = (c.a * 255.0).round().clamp(0, 255);
    final r = (c.r * safeFactor * 255.0).round().clamp(0, 255);
    final g = (c.g * safeFactor * 255.0).round().clamp(0, 255);
    final b = (c.b * safeFactor * 255.0).round().clamp(0, 255);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  static int _scaleArgb(int argb, double factor) {
    final a = (argb >>> 24) & 0xFF;
    final r = (((argb >>> 16) & 0xFF) * factor).round().clamp(0, 255);
    final g = (((argb >>> 8) & 0xFF) * factor).round().clamp(0, 255);
    final b = ((argb & 0xFF) * factor).round().clamp(0, 255);
    return (a << 24) | (r << 16) | (g << 8) | b;
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

final class _MeshEdgeTopology {
  _MeshEdgeTopology({
    required this.vertexPartTags,
    required this.edgeV0,
    required this.edgeV1,
    required this.edgeFaceA,
    required this.edgeFaceB,
    required this.edgeIsCrease,
  });

  final Uint8List vertexPartTags;
  final Int32List edgeV0;
  final Int32List edgeV1;
  final Int32List edgeFaceA;
  final Int32List edgeFaceB;
  final Uint8List edgeIsCrease;

  int get edgeCount => edgeV0.length;

  static _MeshEdgeTopology build(ProceduralMeshPrimitive mesh) {
    final vertCount = mesh.vertices.length ~/ 3;
    final vertParts = Uint8List(vertCount)
      ..fillRange(0, vertCount, MeshPartTag.bodyHull.index);
    final faceCount = mesh.faceCount;
    final indices = mesh.faceIndices;
    final normals = mesh.faceNormals;
    final slots = mesh.faceSlots;

    final edgeMap = <int, _EdgeAccum>{};

    void recordEdge(int a, int b, int faceIdx) {
      if (a == b) return;
      final lo = a < b ? a : b;
      final hi = a < b ? b : a;
      final key = (lo << 20) | hi;
      final existing = edgeMap[key];
      if (existing == null) {
        edgeMap[key] = _EdgeAccum(lo, hi, faceIdx);
      } else if (existing.faceB == -1 && existing.faceA != faceIdx) {
        existing.faceB = faceIdx;
      }
    }

    for (var f = 0; f < faceCount; f++) {
      final partIdx = mesh.partTagForFace(f).index;
      final base = f * 4;
      final i0 = indices[base];
      final i1 = indices[base + 1];
      final i2 = indices[base + 2];
      final i3 = indices[base + 3];

      if (i0 < vertCount) vertParts[i0] = partIdx;
      if (i1 < vertCount) vertParts[i1] = partIdx;
      if (i2 < vertCount) vertParts[i2] = partIdx;
      if (i3 < vertCount) vertParts[i3] = partIdx;

      if (i3 == i2) {
        recordEdge(i0, i1, f);
        recordEdge(i1, i2, f);
        recordEdge(i2, i0, f);
      } else {
        recordEdge(i0, i1, f);
        recordEdge(i1, i2, f);
        recordEdge(i2, i3, f);
        recordEdge(i3, i0, f);
      }
    }

    final count = edgeMap.length;
    final v0 = Int32List(count);
    final v1 = Int32List(count);
    final fa = Int32List(count);
    final fb = Int32List(count);
    final crease = Uint8List(count);

    var idx = 0;
    for (final edge in edgeMap.values) {
      final f0 = edge.faceA;
      final f1 = edge.faceB;
      var isCrease = f1 == -1 || slots[f0] != slots[f1];
      if (!isCrease) {
        final dot = normals[f0 * 3] * normals[f1 * 3] +
            normals[f0 * 3 + 1] * normals[f1 * 3 + 1] +
            normals[f0 * 3 + 2] * normals[f1 * 3 + 2];
        if (dot < 0.55) {
          isCrease = true;
        }
      }
      v0[idx] = edge.v0;
      v1[idx] = edge.v1;
      fa[idx] = f0;
      fb[idx] = f1;
      crease[idx] = isCrease ? 1 : 0;
      idx++;
    }

    return _MeshEdgeTopology(
      vertexPartTags: vertParts,
      edgeV0: v0,
      edgeV1: v1,
      edgeFaceA: fa,
      edgeFaceB: fb,
      edgeIsCrease: crease,
    );
  }
}

final class _EdgeAccum {
  _EdgeAccum(this.v0, this.v1, this.faceA);
  final int v0;
  final int v1;
  final int faceA;
  int faceB = -1;
}
