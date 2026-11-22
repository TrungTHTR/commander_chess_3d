import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import '../../models/faction_model.dart';
import '../../models/piece_model.dart';

/// Material slots matching `docs/BLENDER_ASSET_CONTRACT.md` §4 plus mirror-match
/// [teamRing] and national [factionUniform] / [factionEmblem] slots.
///
/// Indices `0..4` preserve exact backwards compatibility with starter meshes.
enum ProceduralMaterialSlot {
  factionPrimary,
  factionAccent,
  basePedestal,
  neutralMetal,
  heroicEmissive,
  teamRing,
  factionUniform,
  factionEmblem,
}

/// Canonical sub-part tags matching `docs/BLENDER_ASSET_CONTRACT.md` §3 node names.
enum MeshPartTag {
  basePedestal('base_pedestal'),
  bodyHull('body_hull'),
  turret('turret'),
  barrel('barrel'),
  wingRotor('wing_rotor'),
  insigniaStar('insignia_star');

  const MeshPartTag(this.nodeName);
  final String nodeName;
}

/// Pre-baked low-poly mesh primitive with flat vertex buffer, quad/tri faces,
/// sub-part tags, and carrier passenger sockets.
final class ProceduralMeshPrimitive {
  ProceduralMeshPrimitive({
    required this.vertices,
    required this.faceIndices,
    required this.faceNormals,
    required this.faceSlots,
    Uint8List? facePartTags,
    List<Vector3>? passengerSockets,
    Map<MeshPartTag, Vector3>? partPivots,
  }) : facePartTags =
           facePartTags ??
           Uint8List.fromList(
             List<int>.filled(faceSlots.length, MeshPartTag.bodyHull.index),
           ),
       passengerSockets = List<Vector3>.unmodifiable(
         passengerSockets ?? const <Vector3>[],
       ),
       partPivots = Map<MeshPartTag, Vector3>.unmodifiable(
         partPivots ?? const <MeshPartTag, Vector3>{},
       );

  /// Flat XYZ vertex coordinates `[x0, y0, z0, x1, y1, z1, ...]` in local
  /// piece space `[-0.425, +0.425] × [0.0, +1.20] × [-0.425, +0.425]`.
  final Float32List vertices;

  /// Quad vertex index tuples `[i0, i1, i2, i3, ...]` (`4` indices per face;
  /// triangles repeat `i3 == i2`).
  final Int32List faceIndices;

  /// Outward local-space unit normals `[nx, ny, nz, ...]` (`3` floats per face).
  final Float32List faceNormals;

  /// [ProceduralMaterialSlot.index] per face.
  final Uint8List faceSlots;

  /// [MeshPartTag.index] per face.
  final Uint8List facePartTags;

  /// Local-space passenger socket positions (`socket_passenger_0`, `1`).
  final List<Vector3> passengerSockets;

  /// Local-space rotation pivots per [MeshPartTag].
  final Map<MeshPartTag, Vector3> partPivots;

  int get faceCount => faceSlots.length;

  /// Total triangle count (1 for `i3 == i2`, 2 for quads `i3 != i2`).
  int get triangleCount {
    var tris = 0;
    for (var f = 0; f < faceSlots.length; f++) {
      final base = f * 4;
      tris += faceIndices[base + 2] == faceIndices[base + 3] ? 1 : 2;
    }
    return tris;
  }

  MeshPartTag partTagForFace(int faceIndex) {
    if (faceIndex < 0 || faceIndex >= facePartTags.length) {
      return MeshPartTag.bodyHull;
    }
    final idx = facePartTags[faceIndex];
    if (idx < 0 || idx >= MeshPartTag.values.length) {
      return MeshPartTag.bodyHull;
    }
    return MeshPartTag.values[idx];
  }
}

/// Pure-Dart procedural 3D silhouette builder producing 121 distinct national
/// unit meshes (`11 FactionId × 11 PieceType`) strictly within
/// `[-0.425, +0.425] × [0.0, +1.20] × [-0.425, +0.425]` and `[250, 500]` tris.
abstract final class FactionUnitMeshBuilder {
  static const double maxHalfExtentXZ = 0.42;
  static const double maxHeightY = 1.18;

  static ProceduralMeshPrimitive build(FactionId faction, PieceType type) {
    final b = _MeshBuilder();
    switch (type) {
      case PieceType.commander:
        _buildCommander(b, faction);
      case PieceType.headquarters:
        _buildHeadquarters(b, faction);
      case PieceType.infantry:
        _buildInfantry(b, faction);
      case PieceType.militia:
        _buildMilitia(b, faction);
      case PieceType.engineer:
        _buildEngineer(b, faction);
      case PieceType.tank:
        _buildTank(b, faction);
      case PieceType.artillery:
        _buildArtillery(b, faction);
      case PieceType.antiAircraft:
        _buildAntiAircraft(b, faction);
      case PieceType.missile:
        _buildMissile(b, faction);
      case PieceType.airForce:
        _buildAirForce(b, faction);
      case PieceType.navy:
        _buildNavy(b, faction);
    }

    final mesh = b.build();
    assert(
      mesh.triangleCount >= 250 && mesh.triangleCount <= 500,
      'Mesh ${faction.code}.${type.snakeCaseName} has ${mesh.triangleCount} tris (expected 250..500)',
    );
    return mesh;
  }

  static void _addPedestal(
    _MeshBuilder b, {
    double radius = 0.35,
    double baseH = 0.055,
    double ringH = 0.04,
  }) {
    b.addCylinder(
      0,
      0.0,
      0,
      radius,
      baseH,
      radius,
      ProceduralMaterialSlot.basePedestal,
      sides: 12,
      topScaleX: 0.96,
      topScaleZ: 0.96,
      part: MeshPartTag.basePedestal,
    );
    b.addCylinder(
      0,
      baseH,
      0,
      radius * 0.96,
      ringH,
      radius * 0.96,
      ProceduralMaterialSlot.teamRing,
      sides: 12,
      topScaleX: 0.89,
      topScaleZ: 0.89,
      part: MeshPartTag.basePedestal,
    );
  }

  // ---------------------------------------------------------------------------
  // 1. COMMANDER (11 distinct national officers)
  // ---------------------------------------------------------------------------
  static void _buildCommander(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.35, baseH: 0.055, ringH: 0.042);

    // Boots & stance.
    b.addBox(-0.08, 0.097, 0.01, 0.052, 0.08, 0.075, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0.08, 0.097, 0.01, 0.052, 0.08, 0.075, ProceduralMaterialSlot.neutralMetal);
    b.addBox(-0.075, 0.177, 0.0, 0.048, 0.18, 0.055, ProceduralMaterialSlot.factionUniform);
    b.addBox(0.075, 0.177, 0.0, 0.048, 0.18, 0.055, ProceduralMaterialSlot.factionUniform);

    // Tunic / greatcoat torso varied by faction.
    final coatDrop = faction == FactionId.sovietUnion ? 0.22 : 0.34;
    final coatW = switch (faction) {
      FactionId.sovietUnion => 0.18,
      FactionId.usa => 0.165,
      FactionId.vietnam => 0.155,
      FactionId.unitedKingdom => 0.16,
      FactionId.germany => 0.17,
      FactionId.france => 0.155,
      FactionId.china => 0.165,
      FactionId.japan => 0.158,
      FactionId.southKorea => 0.162,
      FactionId.india => 0.168,
      FactionId.israel => 0.16,
    };
    b.addBox(
      0,
      coatDrop,
      0,
      coatW,
      0.66 - coatDrop,
      0.115,
      ProceduralMaterialSlot.factionPrimary,
      topScaleX: 1.08,
      topScaleZ: 0.96,
    );
    // Belt + buckle + teamRing chest sash/flash.
    b.addBox(0, 0.36, 0, coatW + 0.01, 0.045, 0.122, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0, 0.56, 0.12, 0.07, 0.05, 0.018, ProceduralMaterialSlot.teamRing);

    // Epaulettes + arms.
    b.addBox(-coatW - 0.025, 0.58, 0.0, 0.055, 0.045, 0.07, ProceduralMaterialSlot.factionAccent);
    b.addBox(coatW + 0.025, 0.58, 0.0, 0.055, 0.045, 0.07, ProceduralMaterialSlot.factionAccent);
    b.addRotatedBox(-coatW - 0.04, 0.46, 0.03, 0.042, 0.13, 0.045, -0.22, 0, 0.12, ProceduralMaterialSlot.factionUniform);
    b.addRotatedBox(coatW + 0.04, 0.47, 0.05, 0.042, 0.13, 0.045, -0.35, 0, -0.10, ProceduralMaterialSlot.factionUniform);

    // Command accessory (baton / binoculars / tablet / map case).
    switch (faction) {
      case FactionId.usa:
      case FactionId.china:
      case FactionId.southKorea:
        // Encrypted handset + antenna.
        b.addBox(coatW + 0.05, 0.52, 0.10, 0.028, 0.06, 0.024, ProceduralMaterialSlot.neutralMetal);
        b.addBox(coatW + 0.06, 0.58, 0.10, 0.009, 0.11, 0.009, ProceduralMaterialSlot.factionAccent);
      case FactionId.vietnam:
      case FactionId.israel:
        // Field binoculars / map pouch.
        b.addBox(0.0, 0.50, 0.13, 0.065, 0.045, 0.04, ProceduralMaterialSlot.neutralMetal);
        b.addBox(-0.14, 0.34, 0.08, 0.045, 0.09, 0.065, ProceduralMaterialSlot.factionAccent);
      case FactionId.unitedKingdom:
      case FactionId.germany:
      case FactionId.india:
        // Marshal swagger baton + Sam Browne strap.
        b.addRotatedBox(coatW + 0.05, 0.48, 0.14, 0.016, 0.14, 0.016, 0.65, 0, 0, ProceduralMaterialSlot.factionAccent);
        b.addRotatedBox(0, 0.51, 0.12, 0.16, 0.022, 0.015, 0, 0, 0.58, ProceduralMaterialSlot.neutralMetal);
      case FactionId.sovietUnion:
      case FactionId.france:
      case FactionId.japan:
        // Map tablet / officer saber hilt.
        b.addRotatedBox(-coatW - 0.04, 0.40, 0.11, 0.025, 0.10, 0.07, -0.3, 0.2, 0, ProceduralMaterialSlot.factionAccent);
        b.addBox(0.11, 0.44, 0.12, 0.05, 0.06, 0.025, ProceduralMaterialSlot.factionEmblem);
    }

    // Neck & head.
    b.addCylinder(0, 0.66, 0, 0.105, 0.14, 0.105, ProceduralMaterialSlot.factionUniform, sides: 8);

