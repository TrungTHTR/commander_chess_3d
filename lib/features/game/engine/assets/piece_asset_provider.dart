import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:vector_math/vector_math_64.dart';

import '../../models/asset_manifest_model.dart';
import '../../models/piece_model.dart';

/// Material slots matching `docs/BLENDER_ASSET_CONTRACT.md` §4.
enum ProceduralMaterialSlot {
  factionPrimary,
  factionAccent,
  basePedestal,
  neutralMetal,
  heroicEmissive,
}

/// Resolved 3D piece handle returned by [PieceAssetProvider].
abstract interface class PieceVisualHandle {
  PieceVisualKey get visualKey;
  double get boundingRadius;
  bool get isGlbBacked;
}

/// Decoupled 3D piece asset registry supporting both procedural starter meshes
/// and future Blender `.glb` asset providers (`GlbPieceAssetProvider`).
abstract interface class PieceAssetProvider {
  Future<void> preloadAll(AssetManifest manifest);
  PieceVisualHandle resolvePiece(PieceVisualKey key);
  void dispose();
}

/// Pre-baked low-poly mesh primitive with flat vertex buffer and quad/tri faces.
final class ProceduralMeshPrimitive {
  ProceduralMeshPrimitive({
    required this.vertices,
    required this.faceIndices,
    required this.faceNormals,
    required this.faceSlots,
  });

  /// Flat XYZ vertex coordinates `[x0, y0, z0, x1, y1, z1, ...]` in local
  /// piece space `[-0.42, 0.42] × [0.0, 1.05] × [-0.42, 0.42]`.
  final Float32List vertices;

  /// Quad vertex index tuples `[i0, i1, i2, i3, ...]` (`4` indices per face;
  /// triangles repeat `i3 == i2`).
  final Int32List faceIndices;

  /// Outward local-space unit normals `[nx, ny, nz, ...]` (`3` floats per face).
  final Float32List faceNormals;

  /// [ProceduralMaterialSlot.index] per face.
  final Uint8List faceSlots;

  int get faceCount => faceSlots.length;
}

/// Resolved procedural 3D piece geometry + faction/heroic material palette.
final class ProceduralPieceVisualHandle implements PieceVisualHandle {
  ProceduralPieceVisualHandle({
    required this.visualKey,
    required this.boundingRadius,
    required this.mesh,
    required this.slotColors,
  });

  @override
  final PieceVisualKey visualKey;

  @override
  final double boundingRadius;

  @override
  bool get isGlbBacked => false;

  final ProceduralMeshPrimitive mesh;

  /// Color table indexed by [ProceduralMaterialSlot.index].
  final List<Color> slotColors;

  Color colorForSlot(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= slotColors.length) {
      return slotColors.first;
    }
    return slotColors[slotIndex];
  }
}

/// Procedural low-poly 3D piece provider generating distinct geometric unit
/// silhouettes inside `[-0.42, 0.42] × [0.0, 1.05] × [-0.42, 0.42]` local space.
final class ProceduralPieceAssetProvider implements PieceAssetProvider {
  final Map<PieceType, ProceduralMeshPrimitive> _meshCache =
      <PieceType, ProceduralMeshPrimitive>{};
  final Map<PieceVisualKey, ProceduralPieceVisualHandle> _handleCache =
      <PieceVisualKey, ProceduralPieceVisualHandle>{};
  AssetManifest? _manifest;
  bool _disposed = false;

  @override
  Future<void> preloadAll(AssetManifest manifest) async {
    _disposed = false;
    _manifest = manifest;
    _handleCache.clear();

    for (final type in PieceType.values) {
      _meshCache.putIfAbsent(type, () => _buildPieceMesh(type));
    }

    for (final side in PlayerSide.values) {
      for (final type in PieceType.values) {
        for (final isHero in const <bool>[false, true]) {
          final key = PieceVisualKey(type: type, side: side, isHero: isHero);
          _handleCache[key] = _createHandle(key);
        }
      }
    }
  }

  @override
  PieceVisualHandle resolvePiece(PieceVisualKey key) {
    if (_disposed) {
      return _createHandle(key);
    }
    return _handleCache.putIfAbsent(key, () => _createHandle(key));
  }

  @override
  void dispose() {
    _disposed = true;
    _handleCache.clear();
    _meshCache.clear();
    _manifest = null;
  }

