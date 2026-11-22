import 'dart:ui' show Color;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../models/asset_manifest_model.dart';
import '../../models/faction_model.dart';
import '../../models/piece_model.dart';
import 'faction_mesh_builder.dart';
import 'glb_binary_reader.dart';

export 'faction_mesh_builder.dart'
    show MeshPartTag, ProceduralMaterialSlot, ProceduralMeshPrimitive;

/// Resolved 3D piece handle returned by [PieceAssetProvider].
abstract interface class PieceVisualHandle {
  PieceVisualKey get visualKey;
  double get boundingRadius;
  bool get isGlbBacked;
}

/// Decoupled 3D piece asset registry supporting synchronous procedural 3D
/// meshes and asynchronous Khronos `.glb` payload preloading.
abstract interface class PieceAssetProvider {
  Future<void> preloadAll(AssetManifest manifest);
  PieceVisualHandle resolvePiece(PieceVisualKey key);
  void dispose();
}

/// Resolved procedural 3D piece geometry + faction/heroic/team material palette.
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

/// Faction-aware 3D piece asset provider generating 121 national silhouettes
/// synchronously on Frame 1 via [FactionUnitMeshBuilder] and preloading/verifying
/// bundled `.glb` binaries via [GlbBinaryReader].
final class ProceduralPieceAssetProvider implements PieceAssetProvider {
  ProceduralPieceAssetProvider({
    this._bundle,
    this._preloadGlbs = true,
  });

  static const Color redTeamRingColor = Color(0xFFD32F2F);
  static const Color blueTeamRingColor = Color(0xFF1976D2);
  static const Color heroicGoldColor = Color(0xFFFFD54F);
  static const Color defaultPedestalColor = Color(0xFF455A64);

  final AssetBundle? _bundle;
  final bool _preloadGlbs;

  final Map<(FactionId, PieceType), ProceduralMeshPrimitive> _meshCache =
      <(FactionId, PieceType), ProceduralMeshPrimitive>{};
  final Map<PieceVisualKey, ProceduralPieceVisualHandle> _handleCache =
      <PieceVisualKey, ProceduralPieceVisualHandle>{};
  final Map<String, GlbParsedAsset> _glbCache = <String, GlbParsedAsset>{};

  AssetManifest? _manifest;
  bool _disposed = false;
  int _preloadEpoch = 0;

  int get cachedMeshCount => _meshCache.length;
  int get preloadedGlbCount => _glbCache.length;

  /// Returns the parsed `.glb` metadata for [key] if preloaded, or `null`.
  GlbParsedAsset? preloadedGlbFor(PieceVisualKey key) {
    final effectiveFaction = _resolveEffectiveFaction(key);
    final resolvedKey = key.faction == null
        ? key.copyWith(faction: effectiveFaction)
        : key;
    final path =
        _manifest?.resolveGlbPath(resolvedKey) ??
        'assets/models/pieces/${effectiveFaction.code}_${key.type.snakeCaseName}_lod0.glb';
    return _glbCache[path];
  }

  @override
  Future<void> preloadAll(AssetManifest manifest) async {
    final epoch = ++_preloadEpoch;
    _disposed = false;
    _manifest = manifest;
    _handleCache.clear();

    // Pre-warm all 11 × 11 national procedural mesh geometries synchronously.
    for (final faction in FactionId.values) {
      for (final type in PieceType.values) {
        _meshCache.putIfAbsent(
          (faction, type),
          () => FactionUnitMeshBuilder.build(faction, type),
        );
      }
    }

    if (!_preloadGlbs) {
      return;
    }

    // Collect distinct `.glb` paths from manifest.factionMeshes and verify via GlbBinaryReader.
    final paths = <String>{};
    for (final inner in manifest.factionMeshes.values) {
      paths.addAll(inner.values);
    }
    if (paths.isEmpty) {
      return;
    }

    final activeBundle = _bundle ?? rootBundle;
    for (final path in paths) {
      if (_disposed || epoch != _preloadEpoch) return;
      if (_glbCache.containsKey(path)) continue;
      try {
        final byteData = await activeBundle.load(path);
        if (_disposed || epoch != _preloadEpoch) return;
        final parsed = GlbBinaryReader.parseByteData(byteData);
        if (_disposed || epoch != _preloadEpoch) return;
        _glbCache[path] = parsed;
      } on Object {
        // Safely tolerate missing/unbundled `.glb` entries in mock test bundles;
        // synchronous procedural meshes guarantee Frame-1 rendering regardless.
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
    _preloadEpoch++;
    _handleCache.clear();
    _meshCache.clear();
    _glbCache.clear();
    _manifest = null;
  }

  static FactionId _resolveEffectiveFaction(PieceVisualKey key) {
    return key.faction ??
        (key.side == PlayerSide.red ? FactionId.vietnam : FactionId.usa);
  }

  ProceduralPieceVisualHandle _createHandle(PieceVisualKey key) {
    final effectiveFaction = _resolveEffectiveFaction(key);
    final mesh = _meshCache.putIfAbsent(
      (effectiveFaction, key.type),
      () => FactionUnitMeshBuilder.build(effectiveFaction, key.type),
    );
    final descriptor = _manifest?.findPiece(key);
    final slotColors = _resolveSlotColors(key, effectiveFaction, descriptor);
    return ProceduralPieceVisualHandle(
      visualKey: key,
      boundingRadius: descriptor?.boundingRadius ?? 0.425,
      mesh: mesh,
      slotColors: slotColors,
    );
  }

  List<Color> _resolveSlotColors(
    PieceVisualKey key,
    FactionId effectiveFaction,
    MeshAssetDescriptor? descriptor,
  ) {
    final palette = FactionCatalog.of(effectiveFaction).palette;
    final factionPrimary = Color(palette.primaryHex);
    final factionAccent = Color(palette.accentHex);
    final neutralMetal = Color(palette.neutralMetalHex);
    final factionUniform = Color(palette.uniformHex);
    final factionEmblem = Color(palette.emblemHex);
    final heroicEmissive = key.isHero ? heroicGoldColor : factionEmblem;
    final teamRing =
        key.side == PlayerSide.red ? redTeamRingColor : blueTeamRingColor;

    var basePedestal = key.isHero ? heroicGoldColor : defaultPedestalColor;
    if (!key.isHero && descriptor != null) {
      for (final slot in descriptor.materialSlots) {
        if (slot.slotName == 'mat_base_pedestal') {
          final parsed = _tryParseHexColor(slot.defaultHex);
          if (parsed != null) {
            basePedestal = parsed;
          }
          break;
        }
      }
    }

    // Order strictly matches ProceduralMaterialSlot.values (0..7).
    return List<Color>.unmodifiable(<Color>[
      factionPrimary,
      factionAccent,
      basePedestal,
      neutralMetal,
      heroicEmissive,
      teamRing,
      factionUniform,
      factionEmblem,
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
}