    // Distinct national officer headwear + crest (`insigniaStar`).
    b.setPivot(MeshPartTag.insigniaStar, 0.0, 0.88, 0.0);
    switch (faction) {
      case FactionId.usa:
        // Peaked garrison cap + gold visor + 4-star crown crest.
        b.addCylinder(0, 0.79, 0, 0.13, 0.09, 0.14, ProceduralMaterialSlot.factionUniform, sides: 8, topScaleX: 1.18, topScaleZ: 1.18);
        b.addBox(0, 0.78, 0.13, 0.10, 0.022, 0.055, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.89, 0.02, 0.11, 0.05, 0.035, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);
      case FactionId.vietnam:
        // Pith helmet (`mũ cối`) + front gold star emblem.
        b.addCone(0, 0.79, 0, 0.175, 0.125, 0.175, ProceduralMaterialSlot.factionPrimary, sides: 10);
        b.addBox(0, 0.84, 0.12, 0.042, 0.042, 0.025, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);
        b.addRotatedBox(0, 0.96, 0, 0.045, 0.045, 0.025, 0, 0, 0.785, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);
      case FactionId.sovietUnion:
        // Tall fur ushanka + front red-gold star crest.
        b.addBox(0, 0.78, -0.01, 0.145, 0.15, 0.135, ProceduralMaterialSlot.neutralMetal, topScaleX: 0.92, topScaleZ: 0.92);
        b.addBox(-0.14, 0.73, 0.0, 0.025, 0.11, 0.08, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.14, 0.73, 0.0, 0.025, 0.11, 0.08, ProceduralMaterialSlot.neutralMetal);
        b.addRotatedBox(0, 0.88, 0.13, 0.042, 0.042, 0.022, 0, 0, 0.785, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.insigniaStar);
      case FactionId.unitedKingdom:
        // Crimson-banded officer beret + cap badge.
        b.addRotatedBox(0.025, 0.83, 0, 0.15, 0.05, 0.14, 0, 0, 0.24, ProceduralMaterialSlot.factionEmblem);
        b.addBox(-0.03, 0.85, 0.12, 0.036, 0.045, 0.024, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);
      case FactionId.germany:
        // High-crown silver-piped visor cap + iron cross crest.
        b.addCylinder(0, 0.79, -0.01, 0.13, 0.11, 0.14, ProceduralMaterialSlot.factionAccent, sides: 8, topScaleX: 1.22, topScaleZ: 1.20);
        b.addBox(0, 0.78, 0.13, 0.105, 0.024, 0.055, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.88, 0.13, 0.026, 0.07, 0.02, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);
        b.addBox(0, 0.88, 0.13, 0.07, 0.026, 0.02, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);
      case FactionId.france:
        // Tall cylindrical `képi` + gold braid band.
        b.addCylinder(0, 0.79, 0, 0.115, 0.13, 0.115, ProceduralMaterialSlot.factionEmblem, sides: 10, topScaleX: 0.94, topScaleZ: 0.94);
        b.addBox(0, 0.78, 0.11, 0.09, 0.02, 0.045, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.86, 0.11, 0.05, 0.035, 0.02, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);
      case FactionId.china:
        // Wide-brim PLA peaked cap + red star emblem.
        b.addCylinder(0, 0.79, 0, 0.135, 0.095, 0.145, ProceduralMaterialSlot.factionPrimary, sides: 8, topScaleX: 1.24, topScaleZ: 1.24);
        b.addBox(0, 0.78, 0.14, 0.11, 0.02, 0.055, ProceduralMaterialSlot.neutralMetal);
        b.addRotatedBox(0, 0.88, 0.14, 0.04, 0.04, 0.02, 0, 0, 0.785, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.insigniaStar);
      case FactionId.japan:
        // Structured JSDF visor cap + sakura crest.
        b.addCylinder(0, 0.79, 0, 0.125, 0.095, 0.135, ProceduralMaterialSlot.factionUniform, sides: 8, topScaleX: 1.15, topScaleZ: 1.15);
        b.addBox(0, 0.78, 0.125, 0.095, 0.02, 0.05, ProceduralMaterialSlot.neutralMetal);
        b.addCylinder(0, 0.87, 0.12, 0.032, 0.02, 0.032, ProceduralMaterialSlot.heroicEmissive, sides: 6, part: MeshPartTag.insigniaStar);
      case FactionId.southKorea:
        // ROK peaked visor cap + diamond star crest.
        b.addCylinder(0, 0.79, 0, 0.125, 0.10, 0.135, ProceduralMaterialSlot.factionEmblem, sides: 8, topScaleX: 1.14, topScaleZ: 1.14);
        b.addBox(0, 0.78, 0.125, 0.095, 0.02, 0.05, ProceduralMaterialSlot.neutralMetal);
        b.addRotatedBox(0, 0.89, 0.12, 0.038, 0.038, 0.02, 0, 0, 0.785, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);
      case FactionId.india:
        // Saffron-trimmed turban crest + ashoka finial.
        b.addCylinder(0, 0.78, 0, 0.145, 0.12, 0.145, ProceduralMaterialSlot.factionAccent, sides: 10, topScaleX: 0.90, topScaleZ: 0.90);
        b.addBox(0, 0.88, 0.11, 0.04, 0.08, 0.028, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);
      case FactionId.israel:
        // Draped asymmetric mitznefet command cover + crest.
        b.addCylinder(0.015, 0.77, -0.01, 0.165, 0.135, 0.155, ProceduralMaterialSlot.factionUniform, sides: 10, topScaleX: 0.85, topScaleZ: 0.88);
        b.addBox(-0.02, 0.86, 0.13, 0.045, 0.045, 0.024, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);
    }
  }

  // ---------------------------------------------------------------------------
  // 2. HEADQUARTERS (11 distinct bunkers / command shelters, capacity = 1)
  // ---------------------------------------------------------------------------
  static void _buildHeadquarters(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.39, baseH: 0.05, ringH: 0.04);
    b.addPassengerSocket(0.0, 0.56, 0.0);

    // Common concrete/earthen revetment corner bollards, blast door frame, and roof hatch (+84 tris).
    b.addBox(0, 0.09, 0, 0.35, 0.04, 0.33, ProceduralMaterialSlot.neutralMetal);
    b.addBox(-0.27, 0.13, 0.25, 0.045, 0.14, 0.045, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0.27, 0.13, 0.25, 0.045, 0.14, 0.045, ProceduralMaterialSlot.neutralMetal);
    b.addBox(-0.27, 0.13, -0.25, 0.045, 0.14, 0.045, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0.27, 0.13, -0.25, 0.045, 0.14, 0.045, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0, 0.13, 0.29, 0.08, 0.12, 0.03, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0, 0.44, 0.08, 0.08, 0.04, 0.08, ProceduralMaterialSlot.neutralMetal);

    switch (faction) {
      case FactionId.usa:
        // HESCO sandbag bastion + folding SATCOM dish.
        b.addBox(0, 0.09, 0, 0.33, 0.32, 0.30, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.84, topScaleZ: 0.84);
        for (final sx in const <double>[-0.22, 0.0, 0.22]) {
          b.addBox(sx, 0.41, 0.20, 0.09, 0.08, 0.06, ProceduralMaterialSlot.factionUniform);
          b.addBox(sx, 0.41, -0.20, 0.09, 0.08, 0.06, ProceduralMaterialSlot.factionUniform);
        }
        b.addBox(0, 0.41, 0, 0.22, 0.06, 0.18, ProceduralMaterialSlot.factionAccent);
        b.addBox(0, 0.28, 0.28, 0.12, 0.04, 0.02, ProceduralMaterialSlot.teamRing);
        b.setPivot(MeshPartTag.wingRotor, -0.10, 0.52, -0.06);
        b.addCylinder(-0.10, 0.47, -0.06, 0.028, 0.16, 0.028, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addCone(-0.10, 0.63, -0.06, 0.13, 0.09, 0.13, ProceduralMaterialSlot.factionAccent, sides: 10, part: MeshPartTag.wingRotor);
        b.addBox(0.14, 0.47, -0.12, 0.015, 0.42, 0.015, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.wingRotor);

      case FactionId.vietnam:
        // Camouflaged timber & earthen berm bunker + HF radio mast.
        b.addBox(0, 0.09, 0, 0.35, 0.26, 0.33, ProceduralMaterialSlot.factionUniform, topScaleX: 0.78, topScaleZ: 0.78);
        b.addBox(0, 0.35, 0, 0.27, 0.10, 0.25, ProceduralMaterialSlot.factionPrimary);
        for (final lz in const <double>[-0.18, -0.06, 0.06, 0.18]) {
          b.addBox(0, 0.45, lz, 0.28, 0.045, 0.035, ProceduralMaterialSlot.factionAccent);
        }
        b.addBox(0, 0.24, 0.31, 0.10, 0.05, 0.02, ProceduralMaterialSlot.teamRing);
        b.setPivot(MeshPartTag.wingRotor, 0.12, 0.52, -0.08);
        b.addCylinder(0.12, 0.49, -0.08, 0.024, 0.46, 0.024, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addBox(0.12, 0.88, -0.08, 0.12, 0.025, 0.02, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);

      case FactionId.sovietUnion:
        // Octagonal concrete pillbox + armored cupola + whip array.
        b.addCylinder(0, 0.09, 0, 0.34, 0.34, 0.34, ProceduralMaterialSlot.factionPrimary, sides: 8, topScaleX: 0.84, topScaleZ: 0.84);
        b.addCylinder(0, 0.43, 0, 0.22, 0.10, 0.22, ProceduralMaterialSlot.neutralMetal, sides: 8);
        b.addBox(0, 0.26, 0.30, 0.14, 0.05, 0.03, ProceduralMaterialSlot.teamRing);
        b.addBox(-0.18, 0.32, 0.24, 0.06, 0.04, 0.04, ProceduralMaterialSlot.factionAccent);
        b.addBox(0.18, 0.32, 0.24, 0.06, 0.04, 0.04, ProceduralMaterialSlot.factionAccent);
        b.setPivot(MeshPartTag.wingRotor, 0.0, 0.53, -0.10);
        b.addCylinder(0, 0.53, -0.10, 0.022, 0.38, 0.022, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.82, -0.10, 0.16, 0.022, 0.022, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);

      case FactionId.unitedKingdom:
        // Twin blast-walled command shelter + Bowman mast.
        b.addBox(0, 0.09, 0, 0.30, 0.32, 0.26, ProceduralMaterialSlot.factionPrimary);
        b.addBox(-0.31, 0.09, 0, 0.045, 0.38, 0.31, ProceduralMaterialSlot.factionUniform);
        b.addBox(0.31, 0.09, 0, 0.045, 0.38, 0.31, ProceduralMaterialSlot.factionUniform);
        b.addBox(0, 0.41, 0, 0.26, 0.08, 0.22, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.28, 0.27, 0.12, 0.05, 0.02, ProceduralMaterialSlot.teamRing);
        b.setPivot(MeshPartTag.wingRotor, 0.14, 0.52, -0.06);
        b.addCylinder(0.14, 0.49, -0.06, 0.024, 0.40, 0.024, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addBox(0.14, 0.78, -0.06, 0.10, 0.06, 0.02, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.germany:
        // Angular steel Gefechtsstand shelter + NBC louvers + telescopic mast.
        b.addExtrudedPolygon(
          const [(x: -0.32, z: 0.24), (x: 0.32, z: 0.24), (x: 0.24, z: -0.28), (x: -0.24, z: -0.28)],
          0.09,
          0.42,
          ProceduralMaterialSlot.factionPrimary,
          topScale: 0.88,
        );
        b.addBox(-0.18, 0.22, 0.24, 0.08, 0.14, 0.03, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.18, 0.22, 0.24, 0.08, 0.14, 0.03, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.42, 0, 0.22, 0.07, 0.20, ProceduralMaterialSlot.factionAccent);
        b.addBox(0, 0.30, 0.24, 0.08, 0.05, 0.02, ProceduralMaterialSlot.teamRing);
        b.setPivot(MeshPartTag.wingRotor, -0.12, 0.50, -0.08);
        b.addCylinder(-0.12, 0.49, -0.08, 0.024, 0.42, 0.024, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addBox(-0.12, 0.85, -0.08, 0.11, 0.035, 0.035, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.france:
        // Vaulted-arch bunker + Syracuse dish.
        b.addBox(0, 0.09, 0, 0.33, 0.22, 0.30, ProceduralMaterialSlot.factionPrimary);
        b.addBox(0, 0.31, 0, 0.28, 0.15, 0.27, ProceduralMaterialSlot.factionUniform, topScaleX: 0.65, topScaleZ: 0.85);
        b.addBox(0, 0.46, 0, 0.18, 0.06, 0.18, ProceduralMaterialSlot.factionAccent);
        b.addBox(0, 0.20, 0.31, 0.12, 0.05, 0.02, ProceduralMaterialSlot.teamRing);
        b.addBox(-0.16, 0.22, 0.30, 0.07, 0.08, 0.025, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.16, 0.22, 0.30, 0.07, 0.08, 0.025, ProceduralMaterialSlot.neutralMetal);
        b.setPivot(MeshPartTag.wingRotor, 0.08, 0.54, -0.06);
        b.addCylinder(0.08, 0.52, -0.06, 0.022, 0.20, 0.022, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addCone(0.08, 0.70, -0.06, 0.12, 0.09, 0.12, ProceduralMaterialSlot.factionEmblem, sides: 8, part: MeshPartTag.wingRotor);

      case FactionId.china:
        // Hardened C4ISR bunker + geodesic radome.
        b.addBox(0, 0.09, 0, 0.34, 0.30, 0.31, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.82, topScaleZ: 0.82);
        b.addBox(0, 0.39, 0, 0.24, 0.08, 0.22, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.24, 0.30, 0.13, 0.05, 0.02, ProceduralMaterialSlot.teamRing);
        b.setPivot(MeshPartTag.wingRotor, 0.0, 0.50, -0.04);
        b.addCylinder(0, 0.47, -0.04, 0.14, 0.16, 0.14, ProceduralMaterialSlot.factionAccent, sides: 10, topScaleX: 0.72, topScaleZ: 0.72, part: MeshPartTag.wingRotor);
        b.addCone(0, 0.63, -0.04, 0.10, 0.09, 0.10, ProceduralMaterialSlot.factionEmblem, sides: 10, part: MeshPartTag.wingRotor);
        b.addBox(-0.18, 0.47, -0.12, 0.015, 0.34, 0.015, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.wingRotor);

      case FactionId.japan:
        // Stepped coastal concrete bunker + shutter embrasures.
        b.addBox(0, 0.09, 0, 0.36, 0.17, 0.33, ProceduralMaterialSlot.factionPrimary);
        b.addBox(0, 0.26, 0, 0.28, 0.15, 0.26, ProceduralMaterialSlot.factionUniform);
        b.addBox(0, 0.41, 0, 0.20, 0.09, 0.19, ProceduralMaterialSlot.factionAccent);
        b.addBox(0, 0.30, 0.27, 0.14, 0.045, 0.02, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.18, 0.34, 0.12, 0.045, 0.02, ProceduralMaterialSlot.teamRing);
        b.setPivot(MeshPartTag.wingRotor, 0.12, 0.52, -0.06);
        b.addCylinder(0.12, 0.50, -0.06, 0.022, 0.32, 0.022, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addBox(0.12, 0.74, -0.06, 0.13, 0.03, 0.025, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.southKorea:
        // Sloped DMZ bunker + heavy blast overhang + microwave dish.
        b.addBox(0, 0.09, -0.02, 0.34, 0.31, 0.28, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.80, topScaleZ: 0.78);
        b.addBox(0, 0.40, 0.03, 0.29, 0.08, 0.29, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.24, 0.27, 0.13, 0.05, 0.025, ProceduralMaterialSlot.teamRing);
        b.setPivot(MeshPartTag.wingRotor, -0.10, 0.50, -0.08);
        b.addCylinder(-0.10, 0.48, -0.08, 0.025, 0.24, 0.025, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addCylinder(-0.10, 0.70, -0.08, 0.11, 0.06, 0.04, ProceduralMaterialSlot.factionAccent, sides: 8, part: MeshPartTag.wingRotor);

      case FactionId.india:
        // Buttressed sandstone bastion + high-altitude SATCOM mast.
        b.addBox(0, 0.09, 0, 0.31, 0.34, 0.30, ProceduralMaterialSlot.factionUniform);
        for (final bx in const <double>[-0.31, 0.31]) {
          b.addBox(bx, 0.09, 0.18, 0.055, 0.30, 0.08, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.7);
          b.addBox(bx, 0.09, -0.18, 0.055, 0.30, 0.08, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.7);
        }
        b.addBox(0, 0.43, 0, 0.24, 0.07, 0.22, ProceduralMaterialSlot.factionAccent);
        b.addBox(0, 0.26, 0.31, 0.12, 0.05, 0.02, ProceduralMaterialSlot.teamRing);
        b.setPivot(MeshPartTag.wingRotor, 0.0, 0.52, -0.10);
        b.addCylinder(0, 0.50, -0.10, 0.024, 0.36, 0.024, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addCone(0, 0.80, -0.10, 0.11, 0.08, 0.11, ProceduralMaterialSlot.factionAccent, sides: 8, part: MeshPartTag.wingRotor);

      case FactionId.israel:
        // Low-profile concrete dome shielded by gabion walls.
        b.addBox(-0.29, 0.09, 0, 0.055, 0.26, 0.30, ProceduralMaterialSlot.factionUniform);
        b.addBox(0.29, 0.09, 0, 0.055, 0.26, 0.30, ProceduralMaterialSlot.factionUniform);
        b.addBox(0, 0.09, -0.27, 0.28, 0.26, 0.055, ProceduralMaterialSlot.factionUniform);
        b.addCylinder(0, 0.09, 0.02, 0.25, 0.28, 0.25, ProceduralMaterialSlot.factionPrimary, sides: 10, topScaleX: 0.72, topScaleZ: 0.72);
        b.addBox(0, 0.37, 0.02, 0.16, 0.07, 0.16, ProceduralMaterialSlot.factionAccent);
        b.addBox(0, 0.20, 0.27, 0.11, 0.045, 0.02, ProceduralMaterialSlot.teamRing);
        b.setPivot(MeshPartTag.wingRotor, 0.14, 0.48, -0.12);
        b.addCylinder(0.14, 0.44, -0.12, 0.02, 0.36, 0.02, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addBox(0.14, 0.74, -0.12, 0.10, 0.05, 0.02, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);
    }
  }

  // ---------------------------------------------------------------------------
  // 3. INFANTRY (11 distinct national riflemen)
  // ---------------------------------------------------------------------------
  static void _buildInfantry(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.32, baseH: 0.05, ringH: 0.038);

    // Boots & legs.
    b.addBox(-0.075, 0.088, 0.01, 0.048, 0.075, 0.07, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0.075, 0.088, 0.01, 0.048, 0.075, 0.07, ProceduralMaterialSlot.neutralMetal);
    b.addBox(-0.07, 0.163, 0.0, 0.045, 0.18, 0.052, ProceduralMaterialSlot.factionUniform);
    b.addBox(0.07, 0.163, 0.0, 0.045, 0.18, 0.052, ProceduralMaterialSlot.factionUniform);

    // Plate carrier / tactical chest rig + backpack.
    b.addBox(0, 0.34, 0, 0.145, 0.27, 0.105, ProceduralMaterialSlot.factionPrimary, topScaleX: 1.05, topScaleZ: 0.96);
    b.addBox(0, 0.38, -0.11, 0.11, 0.20, 0.055, ProceduralMaterialSlot.factionUniform);
    b.addBox(0, 0.42, 0.11, 0.10, 0.13, 0.03, ProceduralMaterialSlot.factionAccent);
    b.addBox(0, 0.56, 0.11, 0.05, 0.045, 0.018, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);

    // Arms + teamRing shoulder patch.
    b.addBox(-0.165, 0.45, 0.03, 0.038, 0.14, 0.045, ProceduralMaterialSlot.factionUniform);
    b.addBox(0.165, 0.45, 0.03, 0.038, 0.14, 0.045, ProceduralMaterialSlot.factionUniform);
    b.addBox(-0.185, 0.53, 0.03, 0.025, 0.045, 0.04, ProceduralMaterialSlot.teamRing);

    // Head.
    b.addCylinder(0, 0.61, 0, 0.095, 0.13, 0.095, ProceduralMaterialSlot.factionUniform, sides: 8);

    // National helmet silhouette.
    switch (faction) {
      case FactionId.usa:
        // ACH helmet + NVG shroud.
        b.addCylinder(0, 0.72, -0.01, 0.125, 0.12, 0.13, ProceduralMaterialSlot.factionPrimary, sides: 10, topScaleX: 0.85, topScaleZ: 0.85);
        b.addBox(0, 0.78, 0.12, 0.035, 0.04, 0.03, ProceduralMaterialSlot.neutralMetal);
      case FactionId.vietnam:
        // Classic pith helmet (`mũ cối`) + foliage band.
        b.addCone(0, 0.72, 0, 0.165, 0.12, 0.165, ProceduralMaterialSlot.factionPrimary, sides: 10);
        b.addBox(0, 0.74, 0.11, 0.035, 0.035, 0.02, ProceduralMaterialSlot.factionEmblem);
      case FactionId.sovietUnion:
        // SSh-68 flared steel dome helmet.
        b.addCylinder(0, 0.72, 0, 0.135, 0.115, 0.135, ProceduralMaterialSlot.neutralMetal, sides: 10, topScaleX: 0.76, topScaleZ: 0.76);
      case FactionId.unitedKingdom:
        // Mk 7 scrim-netted helmet.
        b.addCylinder(0, 0.72, 0, 0.13, 0.12, 0.13, ProceduralMaterialSlot.factionPrimary, sides: 10, topScaleX: 0.84, topScaleZ: 0.84);
        b.addBox(0, 0.83, 0, 0.09, 0.03, 0.09, ProceduralMaterialSlot.factionUniform);
      case FactionId.germany:
        // M92 Gefechtshelm + tactical goggles.
        b.addCylinder(0, 0.72, -0.01, 0.128, 0.12, 0.13, ProceduralMaterialSlot.factionPrimary, sides: 10, topScaleX: 0.84, topScaleZ: 0.84);
        b.addBox(0, 0.73, 0.12, 0.09, 0.038, 0.028, ProceduralMaterialSlot.factionAccent);
      case FactionId.france:
        // FELIN helmet + digital visor monocle.
        b.addCylinder(0, 0.72, 0, 0.125, 0.12, 0.128, ProceduralMaterialSlot.factionPrimary, sides: 10, topScaleX: 0.86, topScaleZ: 0.86);
        b.addBox(0.055, 0.69, 0.12, 0.045, 0.04, 0.025, ProceduralMaterialSlot.factionEmblem);
      case FactionId.china:
        // QGF-11 aramid helmet + rail mount + twin chest pouches.
        b.addCylinder(0, 0.72, 0, 0.128, 0.12, 0.128, ProceduralMaterialSlot.factionPrimary, sides: 10, topScaleX: 0.86, topScaleZ: 0.86);
        b.addBox(-0.11, 0.76, 0.03, 0.02, 0.03, 0.06, ProceduralMaterialSlot.neutralMetal);
        b.addBox(-0.06, 0.36, 0.13, 0.035, 0.07, 0.025, ProceduralMaterialSlot.factionAccent);
        b.addBox(0.06, 0.36, 0.13, 0.035, 0.07, 0.025, ProceduralMaterialSlot.factionAccent);
      case FactionId.japan:
        // Type 88 Kevlar helmet + neck flap + large field rucksack.
        b.addCylinder(0, 0.72, 0, 0.126, 0.115, 0.128, ProceduralMaterialSlot.factionPrimary, sides: 10, topScaleX: 0.88, topScaleZ: 0.88);
        b.addBox(0, 0.67, -0.12, 0.095, 0.07, 0.03, ProceduralMaterialSlot.factionUniform);
        b.addBox(0, 0.35, -0.14, 0.125, 0.23, 0.075, ProceduralMaterialSlot.factionAccent);
      case FactionId.southKorea:
        // Granite-B K-helmet + NVG bracket + shoulder comms antenna.
        b.addCylinder(0, 0.72, 0, 0.124, 0.118, 0.126, ProceduralMaterialSlot.factionPrimary, sides: 10, topScaleX: 0.85, topScaleZ: 0.85);
        b.addBox(0, 0.76, 0.125, 0.048, 0.032, 0.022, ProceduralMaterialSlot.factionAccent);
        b.addBox(-0.13, 0.56, -0.09, 0.012, 0.24, 0.012, ProceduralMaterialSlot.neutralMetal);
      case FactionId.india:
        // Patka steel-band turban helmet + hip kukri scabbard.
        b.addCylinder(0, 0.71, 0, 0.145, 0.12, 0.145, ProceduralMaterialSlot.factionUniform, sides: 10);
        b.addBox(0, 0.74, 0.125, 0.115, 0.048, 0.032, ProceduralMaterialSlot.neutralMetal);
        b.addRotatedBox(-0.16, 0.31, -0.03, 0.022, 0.11, 0.025, -0.45, 0, 0.15, ProceduralMaterialSlot.factionAccent);
      case FactionId.israel:
        // Iconic bulbous mitznefet mesh cover.
        b.addCylinder(0.015, 0.71, -0.01, 0.175, 0.145, 0.165, ProceduralMaterialSlot.factionUniform, sides: 10, topScaleX: 0.78, topScaleZ: 0.84);
    }

    // Distinct national infantry rifle (`barrel`).
    b.setPivot(MeshPartTag.barrel, 0.12, 0.45, 0.14);
    switch (faction) {
      case FactionId.usa:
      case FactionId.france:
        // M4A1 / HK416F carbine + ACOG optic.
        b.addBox(0.11, 0.44, 0.15, 0.024, 0.042, 0.15, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(0.11, 0.49, 0.12, 0.018, 0.026, 0.055, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addBox(0.11, 0.37, 0.16, 0.016, 0.06, 0.024, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        if (faction == FactionId.france) {
          // FELIN comms battery pack on rear hip.
          b.addBox(-0.08, 0.34, -0.14, 0.055, 0.09, 0.045, ProceduralMaterialSlot.factionEmblem);
        }
      case FactionId.vietnam:
      case FactionId.sovietUnion:
        // AKM / AK-74 with signature curved banana magazine.
        b.addBox(0.11, 0.44, 0.16, 0.024, 0.04, 0.17, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.11, 0.38, 0.18, 0.016, 0.055, 0.024, 0.35, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
      case FactionId.unitedKingdom:
      case FactionId.israel:
        // SA80A3 / Tavor X95 compact bullpup (rear magazine, tall optic).
        b.addBox(0.11, 0.44, 0.12, 0.026, 0.055, 0.125, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(0.11, 0.50, 0.12, 0.020, 0.030, 0.06, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
      case FactionId.germany:
        // HK G36 with tall integrated dual-optic carry handle.
        b.addBox(0.11, 0.44, 0.15, 0.024, 0.042, 0.16, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(0.11, 0.50, 0.13, 0.018, 0.042, 0.095, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
      case FactionId.china:
        // QBZ-191 compact assault rifle + drum/extended mag.
        b.addBox(0.11, 0.44, 0.14, 0.024, 0.042, 0.15, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(0.11, 0.37, 0.15, 0.022, 0.065, 0.028, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
      case FactionId.japan:
        // Howa Type 20 + folded bipod.
        b.addBox(0.11, 0.44, 0.17, 0.022, 0.04, 0.17, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(0.085, 0.40, 0.27, 0.012, 0.045, 0.018, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addBox(0.135, 0.40, 0.27, 0.012, 0.045, 0.018, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
      case FactionId.southKorea:
        // Daewoo K2C1 + angled foregrip + rail optic.
        b.addBox(0.11, 0.44, 0.16, 0.023, 0.04, 0.165, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.11, 0.40, 0.21, 0.016, 0.048, 0.020, -0.35, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
      case FactionId.india:
        // INSAS long-barrel rifle + bayonet lug.
        b.addBox(0.11, 0.44, 0.18, 0.022, 0.04, 0.19, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(0.11, 0.38, 0.16, 0.016, 0.058, 0.024, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
    }
  }

  // ---------------------------------------------------------------------------
  // 4. MILITIA (11 distinct irregular/reserve scouts)
  // ---------------------------------------------------------------------------
  static void _buildMilitia(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.30, baseH: 0.048, ringH: 0.036);

    // Boots & legs (leaner stance).
    b.addBox(-0.065, 0.084, 0.01, 0.042, 0.07, 0.062, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0.065, 0.084, 0.01, 0.042, 0.07, 0.062, ProceduralMaterialSlot.neutralMetal);
    b.addBox(-0.062, 0.154, 0.0, 0.040, 0.17, 0.045, ProceduralMaterialSlot.factionUniform);
    b.addBox(0.062, 0.154, 0.0, 0.040, 0.17, 0.045, ProceduralMaterialSlot.factionUniform);

    // Lean tunic + bandolier + teamRing armband.
    b.addBox(0, 0.324, 0, 0.125, 0.26, 0.09, ProceduralMaterialSlot.factionPrimary, topScaleX: 1.04, topScaleZ: 0.96);
    b.addRotatedBox(0, 0.45, 0.095, 0.12, 0.022, 0.018, 0, 0, 0.55, ProceduralMaterialSlot.factionAccent);
    b.addBox(0, 0.52, 0.095, 0.045, 0.04, 0.015, ProceduralMaterialSlot.heroicEmissive, part: MeshPartTag.insigniaStar);

    b.addBox(-0.145, 0.43, 0.02, 0.034, 0.13, 0.04, ProceduralMaterialSlot.factionUniform);
    b.addBox(0.145, 0.43, 0.02, 0.034, 0.13, 0.04, ProceduralMaterialSlot.factionUniform);
    b.addBox(0.165, 0.50, 0.02, 0.022, 0.042, 0.036, ProceduralMaterialSlot.teamRing);

    // Head.
    b.addCylinder(0, 0.584, 0, 0.088, 0.12, 0.088, ProceduralMaterialSlot.factionUniform, sides: 8);

    // Distinct national militia headgear & field kit.
    switch (faction) {
      case FactionId.usa:
        // Wide boonie patrol hat + Marksman scope.
        b.addCylinder(0, 0.69, 0, 0.175, 0.025, 0.175, ProceduralMaterialSlot.factionUniform, sides: 10);
        b.addCylinder(0, 0.715, 0, 0.10, 0.075, 0.10, ProceduralMaterialSlot.factionPrimary, sides: 10);
        b.addBox(-0.10, 0.44, -0.07, 0.045, 0.12, 0.04, ProceduralMaterialSlot.factionUniform);
      case FactionId.southKorea:
        // Flapped boonie hat + radio whip.
        b.addCylinder(0, 0.69, 0, 0.165, 0.024, 0.165, ProceduralMaterialSlot.factionUniform, sides: 8);
        b.addCylinder(0, 0.714, 0, 0.095, 0.08, 0.095, ProceduralMaterialSlot.factionPrimary, sides: 8);
        b.addBox(-0.12, 0.50, -0.08, 0.012, 0.18, 0.012, ProceduralMaterialSlot.neutralMetal);
      case FactionId.israel:
        // Desert boonie + wide recon chest rig.
        b.addCylinder(0, 0.69, 0, 0.185, 0.028, 0.165, ProceduralMaterialSlot.factionUniform, sides: 10);
        b.addCylinder(0, 0.718, 0, 0.105, 0.07, 0.105, ProceduralMaterialSlot.factionPrimary, sides: 10);
        b.addBox(0, 0.36, 0.10, 0.09, 0.09, 0.03, ProceduralMaterialSlot.factionAccent);
      case FactionId.vietnam:
        // Iconic conical `nón lá` bamboo hat.
        b.addCone(0, 0.69, 0, 0.21, 0.14, 0.21, ProceduralMaterialSlot.factionAccent, sides: 12);
      case FactionId.sovietUnion:
        // Wedge `pilotka` garrison cap.
        b.addBox(0, 0.69, 0, 0.065, 0.08, 0.13, ProceduralMaterialSlot.factionUniform, topScaleX: 0.45);
        b.addBox(0, 0.73, 0.11, 0.025, 0.025, 0.018, ProceduralMaterialSlot.factionEmblem);
      case FactionId.unitedKingdom:
        // Maroon airborne/pathfinder beret.
        b.addRotatedBox(0.025, 0.72, 0, 0.14, 0.045, 0.13, 0, 0, 0.25, ProceduralMaterialSlot.factionEmblem);
      case FactionId.germany:
        // Peaked `Feldmütze` field cap + side patrol rucksack.
        b.addCylinder(0, 0.69, -0.01, 0.105, 0.08, 0.115, ProceduralMaterialSlot.factionPrimary, sides: 8);
        b.addBox(0, 0.69, 0.11, 0.08, 0.018, 0.045, ProceduralMaterialSlot.factionPrimary);
        b.addBox(-0.07, 0.36, -0.13, 0.09, 0.17, 0.06, ProceduralMaterialSlot.factionUniform);
      case FactionId.france:
        // Oversized alpine `tarte` beret.
        b.addCylinder(0.02, 0.70, 0, 0.18, 0.05, 0.17, ProceduralMaterialSlot.factionEmblem, sides: 10, topScaleX: 0.85, topScaleZ: 0.85);
      case FactionId.china:
        // Soft PLA patrol cap + chest pouch pack.
        b.addCylinder(0, 0.69, -0.01, 0.102, 0.072, 0.112, ProceduralMaterialSlot.factionPrimary, sides: 8);
        b.addBox(0, 0.69, 0.115, 0.075, 0.016, 0.04, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.36, -0.10, 0.08, 0.12, 0.04, ProceduralMaterialSlot.factionUniform);
      case FactionId.japan:
        // Structured JSDF work cap + visor ear flaps + waist canteen.
        b.addCylinder(0, 0.69, -0.01, 0.098, 0.082, 0.108, ProceduralMaterialSlot.factionUniform, sides: 10);
        b.addBox(0, 0.69, 0.115, 0.082, 0.018, 0.045, ProceduralMaterialSlot.neutralMetal);
        b.addBox(-0.105, 0.65, -0.02, 0.018, 0.05, 0.045, ProceduralMaterialSlot.factionUniform);
        b.addBox(0.105, 0.65, -0.02, 0.018, 0.05, 0.045, ProceduralMaterialSlot.factionUniform);
        b.addBox(0.11, 0.31, -0.05, 0.038, 0.075, 0.045, ProceduralMaterialSlot.factionAccent);
      case FactionId.india:
        // Upturned Gorkha wide slouch hat.
        b.addRotatedBox(0, 0.70, 0, 0.17, 0.02, 0.15, 0, 0, -0.22, ProceduralMaterialSlot.factionUniform);
        b.addCylinder(0, 0.71, 0, 0.095, 0.08, 0.095, ProceduralMaterialSlot.factionPrimary, sides: 8);
    }

    // Militia carbine / SMG / drum-mag weapon (`barrel`).
    b.setPivot(MeshPartTag.barrel, 0.11, 0.43, 0.12);
    if (faction == FactionId.sovietUnion) {
      // PPSh-41 with round drum magazine.
      b.addRotatedBox(0.11, 0.43, 0.12, 0.022, 0.036, 0.15, -0.15, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
      b.addCylinder(0.11, 0.35, 0.13, 0.045, 0.055, 0.045, ProceduralMaterialSlot.neutralMetal, sides: 8, part: MeshPartTag.barrel);
    } else {
      b.addRotatedBox(0.11, 0.43, 0.12, 0.022, 0.036, 0.16, -0.20, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
      b.addBox(0.11, 0.37, 0.13, 0.015, 0.048, 0.022, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
    }
  }

  // ---------------------------------------------------------------------------
  // 5. ENGINEER (11 distinct CEVs / bridging rigs, capacity = 1)
  // ---------------------------------------------------------------------------
  static void _buildEngineer(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.37, baseH: 0.05, ringH: 0.038);
    b.addPassengerSocket(0.0, 0.51, -0.04);

    final isWheeled = faction == FactionId.vietnam || faction == FactionId.india;

    if (isWheeled) {
      // 6x6 or 8x8 bridge truck.
      final wheelZs = faction == FactionId.india
          ? const <double>[0.24, 0.08, -0.08, -0.24]
          : const <double>[0.22, 0.0, -0.22];
      for (final wz in wheelZs) {
        b.addBox(-0.22, 0.09, wz, 0.042, 0.11, 0.055, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.22, 0.09, wz, 0.042, 0.11, 0.055, ProceduralMaterialSlot.neutralMetal);
      }
      // Armored cab + chassis bed + mudguards + roof beacons + rear tow hooks (+60 tris).
      b.addBox(0, 0.15, -0.02, 0.21, 0.12, 0.31, ProceduralMaterialSlot.neutralMetal);
      b.addBox(0, 0.27, 0.20, 0.19, 0.17, 0.11, ProceduralMaterialSlot.factionPrimary);
      b.addBox(0, 0.38, 0.29, 0.15, 0.05, 0.025, ProceduralMaterialSlot.factionAccent);
      b.addBox(-0.14, 0.44, 0.20, 0.04, 0.03, 0.04, ProceduralMaterialSlot.factionAccent);
      b.addBox(0.14, 0.44, 0.20, 0.04, 0.03, 0.04, ProceduralMaterialSlot.factionAccent);
      b.addBox(-0.18, 0.16, 0.32, 0.04, 0.04, 0.03, ProceduralMaterialSlot.neutralMetal);
      b.addBox(0.18, 0.16, 0.32, 0.04, 0.04, 0.03, ProceduralMaterialSlot.neutralMetal);
      b.addBox(0, 0.21, -0.33, 0.14, 0.05, 0.02, ProceduralMaterialSlot.teamRing);

      // Pontoon / multi-span scissor bridge (`barrel` + `turret`).
      b.setPivot(MeshPartTag.turret, 0, 0.36, -0.04);
      b.setPivot(MeshPartTag.barrel, 0, 0.46, 0.02);
      if (faction == FactionId.vietnam) {
        // Folded PMP steel pontoon deck sections.
        b.addBox(-0.13, 0.27, -0.08, 0.11, 0.18, 0.21, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addBox(0.13, 0.27, -0.08, 0.11, 0.18, 0.21, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addBox(0, 0.45, -0.08, 0.24, 0.06, 0.18, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.turret);
      } else {
        // India Sarvatra multi-span overhead aluminum truss bridge.
        b.addBox(0, 0.27, -0.06, 0.22, 0.12, 0.24, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.39, -0.02, 0.24, 0.11, 0.30, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
      }
    } else {
      // Tracked CEV chassis + roadwheel hubs + rear stowage (+72 tris).
      b.addBox(-0.22, 0.09, 0, 0.07, 0.13, 0.32, ProceduralMaterialSlot.neutralMetal);
      b.addBox(0.22, 0.09, 0, 0.07, 0.13, 0.32, ProceduralMaterialSlot.neutralMetal);
      for (final rz in const <double>[0.18, 0.0, -0.18]) {
        b.addBox(-0.25, 0.11, rz, 0.055, 0.07, 0.055, ProceduralMaterialSlot.factionUniform);
        b.addBox(0.25, 0.11, rz, 0.055, 0.07, 0.055, ProceduralMaterialSlot.factionUniform);
      }
      b.addBox(0, 0.13, -0.02, 0.19, 0.20, 0.30, ProceduralMaterialSlot.factionPrimary);
      b.addBox(0, 0.23, -0.32, 0.14, 0.05, 0.02, ProceduralMaterialSlot.teamRing);

      // Superstructure cupola (`turret`).
      b.setPivot(MeshPartTag.turret, 0, 0.37, 0.0);
      b.addCylinder(0, 0.33, -0.03, 0.16, 0.12, 0.16, ProceduralMaterialSlot.factionPrimary, sides: 8, part: MeshPartTag.turret);
      b.addBox(0, 0.45, -0.03, 0.09, 0.05, 0.09, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);

      // National engineering implement (`barrel`).
      b.setPivot(MeshPartTag.barrel, 0, 0.24, 0.30);
      switch (faction) {
        case FactionId.usa:
          // M1150 ABV: full-width V-shaped mine plow + twin rear MICLIC charge launchers + lane-marking pods.
          b.addRotatedBox(-0.14, 0.18, 0.32, 0.15, 0.09, 0.04, 0, -0.34, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
          b.addRotatedBox(0.14, 0.18, 0.32, 0.15, 0.09, 0.04, 0, 0.34, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
          b.addRotatedBox(-0.11, 0.40, -0.18, 0.06, 0.06, 0.13, -0.35, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
          b.addRotatedBox(0.11, 0.40, -0.18, 0.06, 0.06, 0.13, -0.35, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
          b.addBox(-0.17, 0.28, 0.22, 0.035, 0.065, 0.05, ProceduralMaterialSlot.neutralMetal);
          b.addBox(0.17, 0.28, 0.22, 0.035, 0.065, 0.05, ProceduralMaterialSlot.neutralMetal);
        case FactionId.southKorea:
          // K600 Rhino: wide spiked mine plow + right-side hydraulic excavator arm + magnetic duplicator bar.
          b.addRotatedBox(-0.14, 0.18, 0.32, 0.15, 0.09, 0.04, 0, -0.34, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
          b.addRotatedBox(0.14, 0.18, 0.32, 0.15, 0.09, 0.04, 0, 0.34, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
          b.addBox(0, 0.10, 0.36, 0.26, 0.035, 0.025, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
          b.addRotatedBox(0.15, 0.44, 0.12, 0.042, 0.048, 0.18, -0.50, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
          b.addBox(0.15, 0.51, 0.28, 0.052, 0.08, 0.06, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        case FactionId.sovietUnion:
          // BAT-2 rear crane + front V-blade.
          b.addBox(0, 0.17, 0.33, 0.27, 0.09, 0.04, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
          b.addRotatedBox(-0.11, 0.44, 0.14, 0.038, 0.045, 0.18, -0.55, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
          b.addBox(-0.11, 0.52, 0.29, 0.05, 0.08, 0.06, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        case FactionId.germany:
          // Dachs right-offset telescopic boom + hydraulic winch.
          b.addBox(0, 0.17, 0.33, 0.27, 0.09, 0.04, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
          b.addRotatedBox(0.13, 0.45, 0.14, 0.040, 0.045, 0.19, -0.50, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
          b.addBox(0.13, 0.53, 0.30, 0.055, 0.085, 0.06, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        case FactionId.unitedKingdom:
          // Trojan AVRE: excavator boom + rear fascine rack.
          b.addBox(0, 0.17, 0.33, 0.27, 0.09, 0.04, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
          b.addRotatedBox(-0.12, 0.44, 0.14, 0.038, 0.045, 0.18, -0.55, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
          b.addCylinder(0, 0.36, -0.22, 0.14, 0.09, 0.08, ProceduralMaterialSlot.factionAccent, sides: 6, part: MeshPartTag.turret);
        case FactionId.france:
          // Overhead demolition boom + front blade.
          b.addBox(0, 0.17, 0.33, 0.26, 0.09, 0.04, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
          b.addRotatedBox(0, 0.50, 0.08, 0.04, 0.04, 0.22, -0.35, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        case FactionId.china:
          // Twin heavy mine-clearing rollers out front.
          b.addCylinder(-0.15, 0.10, 0.31, 0.09, 0.14, 0.09, ProceduralMaterialSlot.neutralMetal, sides: 8, part: MeshPartTag.barrel);
          b.addCylinder(0.15, 0.10, 0.31, 0.09, 0.14, 0.09, ProceduralMaterialSlot.neutralMetal, sides: 8, part: MeshPartTag.barrel);
          b.addBox(0, 0.24, 0.28, 0.24, 0.04, 0.05, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        case FactionId.japan:
          // Overhead Type 91 scissor-folding bridge span.
          b.addBox(0, 0.35, 0.0, 0.26, 0.08, 0.34, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
          b.addBox(0, 0.43, 0.0, 0.22, 0.06, 0.30, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        case FactionId.israel:
          // Tall boxy Puma CEV casemate + mine roller.
          b.addBox(0, 0.33, -0.02, 0.19, 0.14, 0.24, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.turret);
          b.addBox(0, 0.17, 0.33, 0.26, 0.09, 0.045, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        case FactionId.vietnam:
        case FactionId.india:
          break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 6. TANK (11 distinct MBTs, capacity = 2)
  // ---------------------------------------------------------------------------
  static void _buildTank(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.37, baseH: 0.048, ringH: 0.036);
    b.addPassengerSocket(-0.13, 0.33, -0.21);
    b.addPassengerSocket(0.13, 0.33, -0.21);

    // Tracks + armored side skirts + lower hull + roadwheel hubs + engine deck (+96 tris).
    b.addBox(-0.23, 0.084, 0, 0.072, 0.14, 0.33, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0.23, 0.084, 0, 0.072, 0.14, 0.33, ProceduralMaterialSlot.neutralMetal);
    for (final rz in const <double>[0.20, 0.0, -0.20]) {
      b.addBox(-0.255, 0.10, rz, 0.052, 0.068, 0.052, ProceduralMaterialSlot.factionUniform);
      b.addBox(0.255, 0.10, rz, 0.052, 0.068, 0.052, ProceduralMaterialSlot.factionUniform);
    }
    b.addBox(-0.295, 0.14, 0, 0.018, 0.09, 0.31, ProceduralMaterialSlot.factionPrimary);
    b.addBox(0.295, 0.14, 0, 0.018, 0.09, 0.31, ProceduralMaterialSlot.factionPrimary);
    b.addBox(0, 0.12, 0, 0.18, 0.19, 0.31, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.92, topScaleZ: 0.90);
    b.addBox(0, 0.31, -0.22, 0.14, 0.025, 0.07, ProceduralMaterialSlot.neutralMetal);
    // teamRing rear deck plate.
    b.addBox(0, 0.22, -0.31, 0.14, 0.05, 0.02, ProceduralMaterialSlot.teamRing);

    // Distinct turret & barrel per nation.
    final turretZ = faction == FactionId.israel ? -0.09 : -0.01;
    b.setPivot(MeshPartTag.turret, 0.0, 0.31, turretZ);
    b.setPivot(MeshPartTag.barrel, 0.0, 0.40, turretZ + 0.16);

    switch (faction) {
      case FactionId.usa:
        // Broad Chobham wedge turret + CROWS RWS + long bustle.
        b.addExtrudedPolygon(
          const [(x: -0.20, z: 0.12), (x: 0.20, z: 0.12), (x: 0.16, z: -0.22), (x: -0.16, z: -0.22), (x: 0.0, z: 0.21)],
          0.31,
          0.47,
          ProceduralMaterialSlot.factionPrimary,
          topScale: 0.86,
          part: MeshPartTag.turret,
        );
        b.addBox(-0.08, 0.47, -0.02, 0.06, 0.06, 0.06, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.37, 0.28, 0.028, 0.028, 0.13, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);

      case FactionId.vietnam:
        // Cast-dome T-90S turret + Kontakt-5 wedge + Shtora IR dazzlers.
        b.addCylinder(0, 0.31, -0.01, 0.18, 0.16, 0.18, ProceduralMaterialSlot.factionPrimary, sides: 10, topScaleX: 0.78, topScaleZ: 0.78, part: MeshPartTag.turret);
        b.addBox(-0.11, 0.36, 0.15, 0.035, 0.04, 0.04, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.turret);
        b.addBox(0.11, 0.36, 0.15, 0.035, 0.04, 0.04, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.turret);
        b.addBox(0, 0.37, 0.27, 0.028, 0.028, 0.13, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);

      case FactionId.sovietUnion:
        // T-72B cast dome + ERA cheek tiles + rear fuel drums.
        b.addCylinder(0, 0.31, 0.0, 0.175, 0.15, 0.175, ProceduralMaterialSlot.factionPrimary, sides: 10, topScaleX: 0.76, topScaleZ: 0.76, part: MeshPartTag.turret);
        b.addBox(-0.11, 0.33, -0.32, 0.055, 0.055, 0.045, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.11, 0.33, -0.32, 0.055, 0.055, 0.045, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.37, 0.27, 0.028, 0.028, 0.13, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);

      case FactionId.unitedKingdom:
        // Tall slab Challenger 2 turret + 120mm L30A1 rifled gun.
        b.addBox(0, 0.31, -0.02, 0.19, 0.19, 0.20, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.90, topScaleZ: 0.88, part: MeshPartTag.turret);
        b.addBox(0, 0.50, -0.05, 0.10, 0.05, 0.10, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.39, 0.28, 0.028, 0.028, 0.13, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);

      case FactionId.germany:
        // Acute arrowhead Leopard 2A7 turret + long L/55 barrel.
        b.addExtrudedPolygon(
          const [(x: 0.0, z: 0.23), (x: 0.19, z: 0.06), (x: 0.16, z: -0.20), (x: -0.16, z: -0.20), (x: -0.19, z: 0.06)],
          0.31,
          0.47,
          ProceduralMaterialSlot.factionPrimary,
          topScale: 0.88,
          part: MeshPartTag.turret,
        );
        b.addBox(0, 0.47, -0.04, 0.11, 0.05, 0.10, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.38, 0.29, 0.025, 0.025, 0.13, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);

      case FactionId.france:
        // Compact Leclerc autoloader turret + modular cheek blocks.
        b.addBox(0, 0.31, -0.02, 0.155, 0.16, 0.21, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.90, topScaleZ: 0.90, part: MeshPartTag.turret);
        b.addBox(0.08, 0.47, 0.02, 0.05, 0.06, 0.05, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.38, 0.28, 0.026, 0.026, 0.13, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);

      case FactionId.china:
        // Sloped FY-4 ERA arrowhead ZTZ-99A turret + APS mast.
        b.addExtrudedPolygon(
          const [(x: 0.0, z: 0.21), (x: 0.18, z: 0.08), (x: 0.15, z: -0.19), (x: -0.15, z: -0.19), (x: -0.18, z: 0.08)],
          0.31,
          0.45,
          ProceduralMaterialSlot.factionPrimary,
          topScale: 0.82,
          part: MeshPartTag.turret,
        );
        b.addBox(-0.10, 0.45, -0.06, 0.035, 0.09, 0.035, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.turret);
        b.addBox(0, 0.37, 0.28, 0.028, 0.028, 0.13, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);

      case FactionId.japan:
        // Compact angular Type 10 turret.
        b.addBox(0, 0.31, 0.0, 0.165, 0.145, 0.18, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.86, topScaleZ: 0.86, part: MeshPartTag.turret);
        b.addBox(0, 0.455, -0.02, 0.09, 0.045, 0.08, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.37, 0.27, 0.026, 0.026, 0.125, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);

      case FactionId.southKorea:
        // Low-profile K2 Black Panther turret + panoramic sight.
        b.addBox(0, 0.31, 0.0, 0.18, 0.135, 0.20, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.84, topScaleZ: 0.88, part: MeshPartTag.turret);
        b.addBox(-0.08, 0.445, 0.02, 0.045, 0.05, 0.045, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.365, 0.28, 0.026, 0.026, 0.135, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);

      case FactionId.india:
        // Broad Kanchan box Arjun turret.
        b.addBox(0, 0.31, -0.01, 0.21, 0.175, 0.20, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.94, topScaleZ: 0.92, part: MeshPartTag.turret);
        b.addBox(0.08, 0.485, 0.0, 0.055, 0.05, 0.055, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.38, 0.28, 0.030, 0.030, 0.13, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);

      case FactionId.israel:
        // Rear-set wedge Merkava Mk.4M turret + Trophy APS pods.
        b.addExtrudedPolygon(
          const [(x: 0.0, z: 0.12), (x: 0.19, z: -0.02), (x: 0.16, z: -0.28), (x: -0.16, z: -0.28), (x: -0.19, z: -0.02)],
          0.31,
          0.47,
          ProceduralMaterialSlot.factionPrimary,
          topScale: 0.86,
          part: MeshPartTag.turret,
        );
        b.addBox(-0.18, 0.39, -0.14, 0.04, 0.06, 0.06, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0.18, 0.39, -0.14, 0.04, 0.06, 0.06, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.38, 0.23, 0.028, 0.028, 0.18, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
    }
    // Bore evacuator / muzzle brake ring.
    b.addBox(0, 0.37, 0.23, 0.042, 0.042, 0.035, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
  }

  // ---------------------------------------------------------------------------
  // 7. ARTILLERY (11 distinct SPG / wheeled / towed howitzers)
  // ---------------------------------------------------------------------------
  static void _buildArtillery(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.36, baseH: 0.048, ringH: 0.036);

    if (faction == FactionId.vietnam) {
      // Towed split-trail 130mm M-46 field gun + spade shoes + recuperator cylinder (+36 tris).
      b.addRotatedBox(-0.14, 0.13, -0.16, 0.035, 0.035, 0.18, 0, -0.40, 0, ProceduralMaterialSlot.factionPrimary);
      b.addRotatedBox(0.14, 0.13, -0.16, 0.035, 0.035, 0.18, 0, 0.40, 0, ProceduralMaterialSlot.factionPrimary);
      b.addBox(-0.21, 0.10, -0.31, 0.045, 0.05, 0.045, ProceduralMaterialSlot.neutralMetal);
      b.addBox(0.21, 0.10, -0.31, 0.045, 0.05, 0.045, ProceduralMaterialSlot.neutralMetal);
      b.addBox(0, 0.14, 0.06, 0.24, 0.05, 0.05, ProceduralMaterialSlot.neutralMetal);
      b.addCylinder(-0.23, 0.09, 0.06, 0.12, 0.06, 0.12, ProceduralMaterialSlot.neutralMetal, sides: 8);
      b.addCylinder(0.23, 0.09, 0.06, 0.12, 0.06, 0.12, ProceduralMaterialSlot.neutralMetal, sides: 8);
      b.setPivot(MeshPartTag.turret, 0, 0.26, 0.08);
      b.addBox(0, 0.19, 0.10, 0.20, 0.22, 0.04, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
      b.addBox(0, 0.26, 0.14, 0.10, 0.05, 0.02, ProceduralMaterialSlot.teamRing, part: MeshPartTag.turret);
      b.setPivot(MeshPartTag.barrel, 0, 0.38, 0.10);
      b.addRotatedBox(0, 0.44, 0.16, 0.032, 0.032, 0.25, -0.45, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
      b.addRotatedBox(0, 0.37, 0.12, 0.045, 0.045, 0.09, -0.45, 0, 0, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.barrel);
      b.addRotatedBox(0, 0.55, 0.36, 0.048, 0.048, 0.035, -0.45, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
      return;
    }

    final isWheeled = faction == FactionId.france || faction == FactionId.israel;
    if (isWheeled) {
      // 6x6 CAESAR / ATMOS 2000 wheeled SPG + armored cab visor + rear spades (+36 tris).
      for (final wz in const <double>[0.22, 0.0, -0.22]) {
        b.addBox(-0.21, 0.084, wz, 0.04, 0.10, 0.055, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.21, 0.084, wz, 0.04, 0.10, 0.055, ProceduralMaterialSlot.neutralMetal);
      }
      b.addBox(0, 0.14, 0, 0.19, 0.12, 0.31, ProceduralMaterialSlot.factionPrimary);
      b.addBox(0, 0.26, 0.18, 0.18, 0.17, 0.12, faction == FactionId.israel ? ProceduralMaterialSlot.factionUniform : ProceduralMaterialSlot.factionPrimary);
      b.addBox(0, 0.37, 0.28, 0.14, 0.05, 0.025, ProceduralMaterialSlot.factionAccent);
      b.addBox(0, 0.20, -0.32, 0.13, 0.05, 0.02, ProceduralMaterialSlot.teamRing);

      b.setPivot(MeshPartTag.turret, 0, 0.30, -0.10);
      b.addBox(0, 0.26, -0.10, 0.14, 0.14, 0.14, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
      if (faction == FactionId.israel) {
        // ATMOS 2000 rear hydraulic spade stabilizers + armored ammo bustle.
        b.addBox(-0.15, 0.11, -0.32, 0.045, 0.11, 0.04, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.15, 0.11, -0.32, 0.045, 0.11, 0.04, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0, 0.34, 0.02, 0.16, 0.07, 0.06, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
      } else {
        // CAESAR open-deck side storage lockers.
        b.addBox(-0.16, 0.26, -0.02, 0.035, 0.08, 0.12, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0.16, 0.26, -0.02, 0.035, 0.08, 0.12, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
      }
      b.setPivot(MeshPartTag.barrel, 0, 0.42, -0.06);
      b.addRotatedBox(0, 0.50, 0.12, 0.032, 0.032, 0.26, -0.52, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
      b.addRotatedBox(0, 0.62, 0.33, 0.048, 0.048, 0.035, -0.52, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
      return;
    }

    // Tracked self-propelled howitzers + roadwheel hubs + rear recoil spades (+96 tris).
    b.addBox(-0.22, 0.084, 0, 0.068, 0.12, 0.32, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0.22, 0.084, 0, 0.068, 0.12, 0.32, ProceduralMaterialSlot.neutralMetal);
    for (final rz in const <double>[0.18, 0.0, -0.18]) {
      b.addBox(-0.245, 0.10, rz, 0.048, 0.065, 0.048, ProceduralMaterialSlot.factionUniform);
      b.addBox(0.245, 0.10, rz, 0.048, 0.065, 0.048, ProceduralMaterialSlot.factionUniform);
    }
    b.addBox(0, 0.12, -0.02, 0.18, 0.17, 0.30, ProceduralMaterialSlot.factionPrimary);
    b.addBox(-0.14, 0.10, -0.32, 0.045, 0.10, 0.04, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0.14, 0.10, -0.32, 0.045, 0.10, 0.04, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0, 0.22, -0.32, 0.13, 0.05, 0.02, ProceduralMaterialSlot.teamRing);

    final turretZ = switch (faction) {
      FactionId.germany => -0.14,
      FactionId.japan => -0.11,
      FactionId.unitedKingdom => -0.05,
      _ => -0.08,
    };
    b.setPivot(MeshPartTag.turret, 0, 0.29, turretZ);

    double barrelPivotY = 0.39;
    double barrelMidY = 0.48;
    double barrelStartZ = turretZ + 0.14;
    double barrelHalfLen = 0.24;
    double brakeWidth = 0.050;
    double elev = -0.46;

    switch (faction) {
      case FactionId.usa:
        // M109A7 Paladin: stepped turret + overhanging armored ammo bustle + CROWS cupola + bow travel lock.
        b.addBox(0, 0.29, -0.04, 0.165, 0.17, 0.16, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.90, topScaleZ: 0.90, part: MeshPartTag.turret);
        b.addBox(0, 0.34, -0.23, 0.175, 0.13, 0.08, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.turret);
        b.addBox(0.09, 0.46, -0.02, 0.055, 0.06, 0.055, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.29, 0.23, 0.09, 0.07, 0.03, ProceduralMaterialSlot.neutralMetal);
        elev = -0.42;
        barrelStartZ = 0.12;
        barrelHalfLen = 0.23;

      case FactionId.sovietUnion:
        // 2S19 Msta-S: rounded octagonal turret + twin rear autoloader chutes + fume extractor sleeve.
        b.addCylinder(0, 0.29, -0.07, 0.19, 0.18, 0.19, ProceduralMaterialSlot.factionPrimary, sides: 8, topScaleX: 0.84, topScaleZ: 0.84, part: MeshPartTag.turret);
        b.addBox(-0.09, 0.31, -0.26, 0.05, 0.09, 0.055, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0.09, 0.31, -0.26, 0.05, 0.09, 0.055, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.47, -0.06, 0.10, 0.045, 0.09, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.turret);
        elev = -0.45;
        barrelStartZ = 0.10;
        barrelHalfLen = 0.24;

      case FactionId.unitedKingdom:
        // AS-90 Braveheart: tall slab box turret + rear stowage basket + muzzle reference mast.
        b.addBox(0, 0.29, -0.05, 0.18, 0.23, 0.18, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.94, topScaleZ: 0.92, part: MeshPartTag.turret);
        b.addBox(0, 0.36, -0.25, 0.15, 0.08, 0.045, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.turret);
        b.addBox(0, 0.52, -0.05, 0.11, 0.04, 0.10, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        elev = -0.46;
        barrelPivotY = 0.41;
        barrelMidY = 0.50;
        barrelStartZ = 0.13;

      case FactionId.germany:
        // PzH 2000: raised forward engine hull + rear-mounted L/52 turret + roof hatches.
        b.addBox(0, 0.29, 0.12, 0.175, 0.06, 0.13, ProceduralMaterialSlot.factionUniform);
        b.addBox(0, 0.29, -0.14, 0.175, 0.18, 0.17, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.88, topScaleZ: 0.90, part: MeshPartTag.turret);
        b.addBox(0, 0.47, -0.15, 0.12, 0.045, 0.11, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        elev = -0.52;
        barrelStartZ = 0.03;
        barrelHalfLen = 0.27;

      case FactionId.china:
        // PLZ-05: forward-overhang welded turret + side smoke-grenade racks + elevated laser/radar pod + double-baffle brake.
        b.addBox(0, 0.29, -0.03, 0.185, 0.18, 0.21, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.90, topScaleZ: 0.92, part: MeshPartTag.turret);
        b.addBox(-0.20, 0.34, -0.06, 0.035, 0.07, 0.12, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0.20, 0.34, -0.06, 0.035, 0.07, 0.12, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(-0.09, 0.47, 0.04, 0.045, 0.075, 0.055, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.turret);
        elev = -0.55;
        barrelStartZ = 0.16;
        barrelHalfLen = 0.25;
        brakeWidth = 0.068;

      case FactionId.japan:
        // Type 99 155mm HSP: tall rear bustle turret + twin roof cupolas + bustle overhang.
        b.addBox(0, 0.29, -0.11, 0.17, 0.22, 0.18, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.88, topScaleZ: 0.88, part: MeshPartTag.turret);
        b.addBox(-0.08, 0.51, -0.09, 0.05, 0.045, 0.05, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0.08, 0.51, -0.09, 0.05, 0.045, 0.05, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.37, -0.28, 0.15, 0.09, 0.045, ProceduralMaterialSlot.factionUniform, part: MeshPartTag.turret);
        elev = -0.47;
        barrelPivotY = 0.41;
        barrelMidY = 0.50;
        barrelStartZ = 0.07;

      case FactionId.southKorea:
        // K9A1 Thunder: sloped hexagonal wedge turret + left-rear APU box + panoramic sight.
        b.addExtrudedPolygon(
          const [(x: 0.0, z: 0.14), (x: 0.18, z: 0.02), (x: 0.16, z: -0.23), (x: -0.16, z: -0.23), (x: -0.18, z: 0.02)],
          0.29,
          0.46,
          ProceduralMaterialSlot.factionPrimary,
          topScale: 0.84,
          part: MeshPartTag.turret,
        );
        b.addBox(-0.12, 0.33, -0.26, 0.065, 0.085, 0.05, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.turret);
        b.addBox(0.08, 0.46, -0.04, 0.045, 0.065, 0.045, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        elev = -0.50;
        barrelStartZ = 0.11;
        barrelHalfLen = 0.25;

      case FactionId.india:
        // K9 Vajra-T: desert sand hull cooling louvers + roof environmental AC pod + extended rear bustle cage.
        b.addBox(0, 0.29, -0.08, 0.17, 0.17, 0.18, ProceduralMaterialSlot.factionUniform, topScaleX: 0.88, topScaleZ: 0.88, part: MeshPartTag.turret);
        b.addBox(-0.21, 0.21, -0.14, 0.04, 0.075, 0.14, ProceduralMaterialSlot.factionAccent);
        b.addBox(0.21, 0.21, -0.14, 0.04, 0.075, 0.14, ProceduralMaterialSlot.factionAccent);
        b.addBox(0, 0.46, -0.12, 0.12, 0.06, 0.085, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.34, -0.27, 0.14, 0.09, 0.055, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.turret);
        elev = -0.48;
        barrelStartZ = 0.10;

      case FactionId.vietnam:
      case FactionId.france:
      case FactionId.israel:
        break;
    }

    b.setPivot(MeshPartTag.barrel, 0, barrelPivotY, barrelStartZ);
    b.addRotatedBox(0, barrelMidY, barrelStartZ + 0.08, 0.034, 0.034, barrelHalfLen, elev, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
    b.addRotatedBox(0, barrelMidY + 0.11, barrelStartZ + 0.26, brakeWidth, 0.050, 0.036, elev, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
  }

  // ---------------------------------------------------------------------------
  // 8. ANTI-AIRCRAFT (11 distinct SPAAGs & SAM batteries)
  // ---------------------------------------------------------------------------
  static void _buildAntiAircraft(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.35, baseH: 0.048, ringH: 0.036);

    // Base platform: wheeled 8x8 (USA, FR), outriggers (VN, IL), or tracked.
    if (faction == FactionId.usa || faction == FactionId.france) {
      for (final wz in const <double>[0.24, 0.08, -0.08, -0.24]) {
        b.addBox(-0.21, 0.084, wz, 0.04, 0.10, 0.052, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.21, 0.084, wz, 0.04, 0.10, 0.052, ProceduralMaterialSlot.neutralMetal);
      }
      b.addBox(0, 0.14, 0, 0.18, 0.16, 0.30, ProceduralMaterialSlot.factionPrimary);
    } else if (faction == FactionId.vietnam || faction == FactionId.israel) {
      // Cruciform outrigger platform + 4 stabilizing footpads + generator boxes (+72 tris).
      b.addBox(0, 0.09, 0, 0.34, 0.06, 0.10, ProceduralMaterialSlot.neutralMetal);
      b.addBox(0, 0.09, 0, 0.10, 0.06, 0.34, ProceduralMaterialSlot.neutralMetal);
      b.addBox(-0.31, 0.085, 0, 0.05, 0.04, 0.08, ProceduralMaterialSlot.factionAccent);
      b.addBox(0.31, 0.085, 0, 0.05, 0.04, 0.08, ProceduralMaterialSlot.factionAccent);
      b.addBox(0, 0.085, 0.31, 0.08, 0.04, 0.05, ProceduralMaterialSlot.factionAccent);
      b.addBox(0, 0.085, -0.31, 0.08, 0.04, 0.05, ProceduralMaterialSlot.factionAccent);
      b.addBox(-0.16, 0.15, 0.16, 0.05, 0.08, 0.05, ProceduralMaterialSlot.factionUniform);
      b.addBox(0.16, 0.15, 0.16, 0.05, 0.08, 0.05, ProceduralMaterialSlot.factionUniform);
      b.addCylinder(0, 0.15, 0, 0.18, 0.14, 0.18, ProceduralMaterialSlot.factionPrimary, sides: 8);
    } else {
      // Tracked SPAAG chassis + roadwheel hubs + rear engine louvers (+84 tris).
      b.addBox(-0.22, 0.084, 0, 0.065, 0.12, 0.30, ProceduralMaterialSlot.neutralMetal);
      b.addBox(0.22, 0.084, 0, 0.065, 0.12, 0.30, ProceduralMaterialSlot.neutralMetal);
      for (final rz in const <double>[0.18, 0.0, -0.18]) {
        b.addBox(-0.24, 0.10, rz, 0.046, 0.062, 0.046, ProceduralMaterialSlot.factionUniform);
        b.addBox(0.24, 0.10, rz, 0.046, 0.062, 0.046, ProceduralMaterialSlot.factionUniform);
      }
      b.addBox(0, 0.29, -0.22, 0.13, 0.03, 0.06, ProceduralMaterialSlot.neutralMetal);
      b.addBox(0, 0.13, 0, 0.18, 0.16, 0.28, ProceduralMaterialSlot.factionPrimary);
    }
    b.addBox(0, 0.22, -0.30, 0.12, 0.05, 0.02, ProceduralMaterialSlot.teamRing);

    b.setPivot(MeshPartTag.turret, 0, 0.31, 0.0);
    b.setPivot(MeshPartTag.barrel, 0, 0.45, 0.06);
    b.setPivot(MeshPartTag.wingRotor, 0, 0.56, -0.14);

    switch (faction) {
      case FactionId.usa:
        // Stryker M-SHORAD: dual pods + 30mm chain gun + radar dome.
        b.addBox(0, 0.30, 0, 0.15, 0.12, 0.15, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addRotatedBox(-0.15, 0.44, 0.03, 0.055, 0.06, 0.13, -0.45, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.15, 0.44, 0.03, 0.055, 0.06, 0.13, -0.45, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addCylinder(0, 0.42, -0.08, 0.08, 0.08, 0.08, ProceduralMaterialSlot.factionPrimary, sides: 8, part: MeshPartTag.wingRotor);

      case FactionId.vietnam:
        // S-60 57mm elevating gun + optical director.
        b.addBox(0, 0.29, 0, 0.15, 0.14, 0.15, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addRotatedBox(0, 0.54, 0.08, 0.032, 0.032, 0.24, -0.78, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(0.14, 0.42, -0.05, 0.05, 0.08, 0.05, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);

      case FactionId.sovietUnion:
        // ZSU-23-4 Shilka: 4 barrels + Gun Dish radar.
        b.addBox(0, 0.29, 0, 0.17, 0.13, 0.17, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.turret);
        for (final bx in const <double>[-0.09, -0.03, 0.03, 0.09]) {
          b.addRotatedBox(bx, 0.48, 0.10, 0.014, 0.014, 0.18, -0.68, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        }
        b.addCylinder(0, 0.44, -0.14, 0.10, 0.06, 0.06, ProceduralMaterialSlot.factionAccent, sides: 8, part: MeshPartTag.wingRotor);

      case FactionId.unitedKingdom:
        // Stormer HVM 8-round twin box + panoramic IR sight.
        b.addBox(0, 0.29, 0, 0.16, 0.13, 0.16, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addRotatedBox(-0.12, 0.48, 0.02, 0.055, 0.065, 0.13, -0.42, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.12, 0.48, 0.02, 0.055, 0.065, 0.13, -0.42, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addCylinder(0, 0.42, 0.06, 0.045, 0.10, 0.045, ProceduralMaterialSlot.factionEmblem, sides: 6, part: MeshPartTag.wingRotor);

      case FactionId.germany:
        // Gepard: twin lateral 35mm pods + rear search radar + front tracker dish.
        b.addBox(0, 0.29, 0, 0.15, 0.14, 0.16, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addRotatedBox(-0.19, 0.46, 0.06, 0.032, 0.032, 0.21, -0.72, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.19, 0.46, 0.06, 0.032, 0.032, 0.21, -0.72, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(0, 0.50, -0.14, 0.13, 0.06, 0.03, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addCylinder(0, 0.43, 0.08, 0.05, 0.06, 0.05, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);

      case FactionId.japan:
        // Type 87 Guntank: twin 35mm pods + offset mast radar.
        b.addBox(0, 0.29, 0, 0.16, 0.15, 0.17, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.turret);
        b.addRotatedBox(-0.20, 0.45, 0.05, 0.036, 0.036, 0.20, -0.68, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.20, 0.45, 0.05, 0.036, 0.036, 0.20, -0.68, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(0.08, 0.51, -0.13, 0.10, 0.07, 0.03, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.france:
        // Crotale NG: 8-cell launcher + central monopulse cone radar.
        b.addBox(0, 0.30, 0, 0.16, 0.13, 0.16, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.turret);
        b.addRotatedBox(-0.15, 0.45, 0.02, 0.055, 0.065, 0.12, -0.45, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.15, 0.45, 0.02, 0.055, 0.065, 0.12, -0.45, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addCone(0, 0.43, 0.0, 0.08, 0.14, 0.08, ProceduralMaterialSlot.factionAccent, sides: 8, part: MeshPartTag.wingRotor);

      case FactionId.china:
        // PGZ-09: twin 35mm + side missile rails + rear search radar.
        b.addBox(0, 0.29, 0, 0.16, 0.13, 0.16, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.turret);
        b.addRotatedBox(-0.07, 0.49, 0.08, 0.024, 0.024, 0.20, -0.75, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.07, 0.49, 0.08, 0.024, 0.024, 0.20, -0.75, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(-0.19, 0.39, -0.02, 0.03, 0.05, 0.10, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addBox(0.19, 0.39, -0.02, 0.03, 0.05, 0.10, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addBox(0, 0.48, -0.14, 0.11, 0.055, 0.03, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);

      case FactionId.southKorea:
        // K30 Biho Hybrid: twin 30mm + twin Chiron SAM pods + forward EO dome.
        b.addBox(0, 0.29, 0, 0.165, 0.13, 0.17, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.turret);
        b.addRotatedBox(-0.07, 0.49, 0.08, 0.022, 0.022, 0.19, -0.75, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.07, 0.49, 0.08, 0.022, 0.022, 0.19, -0.75, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(-0.19, 0.42, 0.0, 0.035, 0.045, 0.11, -0.45, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addRotatedBox(0.19, 0.42, 0.0, 0.035, 0.045, 0.11, -0.45, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addCylinder(0, 0.42, 0.06, 0.045, 0.06, 0.045, ProceduralMaterialSlot.factionEmblem, sides: 6, part: MeshPartTag.wingRotor);

      case FactionId.india:
        // Akash triple-rail elevating SAMs.
        b.addCylinder(0, 0.29, 0, 0.15, 0.12, 0.15, ProceduralMaterialSlot.factionAccent, sides: 8, part: MeshPartTag.turret);
        for (final mx in const <double>[-0.12, 0.0, 0.12]) {
          b.addRotatedBox(mx, 0.50, 0.04, 0.026, 0.026, 0.21, -0.58, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        }
        b.addBox(0, 0.45, -0.14, 0.09, 0.06, 0.03, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);

      case FactionId.israel:
        // Iron Dome angled 20-cell battery box + radar mast.
        b.addBox(0, 0.29, -0.04, 0.16, 0.10, 0.14, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addRotatedBox(0, 0.48, 0.02, 0.17, 0.11, 0.14, -0.52, 0, 0, ProceduralMaterialSlot.factionUniform, part: MeshPartTag.barrel);
        b.addBox(0, 0.50, -0.16, 0.06, 0.14, 0.04, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);
    }
  }

  // ---------------------------------------------------------------------------
  // 9. MISSILE (11 distinct rocket / ballistic / cruise missile TELs)
  // ---------------------------------------------------------------------------
  static void _buildMissile(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.37, baseH: 0.048, ringH: 0.036);

    final isTracked = faction == FactionId.unitedKingdom ||
        faction == FactionId.germany ||
        faction == FactionId.france;

    if (isTracked) {
      b.addBox(-0.22, 0.084, 0, 0.068, 0.12, 0.31, ProceduralMaterialSlot.neutralMetal);
      b.addBox(0.22, 0.084, 0, 0.068, 0.12, 0.31, ProceduralMaterialSlot.neutralMetal);
      for (final rz in const <double>[0.18, -0.18]) {
        b.addBox(-0.245, 0.10, rz, 0.048, 0.065, 0.048, ProceduralMaterialSlot.factionUniform);
        b.addBox(0.245, 0.10, rz, 0.048, 0.065, 0.048, ProceduralMaterialSlot.factionUniform);
      }
      b.addBox(0, 0.12, 0, 0.19, 0.18, 0.30, ProceduralMaterialSlot.factionPrimary);
      b.addBox(0, 0.24, 0.20, 0.18, 0.13, 0.10, ProceduralMaterialSlot.factionUniform);
      b.addBox(0, 0.30, 0.29, 0.15, 0.05, 0.025, ProceduralMaterialSlot.factionAccent);
    } else {
      final wheels = switch (faction) {
        FactionId.india => const <double>[0.25, 0.13, 0.01, -0.11, -0.23],
        FactionId.china => const <double>[0.24, 0.08, -0.08, -0.24],
        FactionId.vietnam ||
        FactionId.sovietUnion ||
        FactionId.japan ||
        FactionId.southKorea =>
          const <double>[0.24, 0.08, -0.08, -0.24],
        _ => const <double>[0.22, 0.0, -0.22],
      };
      for (final wz in wheels) {
        b.addBox(-0.22, 0.084, wz, 0.038, 0.10, 0.048, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.22, 0.084, wz, 0.038, 0.10, 0.048, ProceduralMaterialSlot.neutralMetal);
      }
      b.addBox(0, 0.13, 0, 0.19, 0.13, 0.31, ProceduralMaterialSlot.factionPrimary);
      b.addBox(0, 0.26, 0.21, 0.18, 0.13, 0.09, ProceduralMaterialSlot.factionUniform);
      b.addBox(0, 0.33, 0.29, 0.15, 0.05, 0.025, ProceduralMaterialSlot.factionAccent);
    }
    b.addBox(0, 0.20, -0.32, 0.14, 0.05, 0.02, ProceduralMaterialSlot.teamRing);

    b.setPivot(MeshPartTag.turret, 0, 0.30, -0.06);
    b.addBox(0, 0.26, -0.08, 0.16, 0.08, 0.18, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);

    b.setPivot(MeshPartTag.barrel, 0, 0.42, -0.06);
    switch (faction) {
      case FactionId.usa:
        // HIMARS 6-tube elevating GMLRS pod.
        b.addRotatedBox(0, 0.44, -0.02, 0.13, 0.10, 0.22, -0.48, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0, 0.56, 0.16, 0.11, 0.08, 0.03, -0.48, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);

      case FactionId.vietnam:
        // S-300PMU1 four vertical cylindrical SAM canisters.
        for (final cx in const <double>[-0.13, -0.045, 0.045, 0.13]) {
          b.addCylinder(cx, 0.34, -0.06, 0.038, 0.50, 0.038, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.barrel);
          b.addCone(cx, 0.84, -0.06, 0.038, 0.06, 0.038, ProceduralMaterialSlot.factionAccent, sides: 6, part: MeshPartTag.barrel);
        }

      case FactionId.sovietUnion:
        // Scud-B single massive tactical ballistic missile.
        b.addRotatedBox(0, 0.56, -0.02, 0.08, 0.28, 0.08, 0.32, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0, 0.84, 0.08, 0.055, 0.10, 0.055, 0.32, 0, 0, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.barrel);

      case FactionId.unitedKingdom:
        // M270B1 tracked twin-pod MLRS + cab louver cage.
        b.addRotatedBox(-0.10, 0.46, -0.02, 0.075, 0.09, 0.22, -0.52, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.10, 0.46, -0.02, 0.075, 0.09, 0.22, -0.52, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(-0.10, 0.57, 0.16, 0.06, 0.07, 0.028, -0.52, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addRotatedBox(0.10, 0.57, 0.16, 0.06, 0.07, 0.028, -0.52, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addBox(0, 0.39, 0.21, 0.16, 0.03, 0.06, ProceduralMaterialSlot.factionAccent);

      case FactionId.germany:
        // MARS II tracked twin-pod MLRS + elevated turntable sensor mast.
        b.addRotatedBox(-0.10, 0.48, -0.03, 0.075, 0.09, 0.22, -0.56, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.10, 0.48, -0.03, 0.075, 0.09, 0.22, -0.56, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(-0.10, 0.60, 0.15, 0.06, 0.07, 0.028, -0.56, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addRotatedBox(0.10, 0.60, 0.15, 0.06, 0.07, 0.028, -0.56, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addBox(-0.16, 0.34, -0.18, 0.025, 0.16, 0.025, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);

      case FactionId.france:
        // LRU tracked twin-pod MLRS + rear stabilizer spades.
        b.addRotatedBox(-0.10, 0.45, -0.02, 0.072, 0.088, 0.21, -0.46, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.10, 0.45, -0.02, 0.072, 0.088, 0.21, -0.46, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(-0.10, 0.55, 0.16, 0.058, 0.068, 0.028, -0.46, 0, 0, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.barrel);
        b.addRotatedBox(0.10, 0.55, 0.16, 0.058, 0.068, 0.028, -0.46, 0, 0, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.barrel);
        b.addBox(-0.14, 0.11, -0.31, 0.04, 0.10, 0.04, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.14, 0.11, -0.31, 0.04, 0.10, 0.04, ProceduralMaterialSlot.neutralMetal);

      case FactionId.southKorea:
      case FactionId.israel:
        // K239 Chunmoo (8x8) / PULS (6x6) dual modular rocket pods.
        final tilt = faction == FactionId.israel ? -0.42 : -0.52;
        b.addRotatedBox(-0.10, 0.46, -0.02, 0.075, 0.09, 0.22, tilt, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.10, 0.46, -0.02, 0.075, 0.09, 0.22, tilt, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(-0.10, 0.57, 0.16, 0.06, 0.07, 0.028, tilt, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        b.addRotatedBox(0.10, 0.57, 0.16, 0.06, 0.07, 0.028, tilt, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);

      case FactionId.china:
        // PHL-16 / DF-16 twin heavy ballistic canisters.
        b.addRotatedBox(-0.09, 0.54, -0.02, 0.065, 0.25, 0.065, 0.36, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.09, 0.54, -0.02, 0.065, 0.25, 0.065, 0.36, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(-0.09, 0.80, 0.08, 0.048, 0.07, 0.048, 0.36, 0, 0, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.barrel);
        b.addRotatedBox(0.09, 0.80, 0.08, 0.048, 0.07, 0.048, 0.36, 0, 0, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.barrel);

      case FactionId.japan:
        // Type 12 coastal 6-tube canister rack.
        for (final rowY in const <double>[0.40, 0.52]) {
          for (final cx in const <double>[-0.09, 0.0, 0.09]) {
            b.addRotatedBox(cx, rowY, -0.02, 0.032, 0.032, 0.22, -0.48, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
          }
        }

      case FactionId.india:
        // BrahMos triple supersonic cruise missile canisters.
        for (final cx in const <double>[-0.11, 0.0, 0.11]) {
          b.addRotatedBox(cx, 0.52, -0.02, 0.042, 0.24, 0.042, 0.32, 0, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
          b.addRotatedBox(cx, 0.77, 0.06, 0.032, 0.07, 0.032, 0.32, 0, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.barrel);
        }
    }
  }

  // ---------------------------------------------------------------------------
  // 10. AIR FORCE (11 distinct fighters, capacity = 2)
  // ---------------------------------------------------------------------------
  static void _buildAirForce(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.33, baseH: 0.048, ringH: 0.036);
    b.addPassengerSocket(-0.15, 0.59, -0.05);
    b.addPassengerSocket(0.15, 0.59, -0.05);

    // Pylon + stabilizer collar.
    b.addCylinder(0, 0.084, -0.02, 0.036, 0.44, 0.042, ProceduralMaterialSlot.neutralMetal, sides: 6);
    b.addBox(0, 0.50, -0.02, 0.06, 0.04, 0.07, ProceduralMaterialSlot.teamRing);

    // Fuselage + nose cone + canopy + exhaust nozzle(s).
    final fuseLen = faction == FactionId.china ? 0.37 : 0.33;
    b.addBox(0, 0.54, 0.01, 0.072, 0.09, fuseLen, ProceduralMaterialSlot.factionPrimary, topScaleX: 0.74, topScaleZ: 0.88);
    b.addRotatedBox(0, 0.58, fuseLen + 0.03, 0.045, 0.035, 0.06, 0.15, 0, 0, ProceduralMaterialSlot.factionPrimary);
    b.addBox(0, 0.63, 0.12, 0.042, 0.055, 0.11, ProceduralMaterialSlot.factionAccent, topScaleX: 0.65, topScaleZ: 0.65);
    b.addBox(0, 0.635, -0.12, 0.048, 0.022, 0.07, ProceduralMaterialSlot.teamRing);

    final isSingleEngine = faction == FactionId.japan ||
        faction == FactionId.india ||
        faction == FactionId.israel;
    if (isSingleEngine) {
      b.addCylinder(0, 0.54, -fuseLen, 0.048, 0.06, 0.048, ProceduralMaterialSlot.neutralMetal, sides: 8);
    } else {
      b.addCylinder(-0.048, 0.54, -fuseLen, 0.035, 0.06, 0.035, ProceduralMaterialSlot.neutralMetal, sides: 6);
      b.addCylinder(0.048, 0.54, -fuseLen, 0.035, 0.06, 0.035, ProceduralMaterialSlot.neutralMetal, sides: 6);
    }

    // Distinct national wing / canard / tail-fin silhouettes (`wingRotor` + `insigniaStar`).
    b.setPivot(MeshPartTag.wingRotor, 0, 0.58, -0.04);
    b.setPivot(MeshPartTag.insigniaStar, 0, 0.72, -0.24);

    switch (faction) {
      case FactionId.usa:
        // F-22A Raptor: diamond cropped-delta wings + rectangular TVC exhaust shrouds + canted twin tails.
        b.addExtrudedPolygon(
          const [(x: -0.07, z: 0.14), (x: -0.34, z: -0.08), (x: -0.30, z: -0.20), (x: -0.07, z: -0.20)],
          0.56,
          0.59,
          ProceduralMaterialSlot.factionPrimary,
          part: MeshPartTag.wingRotor,
        );
        b.addExtrudedPolygon(
          const [(x: 0.07, z: 0.14), (x: 0.07, z: -0.20), (x: 0.30, z: -0.20), (x: 0.34, z: -0.08)],
          0.56,
          0.59,
          ProceduralMaterialSlot.factionPrimary,
          part: MeshPartTag.wingRotor,
        );
        b.addRotatedBox(-0.08, 0.69, -0.24, 0.018, 0.10, 0.07, 0, 0, 0.36, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.08, 0.69, -0.24, 0.018, 0.10, 0.07, 0, 0, -0.36, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addBox(-0.05, 0.54, -0.36, 0.036, 0.035, 0.05, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.05, 0.54, -0.36, 0.036, 0.035, 0.05, ProceduralMaterialSlot.neutralMetal);

      case FactionId.southKorea:
        // KF-21 Boramae: swept trapezoidal wings + separate tailplanes + LERX intake strakes + conformal weapon bay + twin tails.
        b.addRotatedBox(-0.19, 0.575, -0.03, 0.16, 0.020, 0.085, 0, 0.42, 0, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.19, 0.575, -0.03, 0.16, 0.020, 0.085, 0, -0.42, 0, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.wingRotor);
        b.addRotatedBox(-0.12, 0.57, -0.23, 0.085, 0.016, 0.05, 0, 0.34, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.12, 0.57, -0.23, 0.085, 0.016, 0.05, 0, -0.34, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addBox(-0.085, 0.56, 0.12, 0.028, 0.035, 0.11, ProceduralMaterialSlot.factionAccent);
        b.addBox(0.085, 0.56, 0.12, 0.028, 0.035, 0.11, ProceduralMaterialSlot.factionAccent);
        b.addBox(0, 0.495, 0.02, 0.052, 0.045, 0.16, ProceduralMaterialSlot.neutralMetal);
        b.addRotatedBox(-0.08, 0.69, -0.24, 0.018, 0.11, 0.065, 0, 0, 0.24, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.08, 0.69, -0.24, 0.018, 0.11, 0.065, 0, 0, -0.24, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.israel:
        // F-35I Adir: broad chined stealth wings + conformal dorsal spine + lateral chined intakes + serrated single shroud.
        b.addExtrudedPolygon(
          const [(x: -0.07, z: 0.12), (x: -0.32, z: -0.06), (x: -0.30, z: -0.19), (x: -0.07, z: -0.19)],
          0.56,
          0.59,
          ProceduralMaterialSlot.factionPrimary,
          part: MeshPartTag.wingRotor,
        );
        b.addExtrudedPolygon(
          const [(x: 0.07, z: 0.12), (x: 0.07, z: -0.19), (x: 0.30, z: -0.19), (x: 0.32, z: -0.06)],
          0.56,
          0.59,
          ProceduralMaterialSlot.factionPrimary,
          part: MeshPartTag.wingRotor,
        );
        b.addBox(0, 0.63, -0.06, 0.046, 0.045, 0.15, ProceduralMaterialSlot.factionUniform);
        b.addBox(-0.095, 0.54, 0.12, 0.032, 0.048, 0.12, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.095, 0.54, 0.12, 0.032, 0.048, 0.12, ProceduralMaterialSlot.neutralMetal);
        b.addRotatedBox(-0.08, 0.69, -0.24, 0.018, 0.10, 0.07, 0, 0, 0.28, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.08, 0.69, -0.24, 0.018, 0.10, 0.07, 0, 0, -0.28, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.vietnam:
        // Su-30MK2V Flanker: wide LERX + twin vertical fins + tail stinger + wingtip rails.
        b.addRotatedBox(-0.20, 0.58, -0.05, 0.18, 0.022, 0.095, 0, 0.50, 0, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.20, 0.58, -0.05, 0.18, 0.022, 0.095, 0, -0.50, 0, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.wingRotor);
        b.addRotatedBox(-0.12, 0.57, -0.24, 0.09, 0.018, 0.055, 0, 0.35, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.12, 0.57, -0.24, 0.09, 0.018, 0.055, 0, -0.35, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addBox(-0.09, 0.63, -0.23, 0.018, 0.16, 0.07, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addBox(0.09, 0.63, -0.23, 0.018, 0.16, 0.07, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.56, -0.36, 0.022, 0.022, 0.06, ProceduralMaterialSlot.neutralMetal);

      case FactionId.sovietUnion:
        // MiG-29 Fulcrum: swept wings + underslung intakes + canted twin fins.
        b.addRotatedBox(-0.19, 0.58, -0.05, 0.17, 0.022, 0.09, 0, 0.48, 0, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.19, 0.58, -0.05, 0.17, 0.022, 0.09, 0, -0.48, 0, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.wingRotor);
        b.addRotatedBox(-0.11, 0.57, -0.23, 0.085, 0.018, 0.05, 0, 0.32, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.11, 0.57, -0.23, 0.085, 0.018, 0.05, 0, -0.32, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addBox(-0.08, 0.63, -0.22, 0.018, 0.15, 0.065, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);
        b.addBox(0.08, 0.63, -0.22, 0.018, 0.15, 0.065, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);
        b.addBox(-0.055, 0.50, 0.02, 0.028, 0.035, 0.14, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.055, 0.50, 0.02, 0.028, 0.035, 0.14, ProceduralMaterialSlot.neutralMetal);

      case FactionId.unitedKingdom:
      case FactionId.france:
      case FactionId.china:
        // Canard-delta fighters (Typhoon chin intake, Rafale refueling probe, J-20 twin canted fins).
        b.addRotatedBox(-0.11, 0.58, 0.16, 0.08, 0.018, 0.04, 0, 0.38, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.11, 0.58, 0.16, 0.08, 0.018, 0.04, 0, -0.38, 0, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addExtrudedPolygon(
          const [(x: -0.07, z: 0.08), (x: -0.33, z: -0.14), (x: -0.31, z: -0.23), (x: -0.07, z: -0.23)],
          0.56,
          0.59,
          ProceduralMaterialSlot.factionPrimary,
          part: MeshPartTag.wingRotor,
        );
        b.addExtrudedPolygon(
          const [(x: 0.07, z: 0.08), (x: 0.07, z: -0.23), (x: 0.31, z: -0.23), (x: 0.33, z: -0.14)],
          0.56,
          0.59,
          ProceduralMaterialSlot.factionPrimary,
          part: MeshPartTag.wingRotor,
        );
        if (faction == FactionId.china) {
          b.addRotatedBox(-0.09, 0.69, -0.25, 0.018, 0.10, 0.07, 0, 0, 0.30, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);
          b.addRotatedBox(0.09, 0.69, -0.25, 0.018, 0.10, 0.07, 0, 0, -0.30, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);
          b.addBox(-0.085, 0.54, 0.10, 0.025, 0.04, 0.11, ProceduralMaterialSlot.neutralMetal);
          b.addBox(0.085, 0.54, 0.10, 0.025, 0.04, 0.11, ProceduralMaterialSlot.neutralMetal);
        } else if (faction == FactionId.france) {
          // Rafale: curved lateral kidney intakes + dorsal spine + starboard refueling probe + wingtip MICA rails.
          b.addBox(0, 0.63, -0.22, 0.02, 0.19, 0.085, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
          b.addBox(0, 0.63, -0.05, 0.04, 0.035, 0.13, ProceduralMaterialSlot.factionUniform);
          b.addBox(-0.09, 0.55, 0.09, 0.028, 0.042, 0.11, ProceduralMaterialSlot.neutralMetal);
          b.addBox(0.09, 0.55, 0.09, 0.028, 0.042, 0.11, ProceduralMaterialSlot.neutralMetal);
          b.addBox(-0.32, 0.56, -0.18, 0.016, 0.022, 0.09, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
          b.addBox(0.32, 0.56, -0.18, 0.016, 0.022, 0.09, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
          b.addBox(0.045, 0.64, 0.25, 0.012, 0.016, 0.08, ProceduralMaterialSlot.neutralMetal);
        } else {
          // Typhoon: large rectangular chin intake + tall single fin + tip EW pod.
          b.addBox(0, 0.63, -0.22, 0.02, 0.21, 0.085, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
          b.addBox(0, 0.84, -0.24, 0.024, 0.028, 0.06, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);
          b.addBox(0, 0.485, 0.08, 0.058, 0.052, 0.13, ProceduralMaterialSlot.neutralMetal);
        }

      case FactionId.germany:
        // Tornado high-swept wing + huge single vertical fin.
        b.addRotatedBox(-0.19, 0.59, -0.05, 0.17, 0.022, 0.08, 0, 0.65, 0, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.wingRotor);
        b.addRotatedBox(0.19, 0.59, -0.05, 0.17, 0.022, 0.08, 0, -0.65, 0, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.63, -0.22, 0.024, 0.22, 0.10, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.japan:
        // F-2 cropped delta + horizontal tailplanes + ventral strakes.
        b.addExtrudedPolygon(
          const [(x: -0.07, z: 0.10), (x: -0.32, z: -0.10), (x: -0.28, z: -0.22), (x: -0.07, z: -0.22)],
          0.56,
          0.59,
          ProceduralMaterialSlot.factionPrimary,
          part: MeshPartTag.wingRotor,
        );
        b.addExtrudedPolygon(
          const [(x: 0.07, z: 0.10), (x: 0.07, z: -0.22), (x: 0.28, z: -0.22), (x: 0.32, z: -0.10)],
          0.56,
          0.59,
          ProceduralMaterialSlot.factionPrimary,
          part: MeshPartTag.wingRotor,
        );
        b.addBox(0, 0.63, -0.21, 0.02, 0.19, 0.08, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addBox(-0.14, 0.57, -0.26, 0.08, 0.015, 0.045, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addBox(0.14, 0.57, -0.26, 0.08, 0.015, 0.045, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.india:
        // HAL Tejas tailless compound delta + bifurcated side intakes.
        b.addExtrudedPolygon(
          const [(x: -0.07, z: 0.15), (x: -0.18, z: 0.0), (x: -0.31, z: -0.20), (x: -0.07, z: -0.22)],
          0.56,
          0.59,
          ProceduralMaterialSlot.factionPrimary,
          part: MeshPartTag.wingRotor,
        );
        b.addExtrudedPolygon(
          const [(x: 0.07, z: 0.15), (x: 0.07, z: -0.22), (x: 0.31, z: -0.20), (x: 0.18, z: 0.0)],
          0.56,
          0.59,
          ProceduralMaterialSlot.factionPrimary,
          part: MeshPartTag.wingRotor,
        );
        b.addBox(0, 0.63, -0.20, 0.02, 0.20, 0.085, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addBox(-0.085, 0.54, 0.06, 0.02, 0.04, 0.08, ProceduralMaterialSlot.neutralMetal);
        b.addBox(0.085, 0.54, 0.06, 0.02, 0.04, 0.08, ProceduralMaterialSlot.neutralMetal);
    }

    // Wing/tail national roundel (`insigniaStar`).
    b.addCylinder(0, 0.72, -0.22, 0.036, 0.024, 0.036, ProceduralMaterialSlot.heroicEmissive, sides: 6, part: MeshPartTag.insigniaStar);
  }

  // ---------------------------------------------------------------------------
  // 11. NAVY (11 distinct surface combatants, capacity = 2)
  // ---------------------------------------------------------------------------
  static void _buildNavy(_MeshBuilder b, FactionId faction) {
    _addPedestal(b, radius: 0.36, baseH: 0.045, ringH: 0.035);
    b.addPassengerSocket(0.0, 0.26, 0.07);
    b.addPassengerSocket(0.0, 0.26, -0.24);

    // Tapered warship hull (`bodyHull`) + transom teamRing stripe.
    final beam = faction == FactionId.israel ? 0.14 : 0.165;
    b.addExtrudedPolygon(
      [
        (x: 0.0, z: 0.37),
        (x: beam, z: 0.16),
        (x: beam, z: -0.33),
        (x: -beam, z: -0.33),
        (x: -beam, z: 0.16),
      ],
      0.08,
      0.24,
      ProceduralMaterialSlot.factionPrimary,
      topScale: 1.04,
    );
    b.addBox(0, 0.14, -0.335, 0.11, 0.05, 0.02, ProceduralMaterialSlot.teamRing);

    // Forward bow deck turret & barrel (`turret` + `barrel`) + aft CIWS + helipad + VLS (+72 tris).
    b.setPivot(MeshPartTag.turret, 0, 0.24, 0.19);
    b.addCylinder(0, 0.24, 0.19, 0.068, 0.075, 0.068, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.turret);
    b.setPivot(MeshPartTag.barrel, 0, 0.28, 0.25);
    b.addBox(0, 0.27, 0.29, 0.018, 0.018, 0.085, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
    b.addBox(0, 0.24, 0.11, 0.09, 0.02, 0.05, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0, 0.24, -0.26, 0.11, 0.018, 0.07, ProceduralMaterialSlot.factionUniform);
    b.addCylinder(0, 0.258, -0.20, 0.035, 0.06, 0.035, ProceduralMaterialSlot.factionAccent, sides: 6);
    b.addBox(-0.11, 0.24, 0.02, 0.025, 0.04, 0.06, ProceduralMaterialSlot.neutralMetal);
    b.addBox(0.11, 0.24, 0.02, 0.025, 0.04, 0.06, ProceduralMaterialSlot.neutralMetal);

    // Distinct national bridge superstructure & radar mast (`wingRotor`).
    b.setPivot(MeshPartTag.wingRotor, 0, 0.50, -0.08);
    switch (faction) {
      case FactionId.usa:
        // Arleigh Burke DDG-51: octagonal SPY-1D deckhouse + angled aft funnel + lattice mast.
        b.addCylinder(0, 0.24, -0.04, 0.125, 0.20, 0.135, ProceduralMaterialSlot.factionAccent, sides: 8, topScaleX: 0.78, topScaleZ: 0.78, part: MeshPartTag.turret);
        b.addBox(0, 0.44, -0.04, 0.024, 0.28, 0.024, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.64, -0.04, 0.11, 0.028, 0.022, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.japan:
        // Maya-Class Aegis DDG: stepped two-tier pyramidal deckhouse + aft hangar.
        b.addCylinder(0, 0.24, -0.06, 0.13, 0.18, 0.15, ProceduralMaterialSlot.factionAccent, sides: 8, topScaleX: 0.80, topScaleZ: 0.80, part: MeshPartTag.turret);
        b.addBox(0, 0.24, -0.21, 0.10, 0.11, 0.07, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.turret);
        b.addBox(0, 0.42, -0.05, 0.026, 0.29, 0.026, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.65, -0.05, 0.12, 0.028, 0.022, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.southKorea:
        // Sejong the Great DDG: heavy Aegis + twin funnels + aft VLS.
        b.addCylinder(0, 0.24, -0.05, 0.125, 0.20, 0.135, ProceduralMaterialSlot.factionAccent, sides: 8, topScaleX: 0.78, topScaleZ: 0.78, part: MeshPartTag.turret);
        b.addBox(0, 0.44, -0.05, 0.024, 0.28, 0.024, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.64, -0.05, 0.11, 0.028, 0.022, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);
        b.addBox(-0.06, 0.24, -0.18, 0.04, 0.14, 0.05, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.turret);
        b.addBox(0.06, 0.24, -0.18, 0.04, 0.14, 0.05, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.turret);

      case FactionId.vietnam:
        // Gepard 3.9 frigate + angled Uran-E anti-ship tubes.
        b.addBox(0, 0.24, -0.06, 0.11, 0.18, 0.14, ProceduralMaterialSlot.factionAccent, topScaleX: 0.80, topScaleZ: 0.80, part: MeshPartTag.turret);
        b.addRotatedBox(-0.10, 0.28, 0.05, 0.032, 0.032, 0.09, -0.35, 0.35, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addRotatedBox(0.10, 0.28, 0.05, 0.032, 0.032, 0.09, -0.35, -0.35, 0, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.barrel);
        b.addBox(0, 0.42, -0.06, 0.024, 0.26, 0.024, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.62, -0.06, 0.10, 0.03, 0.025, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);

      case FactionId.sovietUnion:
        // Kirov heavy missile cruiser: twin towering masts + angled Granit silos.
        b.addBox(0, 0.24, -0.04, 0.125, 0.22, 0.18, ProceduralMaterialSlot.factionAccent, topScaleX: 0.78, topScaleZ: 0.82, part: MeshPartTag.turret);
        b.addBox(0, 0.46, 0.01, 0.024, 0.26, 0.024, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.46, -0.14, 0.022, 0.22, 0.022, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.66, 0.01, 0.11, 0.03, 0.024, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);

      case FactionId.unitedKingdom:
        // Type 45 Daring DDG: tall foremast + spherical SAMPSON radar dome.
        b.addBox(0, 0.24, -0.06, 0.115, 0.17, 0.14, ProceduralMaterialSlot.factionAccent, topScaleX: 0.82, topScaleZ: 0.82, part: MeshPartTag.turret);
        b.addBox(0, 0.41, -0.04, 0.045, 0.26, 0.045, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.wingRotor);
        b.addCylinder(0, 0.67, -0.04, 0.08, 0.11, 0.08, ProceduralMaterialSlot.factionEmblem, sides: 8, topScaleX: 0.75, topScaleZ: 0.75, part: MeshPartTag.wingRotor);

      case FactionId.germany:
        // F125 twin-island superstructure + APAR pyramids.
        b.addBox(0, 0.24, 0.03, 0.11, 0.16, 0.09, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.24, -0.15, 0.11, 0.16, 0.09, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addCone(0, 0.40, 0.03, 0.055, 0.20, 0.055, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addCone(0, 0.40, -0.15, 0.055, 0.18, 0.055, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);

      case FactionId.france:
        // FREMM Aquitaine: clean sloped bridge + tapered pyramid radar mast.
        b.addBox(0, 0.24, -0.05, 0.12, 0.16, 0.15, ProceduralMaterialSlot.factionAccent, topScaleX: 0.84, topScaleZ: 0.84, part: MeshPartTag.turret);
        b.addCone(0, 0.40, -0.05, 0.085, 0.30, 0.085, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.62, -0.05, 0.09, 0.025, 0.022, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.china:
        // Type 055 Renhai: flush foredeck VLS bank + tall integrated stealth mast.
        b.addBox(0, 0.24, 0.10, 0.10, 0.03, 0.07, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.turret);
        b.addBox(0, 0.24, -0.07, 0.125, 0.17, 0.16, ProceduralMaterialSlot.factionAccent, topScaleX: 0.82, topScaleZ: 0.82, part: MeshPartTag.turret);
        b.addCone(0, 0.41, -0.07, 0.075, 0.34, 0.075, ProceduralMaterialSlot.neutralMetal, sides: 6, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.66, -0.07, 0.095, 0.028, 0.022, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);

      case FactionId.india:
        // INS Visakhapatnam: raised BrahMos VLS foredeck housing + MF-STAR octagon mast + dual-step aft hangar + twin funnels.
        b.addBox(0, 0.24, 0.10, 0.095, 0.045, 0.055, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.turret);
        b.addBox(0, 0.24, -0.02, 0.12, 0.17, 0.11, ProceduralMaterialSlot.factionAccent, topScaleX: 0.84, topScaleZ: 0.84, part: MeshPartTag.turret);
        b.addBox(0, 0.24, -0.20, 0.105, 0.11, 0.075, ProceduralMaterialSlot.factionPrimary, part: MeshPartTag.turret);
        b.addBox(-0.058, 0.28, -0.14, 0.032, 0.11, 0.042, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.turret);
        b.addBox(0.058, 0.28, -0.14, 0.032, 0.11, 0.042, ProceduralMaterialSlot.neutralMetal, part: MeshPartTag.turret);
        b.addCylinder(0, 0.41, -0.02, 0.072, 0.16, 0.072, ProceduralMaterialSlot.neutralMetal, sides: 8, topScaleX: 0.72, topScaleZ: 0.72, part: MeshPartTag.wingRotor);
        b.addCone(0, 0.57, -0.02, 0.062, 0.17, 0.062, ProceduralMaterialSlot.factionEmblem, sides: 8, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.67, -0.02, 0.095, 0.025, 0.022, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.wingRotor);

      case FactionId.israel:
        // Sa'ar 6 compact corvette + ELM-2248 radar mast.
        b.addBox(0, 0.24, -0.04, 0.10, 0.16, 0.12, ProceduralMaterialSlot.factionAccent, part: MeshPartTag.turret);
        b.addBox(0, 0.40, -0.04, 0.06, 0.18, 0.06, ProceduralMaterialSlot.neutralMetal, topScaleX: 0.75, topScaleZ: 0.75, part: MeshPartTag.wingRotor);
        b.addBox(0, 0.58, -0.04, 0.09, 0.03, 0.024, ProceduralMaterialSlot.factionEmblem, part: MeshPartTag.wingRotor);
    }
  }
}

final class _MeshBuilder {
  final List<double> _verts = <double>[];
  final List<int> _faces = <int>[];
  final List<double> _normals = <double>[];
  final List<int> _slots = <int>[];
  final List<int> _partTags = <int>[];
  final List<Vector3> _sockets = <Vector3>[];
  final Map<MeshPartTag, Vector3> _pivots = <MeshPartTag, Vector3>{};

  final Vector3 _v0 = Vector3.zero();
  final Vector3 _v1 = Vector3.zero();
  final Vector3 _v2 = Vector3.zero();
  final Vector3 _e1 = Vector3.zero();
  final Vector3 _e2 = Vector3.zero();
  final Vector3 _n = Vector3.zero();

  void setPivot(MeshPartTag part, double x, double y, double z) {
    _pivots[part] = Vector3(
      x.clamp(-FactionUnitMeshBuilder.maxHalfExtentXZ, FactionUnitMeshBuilder.maxHalfExtentXZ),
      y.clamp(0.0, FactionUnitMeshBuilder.maxHeightY),
      z.clamp(-FactionUnitMeshBuilder.maxHalfExtentXZ, FactionUnitMeshBuilder.maxHalfExtentXZ),
    );
  }

  void addPassengerSocket(double x, double y, double z) {
    _sockets.add(
      Vector3(
        x.clamp(-FactionUnitMeshBuilder.maxHalfExtentXZ, FactionUnitMeshBuilder.maxHalfExtentXZ),
        y.clamp(0.0, FactionUnitMeshBuilder.maxHeightY),
        z.clamp(-FactionUnitMeshBuilder.maxHalfExtentXZ, FactionUnitMeshBuilder.maxHalfExtentXZ),
      ),
    );
  }

  int _addVertex(double x, double y, double z) {
    var cx = x.clamp(-FactionUnitMeshBuilder.maxHalfExtentXZ, FactionUnitMeshBuilder.maxHalfExtentXZ);
    final cy = y.clamp(0.0, FactionUnitMeshBuilder.maxHeightY);
    var cz = z.clamp(-FactionUnitMeshBuilder.maxHalfExtentXZ, FactionUnitMeshBuilder.maxHalfExtentXZ);
    final rSq = cx * cx + cz * cz;
    const maxR = FactionUnitMeshBuilder.maxHalfExtentXZ;
    if (rSq > maxR * maxR) {
      final scale = maxR / math.sqrt(rSq);
      cx *= scale;
      cz *= scale;
    }
    final idx = _verts.length ~/ 3;
    _verts.add(cx);
    _verts.add(cy);
    _verts.add(cz);
    return idx;
  }

  void _addFace(
    int i0,
    int i1,
    int i2,
    int i3,
    ProceduralMaterialSlot slot,
    MeshPartTag part,
  ) {
    _faces.add(i0);
    _faces.add(i1);
    _faces.add(i2);
    _faces.add(i3);
    _slots.add(slot.index);
    _partTags.add(part.index);

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
    MeshPartTag part = MeshPartTag.bodyHull,
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

    _addFace(b0, b1, t1, t0, slot, part);
    _addFace(b1, b2, t2, t1, slot, part);
    _addFace(b2, b3, t3, t2, slot, part);
    _addFace(b3, b0, t0, t3, slot, part);
    _addFace(t0, t1, t2, t3, slot, part);
    _addFace(b3, b2, b1, b0, slot, part);
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
    ProceduralMaterialSlot slot, {
    MeshPartTag part = MeshPartTag.bodyHull,
  }) {
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

    _addFace(b0, b1, t1, t0, slot, part);
    _addFace(b1, b2, t2, t1, slot, part);
    _addFace(b2, b3, t3, t2, slot, part);
    _addFace(b3, b0, t0, t3, slot, part);
    _addFace(t0, t1, t2, t3, slot, part);
    _addFace(b3, b2, b1, b0, slot, part);
  }

  void addCylinder(
    double cx,
    double yBottom,
    double cz,
    double radiusX,
    double height,
    double radiusZ,
    ProceduralMaterialSlot slot, {
    int sides = 10,
    double topScaleX = 1.0,
    double topScaleZ = 1.0,
    bool includeCaps = true,
    MeshPartTag part = MeshPartTag.bodyHull,
  }) {
    final yTop = yBottom + height;
    final bottomIndices = <int>[];
    final topIndices = <int>[];

    for (var i = 0; i < sides; i++) {
      final angle = -i * (2.0 * math.pi / sides);
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      bottomIndices.add(_addVertex(cx + cosA * radiusX, yBottom, cz + sinA * radiusZ));
      topIndices.add(
        _addVertex(
          cx + cosA * radiusX * topScaleX,
          yTop,
          cz + sinA * radiusZ * topScaleZ,
        ),
      );
    }

    for (var i = 0; i < sides; i++) {
      final next = (i + 1) % sides;
      _addFace(
        bottomIndices[i],
        bottomIndices[next],
        topIndices[next],
        topIndices[i],
        slot,
        part,
      );
    }

    if (includeCaps) {
      final topCenter = _addVertex(cx, yTop, cz);
      final bottomCenter = _addVertex(cx, yBottom, cz);
      for (var i = 0; i < sides; i++) {
        final next = (i + 1) % sides;
        _addFace(topIndices[i], topIndices[next], topCenter, topCenter, slot, part);
        _addFace(bottomIndices[next], bottomIndices[i], bottomCenter, bottomCenter, slot, part);
      }
    }
  }

  void addCone(
    double cx,
    double yBottom,
    double cz,
    double radiusX,
    double height,
    double radiusZ,
    ProceduralMaterialSlot slot, {
    int sides = 10,
    MeshPartTag part = MeshPartTag.bodyHull,
  }) {
    final baseIndices = <int>[];
    for (var i = 0; i < sides; i++) {
      final angle = -i * (2.0 * math.pi / sides);
      baseIndices.add(
        _addVertex(cx + math.cos(angle) * radiusX, yBottom, cz + math.sin(angle) * radiusZ),
      );
    }
    final apex = _addVertex(cx, yBottom + height, cz);
    final bottomCenter = _addVertex(cx, yBottom, cz);

    for (var i = 0; i < sides; i++) {
      final next = (i + 1) % sides;
      _addFace(baseIndices[i], baseIndices[next], apex, apex, slot, part);
      _addFace(baseIndices[next], baseIndices[i], bottomCenter, bottomCenter, slot, part);
    }
  }

  void addExtrudedPolygon(
    List<({double x, double z})> xzFootprint,
    double yBottom,
    double yTop,
    ProceduralMaterialSlot slot, {
    double topScale = 1.0,
    MeshPartTag part = MeshPartTag.bodyHull,
  }) {
    final n = xzFootprint.length;
    if (n < 3) return;

    var cx = 0.0;
    var cz = 0.0;
    var signedArea = 0.0;
    for (var i = 0; i < n; i++) {
      final p0 = xzFootprint[i];
      final p1 = xzFootprint[(i + 1) % n];
      cx += p0.x;
      cz += p0.z;
      signedArea += p0.x * p1.z - p1.x * p0.z;
    }
    cx /= n;
    cz /= n;

    // Ensure CCW order around +Y when viewed from above (in right-handed X-right, Z-forward,
    // top-down +Y view, CCW corresponds to negative signed area in (x, z)).
    final pts = signedArea > 0 ? xzFootprint.reversed.toList() : xzFootprint;

    final bottomIndices = <int>[];
    final topIndices = <int>[];
    for (final p in pts) {
      bottomIndices.add(_addVertex(p.x, yBottom, p.z));
      topIndices.add(
        _addVertex(cx + (p.x - cx) * topScale, yTop, cz + (p.z - cz) * topScale),
      );
    }

    for (var i = 0; i < n; i++) {
      final next = (i + 1) % n;
      _addFace(
        bottomIndices[i],
        bottomIndices[next],
        topIndices[next],
        topIndices[i],
        slot,
        part,
      );
    }

    final topCenter = _addVertex(cx, yTop, cz);
    final bottomCenter = _addVertex(cx, yBottom, cz);
    for (var i = 0; i < n; i++) {
      final next = (i + 1) % n;
      _addFace(topIndices[i], topIndices[next], topCenter, topCenter, slot, part);
      _addFace(bottomIndices[next], bottomIndices[i], bottomCenter, bottomCenter, slot, part);
    }
  }

  ProceduralMeshPrimitive build() {
    return ProceduralMeshPrimitive(
      vertices: Float32List.fromList(_verts),
      faceIndices: Int32List.fromList(_faces),
      faceNormals: Float32List.fromList(_normals),
      faceSlots: Uint8List.fromList(_slots),
      facePartTags: Uint8List.fromList(_partTags),
      passengerSockets: _sockets,
      partPivots: _pivots,
    );
  }
}