  ProceduralPieceVisualHandle _createHandle(PieceVisualKey key) {
    final mesh = _meshCache.putIfAbsent(
      key.type,
      () => _buildPieceMesh(key.type),
    );
    final descriptor = _manifest?.findPiece(key);
    final slotColors = _resolveSlotColors(key, descriptor);
    return ProceduralPieceVisualHandle(
      visualKey: key,
      boundingRadius: descriptor?.boundingRadius ?? 0.42,
      mesh: mesh,
      slotColors: slotColors,
    );
  }

  List<Color> _resolveSlotColors(
    PieceVisualKey key,
    MeshAssetDescriptor? descriptor,
  ) {
    final isRed = key.side == PlayerSide.red;
    var factionPrimary = isRed
        ? const Color(0xFFC62828)
        : const Color(0xFF1565C0);
    var factionAccent = isRed
        ? const Color(0xFFFFB300)
        : const Color(0xFFB0BEC5);
    var basePedestal = key.isHero
        ? const Color(0xFFFFD54F)
        : const Color(0xFF455A64);
    var neutralMetal = const Color(0xFF37474F);
    var heroicEmissive = const Color(0xFFFFD54F);

    if (descriptor != null) {
      for (final slot in descriptor.materialSlots) {
        final effectiveHex =
            (key.isHero && slot.heroicHex != null && slot.heroicHex!.isNotEmpty)
                ? slot.heroicHex!
                : slot.defaultHex;
        final parsed = _tryParseHexColor(effectiveHex);
        if (parsed == null) continue;

        switch (slot.slotName) {
          case 'mat_faction_primary':
            factionPrimary = parsed;
          case 'mat_faction_accent':
            factionAccent = parsed;
          case 'mat_base_pedestal':
            basePedestal = key.isHero ? const Color(0xFFFFD54F) : parsed;
          case 'mat_neutral_metal':
            neutralMetal = parsed;
          case 'mat_heroic_emissive':
            heroicEmissive = parsed;
        }
      }
    }

    return List<Color>.unmodifiable(<Color>[
      factionPrimary,
      factionAccent,
      basePedestal,
      neutralMetal,
      heroicEmissive,
    ]);
  }

  static Color? _tryParseHexColor(String hex) {
    final cleaned = hex.trim().replaceFirst('#', '');
    if (cleaned.length == 6) {
      final value = int.tryParse('FF$cleaned', radix: 16);
      return value == null ? null : Color(value);
    }
    if (cleaned.length == 8) {
      final value = int.tryParse(cleaned, radix: 16);
      return value == null ? null : Color(value);
    }
    return null;
  }

  static ProceduralMeshPrimitive _buildPieceMesh(PieceType type) {
    final b = _MeshBuilder();

    // Base pedestal common to all 11 tactical pieces (resting flush at y = 0.0).
    switch (type) {
      case PieceType.commander:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.36, 0.14, 0.36,
          ProceduralMaterialSlot.basePedestal,
        );
        b.addBox(
          0, 0.14, 0, 0.24, 0.38, 0.20,
          ProceduralMaterialSlot.factionPrimary,
          topScaleX: 0.72,
          topScaleZ: 0.72,
        );
        b.addOctagonalPrism(
          0, 0.52, 0, 0.16, 0.18, 0.16,
          ProceduralMaterialSlot.factionAccent,
        );
        // Command star crown emblem (crossed diamond spires).
        b.addRotatedBox(
          0, 0.84, 0, 0.06, 0.19, 0.06,
          0.0, 0.0, 0.0,
          ProceduralMaterialSlot.heroicEmissive,
        );
        b.addRotatedBox(
          0, 0.84, 0, 0.22, 0.055, 0.055,
          0.0, 0.0, 0.0,
          ProceduralMaterialSlot.heroicEmissive,
        );
        b.addRotatedBox(
          0, 0.84, 0, 0.16, 0.05, 0.05,
          0.0, 0.0, 0.785,
          ProceduralMaterialSlot.factionAccent,
        );
        b.addRotatedBox(
          0, 0.84, 0, 0.16, 0.05, 0.05,
          0.0, 0.0, -0.785,
          ProceduralMaterialSlot.factionAccent,
        );

      case PieceType.headquarters:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.40, 0.12, 0.40,
          ProceduralMaterialSlot.basePedestal,
        );
        // Wide sloped armored bunker.
        b.addBox(
          0, 0.12, 0, 0.34, 0.34, 0.32,
          ProceduralMaterialSlot.factionPrimary,
          topScaleX: 0.76,
          topScaleZ: 0.76,
        );
        // Roof parapet + command slit.
        b.addBox(
          0, 0.46, 0, 0.23, 0.09, 0.22,
          ProceduralMaterialSlot.factionAccent,
        );
        b.addBox(
          0.11, 0.55, -0.09, 0.025, 0.42, 0.025,
          ProceduralMaterialSlot.neutralMetal,
        );
        b.addBox(
          0.11, 0.88, -0.02, 0.03, 0.08, 0.10,
          ProceduralMaterialSlot.factionAccent,
        );

      case PieceType.infantry:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.32, 0.11, 0.32,
          ProceduralMaterialSlot.basePedestal,
        );
        // Torso.
        b.addBox(
          0, 0.11, -0.02, 0.18, 0.42, 0.14,
          ProceduralMaterialSlot.factionPrimary,
          topScaleX: 0.86,
          topScaleZ: 0.84,
        );
        // Forward tactical shield plate.
        b.addBox(
          -0.06, 0.16, 0.16, 0.17, 0.42, 0.045,
          ProceduralMaterialSlot.factionAccent,
        );
        // Helmet dome.
        b.addOctagonalPrism(
          0, 0.55, -0.01, 0.15, 0.22, 0.15,
          ProceduralMaterialSlot.neutralMetal,
        );
        b.addBox(
          0, 0.77, -0.01, 0.10, 0.06, 0.10,
          ProceduralMaterialSlot.factionPrimary,
        );

      case PieceType.militia:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.29, 0.10, 0.29,
          ProceduralMaterialSlot.basePedestal,
        );
        // Lean torso.
        b.addBox(
          0, 0.10, 0, 0.15, 0.40, 0.13,
          ProceduralMaterialSlot.factionPrimary,
          topScaleX: 0.85,
          topScaleZ: 0.85,
        );
        // Rifle slung diagonally.
        b.addRotatedBox(
          0.17, 0.36, 0.08, 0.03, 0.28, 0.03,
          -0.25, 0.0, -0.15,
          ProceduralMaterialSlot.neutralMetal,
        );
        // Head + tilted militia beret.
        b.addOctagonalPrism(
          0, 0.52, 0, 0.12, 0.16, 0.12,
          ProceduralMaterialSlot.neutralMetal,
        );
        b.addRotatedBox(
          0.03, 0.72, 0.0, 0.17, 0.05, 0.15,
          0.0, 0.0, 0.22,
          ProceduralMaterialSlot.factionAccent,
        );

      case PieceType.engineer:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.34, 0.11, 0.34,
          ProceduralMaterialSlot.basePedestal,
        );
        // Chassis & utility pack.
        b.addBox(
          0, 0.11, 0.02, 0.21, 0.30, 0.22,
          ProceduralMaterialSlot.factionPrimary,
        );
        b.addBox(
          0, 0.24, -0.22, 0.16, 0.24, 0.08,
          ProceduralMaterialSlot.neutralMetal,
        );
        // Folded pontoon bridge deck on top.
        b.addBox(
          0, 0.41, 0.04, 0.30, 0.10, 0.28,
          ProceduralMaterialSlot.factionAccent,
        );
        b.addBox(
          0, 0.51, 0.04, 0.22, 0.08, 0.20,
          ProceduralMaterialSlot.neutralMetal,
        );

      case PieceType.tank:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.37, 0.10, 0.37,
          ProceduralMaterialSlot.basePedestal,
        );
        // Left and right tracks.
        b.addBox(
          -0.22, 0.10, 0, 0.09, 0.16, 0.34,
          ProceduralMaterialSlot.neutralMetal,
        );
        b.addBox(
          0.22, 0.10, 0, 0.09, 0.16, 0.34,
          ProceduralMaterialSlot.neutralMetal,
        );
        // Armored hull.
        b.addBox(
          0, 0.14, 0, 0.18, 0.20, 0.30,
          ProceduralMaterialSlot.factionPrimary,
          topScaleX: 0.90,
          topScaleZ: 0.88,
        );
        // Turret + forward gun barrel.
        b.addOctagonalPrism(
          0, 0.34, -0.02, 0.19, 0.18, 0.20,
          ProceduralMaterialSlot.factionPrimary,
        );
        b.addBox(
          0, 0.52, -0.03, 0.11, 0.05, 0.11,
          ProceduralMaterialSlot.factionAccent,
        );
        b.addBox(
          0, 0.41, 0.24, 0.035, 0.035, 0.17,
          ProceduralMaterialSlot.neutralMetal,
        );

      case PieceType.artillery:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.36, 0.10, 0.36,
          ProceduralMaterialSlot.basePedestal,
        );
        // Heavy carriage chassis.
        b.addBox(
          0, 0.10, -0.04, 0.26, 0.19, 0.26,
          ProceduralMaterialSlot.factionPrimary,
        );
        // Gun shield.
        b.addBox(
          0, 0.29, 0.08, 0.22, 0.22, 0.04,
          ProceduralMaterialSlot.factionAccent,
        );
        // Angled elevated howitzer barrel (+Z forward, angled upward).
        b.addRotatedBox(
          0, 0.48, 0.14, 0.045, 0.045, 0.26,
          -0.46, 0.0, 0.0,
          ProceduralMaterialSlot.neutralMetal,
        );

      case PieceType.antiAircraft:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.35, 0.10, 0.35,
          ProceduralMaterialSlot.basePedestal,
        );
        b.addBox(
          0, 0.10, 0, 0.24, 0.22, 0.24,
          ProceduralMaterialSlot.factionPrimary,
        );
        b.addOctagonalPrism(
          0, 0.32, 0, 0.18, 0.16, 0.18,
          ProceduralMaterialSlot.factionAccent,
        );
        // Twin skyward AA barrels.
        b.addRotatedBox(
          -0.08, 0.56, 0.08, 0.03, 0.03, 0.24,
          -0.78, 0.0, 0.0,
          ProceduralMaterialSlot.neutralMetal,
        );
        b.addRotatedBox(
          0.08, 0.56, 0.08, 0.03, 0.03, 0.24,
          -0.78, 0.0, 0.0,
          ProceduralMaterialSlot.neutralMetal,
        );

      case PieceType.missile:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.37, 0.10, 0.37,
          ProceduralMaterialSlot.basePedestal,
        );
        // Transporter-erector chassis.
        b.addBox(
          0, 0.10, 0, 0.25, 0.20, 0.32,
          ProceduralMaterialSlot.factionPrimary,
        );
        // Twin angled missile pods + warhead tips.
        b.addRotatedBox(
          -0.11, 0.52, 0.02, 0.075, 0.28, 0.075,
          0.35, 0.0, 0.0,
          ProceduralMaterialSlot.neutralMetal,
        );
        b.addRotatedBox(
          0.11, 0.52, 0.02, 0.075, 0.28, 0.075,
          0.35, 0.0, 0.0,
          ProceduralMaterialSlot.neutralMetal,
        );
        b.addRotatedBox(
          -0.11, 0.80, 0.11, 0.055, 0.08, 0.055,
          0.35, 0.0, 0.0,
          ProceduralMaterialSlot.factionAccent,
        );
        b.addRotatedBox(
          0.11, 0.80, 0.11, 0.055, 0.08, 0.055,
          0.35, 0.0, 0.0,
          ProceduralMaterialSlot.factionAccent,
        );

      case PieceType.airForce:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.33, 0.10, 0.33,
          ProceduralMaterialSlot.basePedestal,
        );
        // Slender flight pylon raising aircraft above deck.
        b.addBox(
          0, 0.10, -0.02, 0.04, 0.44, 0.05,
          ProceduralMaterialSlot.neutralMetal,
        );
        // Fuselage.
        b.addBox(
          0, 0.54, 0.02, 0.075, 0.10, 0.34,
          ProceduralMaterialSlot.factionPrimary,
          topScaleX: 0.72,
          topScaleZ: 0.86,
        );
        // Cockpit canopy.
        b.addBox(
          0, 0.64, 0.12, 0.045, 0.06, 0.11,
          ProceduralMaterialSlot.factionAccent,
          topScaleX: 0.65,
          topScaleZ: 0.65,
        );
        // Swept delta wings.
        b.addRotatedBox(
          -0.19, 0.58, -0.04, 0.17, 0.025, 0.10,
          0.0, 0.45, 0.0,
          ProceduralMaterialSlot.factionPrimary,
        );
        b.addRotatedBox(
          0.19, 0.58, -0.04, 0.17, 0.025, 0.10,
          0.0, -0.45, 0.0,
          ProceduralMaterialSlot.factionPrimary,
        );
        // Twin canted tail fins.
        b.addRotatedBox(
          -0.08, 0.70, -0.24, 0.02, 0.11, 0.07,
          0.0, 0.0, 0.28,
          ProceduralMaterialSlot.factionAccent,
        );
        b.addRotatedBox(
          0.08, 0.70, -0.24, 0.02, 0.11, 0.07,
          0.0, 0.0, -0.28,
          ProceduralMaterialSlot.factionAccent,
        );

      case PieceType.navy:
        b.addOctagonalPrism(
          0, 0.0, 0, 0.36, 0.09, 0.36,
          ProceduralMaterialSlot.basePedestal,
        );
        // Destroyer hull (tapered bow & stern).
        b.addBox(
          0, 0.09, 0.0, 0.18, 0.17, 0.37,
          ProceduralMaterialSlot.factionPrimary,
          topScaleX: 1.08,
          topScaleZ: 1.02,
        );
        // Forward deck turret.
        b.addOctagonalPrism(
          0, 0.26, 0.18, 0.08, 0.09, 0.08,
          ProceduralMaterialSlot.neutralMetal,
        );
        b.addBox(
          0, 0.31, 0.29, 0.02, 0.02, 0.10,
          ProceduralMaterialSlot.neutralMetal,
        );
        // Bridge superstructure + radar mast.
        b.addBox(
          0, 0.26, -0.08, 0.12, 0.24, 0.14,
          ProceduralMaterialSlot.factionAccent,
          topScaleX: 0.78,
          topScaleZ: 0.78,
        );
        b.addBox(
          0, 0.50, -0.09, 0.025, 0.26, 0.025,
          ProceduralMaterialSlot.neutralMetal,
        );
        b.addBox(
          0, 0.68, -0.09, 0.11, 0.03, 0.025,
          ProceduralMaterialSlot.factionAccent,
        );
    }

    return b.build();
  }
}

final class _MeshBuilder {
  final List<double> _verts = <double>[];
  final List<int> _faces = <int>[];
  final List<double> _normals = <double>[];
  final List<int> _slots = <int>[];

  final Vector3 _v0 = Vector3.zero();
  final Vector3 _v1 = Vector3.zero();
  final Vector3 _v2 = Vector3.zero();
  final Vector3 _e1 = Vector3.zero();
  final Vector3 _e2 = Vector3.zero();
  final Vector3 _n = Vector3.zero();

  int _addVertex(double x, double y, double z) {
    final idx = _verts.length ~/ 3;
    _verts.add(x.clamp(-0.42, 0.42));
    _verts.add(y.clamp(0.0, 1.05));
    _verts.add(z.clamp(-0.42, 0.42));
    return idx;
  }

  void _addQuad(int i0, int i1, int i2, int i3, ProceduralMaterialSlot slot) {
    _faces.add(i0);
    _faces.add(i1);
    _faces.add(i2);
    _faces.add(i3);
    _slots.add(slot.index);

    _v0.setValues(_verts[i0 * 3], _verts[i0 * 3 + 1], _verts[i0 * 3 + 2]);
    _v1.setValues(_verts[i1 * 3], _verts[i1 * 3 + 1], _verts[i1 * 3 + 2]);
    _v2.setValues(_verts[i2 * 3], _verts[i2 * 3 + 1], _verts[i2 * 3 + 2]);

    _e1
      ..setFrom(_v1)
      ..sub(_v0);
    _e2
      ..setFrom(_v2)
      ..sub(_v0);
    _e1.crossInto(_e2, _n);
    final len = _n.length;
    if (len > 1e-6) {
      _n.scale(1.0 / len);
    } else {
      _n.setValues(0.0, 1.0, 0.0);
    }
    _normals.add(_n.x);
    _normals.add(_n.y);
    _normals.add(_n.z);
  }

  void addBox(
    double cx,
    double yBottom,
    double cz,
    double halfW,
    double height,
    double halfD,
    ProceduralMaterialSlot slot, {
    double topScaleX = 1.0,
    double topScaleZ = 1.0,
  }) {
    final yTop = yBottom + height;
    final bMinX = cx - halfW;
    final bMaxX = cx + halfW;
    final bMinZ = cz - halfD;
    final bMaxZ = cz + halfD;

    final tHalfW = halfW * topScaleX;
    final tHalfD = halfD * topScaleZ;
    final tMinX = cx - tHalfW;
    final tMaxX = cx + tHalfW;
    final tMinZ = cz - tHalfD;
    final tMaxZ = cz + tHalfD;

    final b0 = _addVertex(bMinX, yBottom, bMaxZ);
    final b1 = _addVertex(bMaxX, yBottom, bMaxZ);
    final b2 = _addVertex(bMaxX, yBottom, bMinZ);
    final b3 = _addVertex(bMinX, yBottom, bMinZ);

    final t0 = _addVertex(tMinX, yTop, tMaxZ);
    final t1 = _addVertex(tMaxX, yTop, tMaxZ);
    final t2 = _addVertex(tMaxX, yTop, tMinZ);
    final t3 = _addVertex(tMinX, yTop, tMinZ);

    // Front (+Z), Right (+X), Back (-Z), Left (-X), Top (+Y), Bottom (-Y).
    _addQuad(b0, b1, t1, t0, slot);
    _addQuad(b1, b2, t2, t1, slot);
    _addQuad(b2, b3, t3, t2, slot);
    _addQuad(b3, b0, t0, t3, slot);
    _addQuad(t0, t1, t2, t3, slot);
    _addQuad(b3, b2, b1, b0, slot);
  }

  void addRotatedBox(
    double cx,
    double cy,
    double cz,
    double halfW,
    double halfH,
    double halfD,
    double rotX,
    double rotY,
    double rotZ,
    ProceduralMaterialSlot slot,
  ) {
    final rot = Matrix4.identity()
      ..rotateY(rotY)
      ..rotateX(rotX)
      ..rotateZ(rotZ);

    int addRotatedVertex(double lx, double ly, double lz) {
      final p = Vector3(lx, ly, lz);
      rot.transform3(p);
      return _addVertex(cx + p.x, cy + p.y, cz + p.z);
    }

    final b0 = addRotatedVertex(-halfW, -halfH, halfD);
    final b1 = addRotatedVertex(halfW, -halfH, halfD);
    final b2 = addRotatedVertex(halfW, -halfH, -halfD);
    final b3 = addRotatedVertex(-halfW, -halfH, -halfD);

    final t0 = addRotatedVertex(-halfW, halfH, halfD);
    final t1 = addRotatedVertex(halfW, halfH, halfD);
    final t2 = addRotatedVertex(halfW, halfH, -halfD);
    final t3 = addRotatedVertex(-halfW, halfH, -halfD);

    _addQuad(b0, b1, t1, t0, slot);
    _addQuad(b1, b2, t2, t1, slot);
    _addQuad(b2, b3, t3, t2, slot);
    _addQuad(b3, b0, t0, t3, slot);
    _addQuad(t0, t1, t2, t3, slot);
    _addQuad(b3, b2, b1, b0, slot);
  }

  void addOctagonalPrism(
    double cx,
    double yBottom,
    double cz,
    double radiusX,
    double height,
    double radiusZ,
    ProceduralMaterialSlot slot,
  ) {
    const sides = 8;
    final yTop = yBottom + height;
    final bottomIndices = <int>[];
    final topIndices = <int>[];

    for (var i = 0; i < sides; i++) {
      // Negative angle step gives CCW order around +Y when viewed from above.
      final angle = -i * (2.0 * math.pi / sides);
      final vx = cx + math.cos(angle) * radiusX;
      final vz = cz + math.sin(angle) * radiusZ;
      bottomIndices.add(_addVertex(vx, yBottom, vz));
      topIndices.add(_addVertex(vx, yTop, vz));
    }

    for (var i = 0; i < sides; i++) {
      final next = (i + 1) % sides;
      _addQuad(
        bottomIndices[i],
        bottomIndices[next],
        topIndices[next],
        topIndices[i],
        slot,
      );
    }

    // Top cap split into 2 quads + 2 quads (quads of 4 vertices around center).
    final topCenter = _addVertex(cx, yTop, cz);
    final bottomCenter = _addVertex(cx, yBottom, cz);
    for (var i = 0; i < sides; i++) {
      final next = (i + 1) % sides;
      _addQuad(
        topIndices[i],
        topIndices[next],
        topCenter,
        topCenter,
        slot,
      );
      _addQuad(
        bottomIndices[next],
        bottomIndices[i],
        bottomCenter,
        bottomCenter,
        slot,
      );
    }
  }

  ProceduralMeshPrimitive build() {
    return ProceduralMeshPrimitive(
      vertices: Float32List.fromList(_verts),
      faceIndices: Int32List.fromList(_faces),
      faceNormals: Float32List.fromList(_normals),
      faceSlots: Uint8List.fromList(_slots),
    );
  }
}
