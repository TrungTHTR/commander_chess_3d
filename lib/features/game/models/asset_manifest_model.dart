import 'package:equatable/equatable.dart';

import 'faction_model.dart';
import 'piece_model.dart';

/// Standardized NLA animation clip names matching `docs/BLENDER_ASSET_CONTRACT.md`.
enum PieceAnimClip {
  idle,
  select,
  move,
  attack,
  capture,
  promote,
  defeat;

  static PieceAnimClip? tryParse(Object? raw) {
    if (raw is String) {
      final normalized = raw.trim().toLowerCase().replaceAll('_', '');
      for (final clip in PieceAnimClip.values) {
        if (clip.name.toLowerCase() == normalized) return clip;
      }
    }
    return null;
  }
}

/// Visual lookup key decoupling domain piece identity from 3D mesh assets.
final class PieceVisualKey extends Equatable {
  const PieceVisualKey({
    required this.type,
    required this.side,
    this.isHero = false,
    this.faction,
  });

  final PieceType type;
  final PlayerSide side;
  final bool isHero;
  final FactionId? faction;

  PieceVisualKey copyWith({
    PieceType? type,
    PlayerSide? side,
    bool? isHero,
    FactionId? faction,
    bool clearFaction = false,
  }) {
    return PieceVisualKey(
      type: type ?? this.type,
      side: side ?? this.side,
      isHero: isHero ?? this.isHero,
      faction: clearFaction ? null : (faction ?? this.faction),
    );
  }

  factory PieceVisualKey.fromJson(Map<String, dynamic> json) {
    return PieceVisualKey(
      type: PieceType.fromJsonValue(
        json['type'] ?? json['pieceType'] ?? json['piece_type'],
      ),
      side: PlayerSide.fromJsonValue(json['side']),
      isHero: _asBool(json['isHero'] ?? json['is_hero']),
      faction: FactionId.tryFromJsonValue(
        json['faction'] ?? json['factionId'] ?? json['faction_id'],
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.name,
        'side': side.name,
        'isHero': isHero,
        if (faction != null) 'faction': faction!.code,
      };

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
  List<Object?> get props => <Object?>[type, side, isHero, faction];
}

/// Level-of-Detail mesh entry for distance-based LOD0/LOD1 selection.
final class MeshLodSpec extends Equatable {
  const MeshLodSpec({
    this.tier = 'lod0',
    required this.maxDistanceSq,
    required this.assetPath,
    this.maxTriangles = 1200,
  });

  final String tier;
  final double maxDistanceSq;
  final String assetPath;
  final int maxTriangles;

  MeshLodSpec copyWith({
    String? tier,
    double? maxDistanceSq,
    String? assetPath,
    int? maxTriangles,
  }) {
    return MeshLodSpec(
      tier: tier ?? this.tier,
      maxDistanceSq: maxDistanceSq ?? this.maxDistanceSq,
      assetPath: assetPath ?? this.assetPath,
      maxTriangles: maxTriangles ?? this.maxTriangles,
    );
  }

  factory MeshLodSpec.fromJson(Map<String, dynamic> json) {
    final rawTier = json['tier'];
    final tierStr = rawTier is int
        ? 'lod$rawTier'
        : (rawTier == null || rawTier.toString().isEmpty)
            ? 'lod0'
            : rawTier.toString();
    return MeshLodSpec(
      tier: tierStr,
      maxDistanceSq: _asDouble(
        json['maxDistanceSq'] ?? json['max_distance_sq'],
        100.0,
      ),
      assetPath: _asString(json['assetPath'] ?? json['asset_path']),
      maxTriangles: _asInt(
        json['maxTriangles'] ?? json['max_triangles'],
        1200,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tier': tier,
        'maxDistanceSq': maxDistanceSq,
        'assetPath': assetPath,
        'maxTriangles': maxTriangles,
      };

  static String _asString(Object? raw, [String fallback = '']) =>
      raw == null ? fallback : raw.toString();

  static double _asDouble(Object? raw, double fallback) {
    if (raw is num) {
      if (!raw.isFinite) {
        throw FormatException('Expected finite numeric value, got $raw');
      }
      return raw.toDouble();
    }
    if (raw is String) {
      final parsed = double.tryParse(raw.trim());
      if (parsed != null) {
        if (!parsed.isFinite) {
          throw FormatException('Expected finite numeric value, got $raw');
        }
        return parsed;
      }
    }
    return fallback;
  }

  static int _asInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) {
      if (!raw.isFinite) {
        throw FormatException('Expected finite numeric value, got $raw');
      }
      return raw.toInt();
    }
    if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
    return fallback;
  }

  @override
  List<Object?> get props => <Object?>[
        tier,
        maxDistanceSq,
        assetPath,
        maxTriangles,
      ];
}

/// Named PBR material slot binding for runtime Red/Blue/Heroic tinting.
final class MaterialSlotBinding extends Equatable {
  const MaterialSlotBinding({
    required this.slotName,
    required this.defaultHex,
    this.heroicHex,
  });

  final String slotName;
  final String defaultHex;
  final String? heroicHex;

  MaterialSlotBinding copyWith({
    String? slotName,
    String? defaultHex,
    String? heroicHex,
  }) {
    return MaterialSlotBinding(
      slotName: slotName ?? this.slotName,
      defaultHex: defaultHex ?? this.defaultHex,
      heroicHex: heroicHex ?? this.heroicHex,
    );
  }

  factory MaterialSlotBinding.fromJson(
    Map<String, dynamic> json, {
    String? slotNameOverride,
    String? heroicHexOverride,
  }) {
    final rawHeroic = json['heroicHex'] ?? json['heroic_hex'];
    return MaterialSlotBinding(
      slotName: slotNameOverride ??
          _asString(json['slotName'] ?? json['slot_name']),
      defaultHex: _asString(
        json['defaultHex'] ??
            json['default_hex'] ??
            json['baseColorHex'] ??
            json['base_color_hex'],
      ),
      heroicHex: heroicHexOverride ?? rawHeroic?.toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'slotName': slotName,
        'defaultHex': defaultHex,
        if (heroicHex != null) 'heroicHex': heroicHex,
      };

  static String _asString(Object? raw, [String fallback = '']) =>
      raw == null ? fallback : raw.toString();

  @override
  List<Object?> get props => <Object?>[slotName, defaultHex, heroicHex];
}

/// Blender `.glb` asset descriptor for a piece variant.
final class MeshAssetDescriptor extends Equatable {
  const MeshAssetDescriptor({
    required this.assetId,
    required this.visualKey,
    required this.glbPath,
    this.rootNodeName = '',
    this.lodTiers = const <MeshLodSpec>[],
    this.boundingRadius = 0.425,
    this.passengerSockets = const <String>[],
    this.materialSlots = const <MaterialSlotBinding>[],
    this.animations = const <PieceAnimClip, String>{},
  });

  final String assetId;
  final PieceVisualKey visualKey;
  final String glbPath;
  final String rootNodeName;
  final List<MeshLodSpec> lodTiers;
  final double boundingRadius;
  final List<String> passengerSockets;
  final List<MaterialSlotBinding> materialSlots;
  final Map<PieceAnimClip, String> animations;

  String get effectiveRootNodeName => rootNodeName.isNotEmpty
      ? rootNodeName
      : 'piece_${visualKey.type.snakeCaseName}';

  MeshAssetDescriptor copyWith({
    String? assetId,
    PieceVisualKey? visualKey,
    String? glbPath,
    String? rootNodeName,
    List<MeshLodSpec>? lodTiers,
    double? boundingRadius,
    List<String>? passengerSockets,
    List<MaterialSlotBinding>? materialSlots,
    Map<PieceAnimClip, String>? animations,
  }) {
    return MeshAssetDescriptor(
      assetId: assetId ?? this.assetId,
      visualKey: visualKey ?? this.visualKey,
      glbPath: glbPath ?? this.glbPath,
      rootNodeName: rootNodeName ?? this.rootNodeName,
      lodTiers: lodTiers != null
          ? List<MeshLodSpec>.unmodifiable(lodTiers)
          : this.lodTiers,
      boundingRadius: boundingRadius ?? this.boundingRadius,
      passengerSockets: passengerSockets != null
          ? List<String>.unmodifiable(passengerSockets)
          : this.passengerSockets,
      materialSlots: materialSlots != null
          ? List<MaterialSlotBinding>.unmodifiable(materialSlots)
          : this.materialSlots,
      animations: animations != null
          ? Map<PieceAnimClip, String>.unmodifiable(animations)
          : this.animations,
    );
  }

  factory MeshAssetDescriptor.fromJson(Map<String, dynamic> json) {
    final rawKey = json['visualKey'] ?? json['visual_key'];
    final visualKey = rawKey is Map<String, dynamic>
        ? PieceVisualKey.fromJson(rawKey)
        : rawKey is Map
            ? PieceVisualKey.fromJson(Map<String, dynamic>.from(rawKey))
            : PieceVisualKey.fromJson(json);

    final rawLods = json['lodTiers'] ?? json['lod_tiers'];
    final lods = <MeshLodSpec>[];
    if (rawLods is List) {
      for (final item in rawLods) {
        if (item is Map<String, dynamic>) {
          lods.add(MeshLodSpec.fromJson(item));
        } else if (item is Map) {
          lods.add(MeshLodSpec.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final rawSockets = json['passengerSockets'] ?? json['passenger_sockets'];
    final sockets = <String>[];
    if (rawSockets is List) {
      for (final item in rawSockets) {
        if (item != null) sockets.add(item.toString());
      }
    } else {
      final legacySocket =
          json['carrySocketName'] ?? json['carry_socket_name'];
      if (legacySocket is String && legacySocket.isNotEmpty) {
        sockets.add(legacySocket);
      }
    }

    final rawHeroicOverrides =
        json['heroicMaterialOverrides'] ?? json['heroic_material_overrides'];
    final heroicBySlot = <String, String>{};
    if (rawHeroicOverrides is Map) {
      for (final entry in rawHeroicOverrides.entries) {
        final slotKey = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          final hex = value['emissiveHex'] ??
              value['emissive_hex'] ??
              value['baseColorHex'] ??
              value['base_color_hex'] ??
              value['heroicHex'] ??
              value['heroic_hex'];
          if (hex != null) {
            heroicBySlot[slotKey] = hex.toString();
          }
        }
      }
    }

    final rawSlots = json['materialSlots'] ?? json['material_slots'];
    final slots = <MaterialSlotBinding>[];
    if (rawSlots is List) {
      for (final item in rawSlots) {
        if (item is Map<String, dynamic>) {
          slots.add(MaterialSlotBinding.fromJson(item));
        } else if (item is Map) {
          slots.add(
            MaterialSlotBinding.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    } else if (rawSlots is Map) {
      for (final entry in rawSlots.entries) {
        final slotName = entry.key.toString();
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          slots.add(
            MaterialSlotBinding.fromJson(
              value,
              slotNameOverride: slotName,
              heroicHexOverride: heroicBySlot[slotName],
            ),
          );
        } else if (value is Map) {
          slots.add(
            MaterialSlotBinding.fromJson(
              Map<String, dynamic>.from(value),
              slotNameOverride: slotName,
              heroicHexOverride: heroicBySlot[slotName],
            ),
          );
        }
      }
    }

    final rawAnimations = json['animations'];
    final parsedAnims = <PieceAnimClip, String>{};
    if (rawAnimations is Map) {
      for (final entry in rawAnimations.entries) {
        final clip = PieceAnimClip.tryParse(entry.key);
        if (clip != null && entry.value != null) {
          parsedAnims[clip] = entry.value.toString();
        }
      }
    }

    final rawRoot = json['rootNodeName'] ?? json['root_node_name'];
    final rootNode = (rawRoot == null || rawRoot.toString().isEmpty)
        ? 'piece_${visualKey.type.snakeCaseName}'
        : rawRoot.toString();

    return MeshAssetDescriptor(
      assetId: _asString(json['assetId'] ?? json['asset_id']),
      visualKey: visualKey,
      glbPath: _asString(json['glbPath'] ?? json['glb_path']),
      rootNodeName: rootNode,
      lodTiers: List<MeshLodSpec>.unmodifiable(lods),
      boundingRadius: _asDouble(
        json['boundingRadius'] ?? json['bounding_radius'],
        0.425,
      ),
      passengerSockets: List<String>.unmodifiable(sockets),
      materialSlots: List<MaterialSlotBinding>.unmodifiable(slots),
      animations: Map<PieceAnimClip, String>.unmodifiable(parsedAnims),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'assetId': assetId,
        'visualKey': visualKey.toJson(),
        'glbPath': glbPath,
        'rootNodeName': effectiveRootNodeName,
        'lodTiers': lodTiers.map((e) => e.toJson()).toList(growable: false),
        'boundingRadius': boundingRadius,
        'passengerSockets': passengerSockets,
        'materialSlots':
            materialSlots.map((e) => e.toJson()).toList(growable: false),
        'animations': <String, String>{
          for (final entry in animations.entries) entry.key.name: entry.value,
        },
      };

  static String _asString(Object? raw, [String fallback = '']) =>
      raw == null ? fallback : raw.toString();

  static double _asDouble(Object? raw, double fallback) {
    if (raw is num) {
      if (!raw.isFinite) {
        throw FormatException('Expected finite numeric value, got $raw');
      }
      return raw.toDouble();
    }
    if (raw is String) {
      final parsed = double.tryParse(raw.trim());
      if (parsed != null) {
        if (!parsed.isFinite) {
          throw FormatException('Expected finite numeric value, got $raw');
        }
        return parsed;
      }
    }
    return fallback;
  }

  @override
  List<Object?> get props => <Object?>[
        assetId,
        visualKey,
        glbPath,
        rootNodeName,
        lodTiers,
        boundingRadius,
        passengerSockets,
        materialSlots,
        animations,
      ];
}

/// Top-level Blender 3D asset registry parsed from `assets/models/asset_manifest.json`.
final class AssetManifest extends Equatable {
  const AssetManifest({
    this.schemaVersion = 1,
    this.unitScaleMeters = 1.0,
    required this.boardGlbPath,
    this.boardRootNodeName = 'board_root',
    required this.pieces,
    this.factionMeshes = const <FactionId, Map<PieceType, String>>{},
  });

  final int schemaVersion;
  final double unitScaleMeters;
  final String boardGlbPath;
  final String boardRootNodeName;
  final List<MeshAssetDescriptor> pieces;
  final Map<FactionId, Map<PieceType, String>> factionMeshes;

  /// Returns the faction-specific `.glb` path for `(faction, type)`, or `null`.
  String? findFactionMeshPath(FactionId faction, PieceType type) =>
      factionMeshes[faction]?[type];

  /// Resolves the best `.glb` path for [key], preferring faction-specific meshes
  /// when [key.faction] is provided and falling back to base [findPiece].
  String? resolveGlbPath(PieceVisualKey key) {
    if (key.faction != null) {
      final factionPath = findFactionMeshPath(key.faction!, key.type);
      if (factionPath != null && factionPath.isNotEmpty) {
        return factionPath;
      }
    }
    return findPiece(key)?.glbPath;
  }

  /// Resolves exact `(type, side, isHero, faction)` match, falling back to
  /// non-hero `(type, side, false, faction)` and then `faction == null` base
  /// descriptors if dedicated faction/hero entries are omitted.
  MeshAssetDescriptor? findPiece(PieceVisualKey key) {
    for (final piece in pieces) {
      if (piece.visualKey == key) return piece;
    }
    if (key.isHero) {
      final nonHeroKey = key.copyWith(isHero: false);
      for (final piece in pieces) {
        if (piece.visualKey == nonHeroKey) return piece;
      }
    }
    if (key.faction != null) {
      final baseFactionKey = key.copyWith(clearFaction: true);
      for (final piece in pieces) {
        if (piece.visualKey == baseFactionKey) return piece;
      }
      if (key.isHero) {
        final baseNonHeroKey = key.copyWith(isHero: false, clearFaction: true);
        for (final piece in pieces) {
          if (piece.visualKey == baseNonHeroKey) return piece;
        }
      }
    }
    return null;
  }

  AssetManifest copyWith({
    int? schemaVersion,
    double? unitScaleMeters,
    String? boardGlbPath,
    String? boardRootNodeName,
    List<MeshAssetDescriptor>? pieces,
    Map<FactionId, Map<PieceType, String>>? factionMeshes,
  }) {
    return AssetManifest(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      unitScaleMeters: unitScaleMeters ?? this.unitScaleMeters,
      boardGlbPath: boardGlbPath ?? this.boardGlbPath,
      boardRootNodeName: boardRootNodeName ?? this.boardRootNodeName,
      pieces: pieces != null
          ? List<MeshAssetDescriptor>.unmodifiable(pieces)
          : this.pieces,
      factionMeshes: factionMeshes != null
          ? _freezeFactionMeshes(factionMeshes)
          : this.factionMeshes,
    );
  }

  factory AssetManifest.fromJson(Map<String, dynamic> json) {
    final rawPieces = json['pieces'];
    final parsedPieces = <MeshAssetDescriptor>[];
    if (rawPieces is List) {
      for (final item in rawPieces) {
        if (item is Map<String, dynamic>) {
          parsedPieces.add(MeshAssetDescriptor.fromJson(item));
        } else if (item is Map) {
          parsedPieces.add(
            MeshAssetDescriptor.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final parsedFactionMeshes = <FactionId, Map<PieceType, String>>{};
    final rawFactionMeshes = json['factionMeshes'] ?? json['faction_meshes'];
    if (rawFactionMeshes is Map) {
      for (final outerEntry in rawFactionMeshes.entries) {
        final faction = FactionId.tryFromJsonValue(outerEntry.key);
        if (faction == null || outerEntry.value is! Map) continue;
        final innerMap = <PieceType, String>{};
        for (final innerEntry in (outerEntry.value as Map).entries) {
          final pieceType = PieceType.tryFromJsonValue(innerEntry.key);
          final rawPath = innerEntry.value;
          if (pieceType != null &&
              rawPath is String &&
              rawPath.trim().isNotEmpty) {
            innerMap[pieceType] = rawPath.trim();
          }
        }
        if (innerMap.isNotEmpty) {
          parsedFactionMeshes[faction] =
              Map<PieceType, String>.unmodifiable(innerMap);
        }
      }
    }

    final rawUnitScale = json['unitScaleMeters'] ?? json['unit_scale_meters'];
    final double unitScaleMeters;
    if (rawUnitScale == null) {
      unitScaleMeters = 1.0;
    } else if (rawUnitScale is num) {
      if (!rawUnitScale.isFinite || rawUnitScale <= 0) {
        throw FormatException(
          'Expected finite positive unitScaleMeters, got $rawUnitScale',
        );
      }
      unitScaleMeters = rawUnitScale.toDouble();
    } else if (rawUnitScale is String) {
      final parsed = double.tryParse(rawUnitScale.trim());
      if (parsed == null || !parsed.isFinite || parsed <= 0) {
        throw FormatException(
          'Expected finite positive unitScaleMeters, got $rawUnitScale',
        );
      }
      unitScaleMeters = parsed;
    } else {
      throw FormatException(
        'Expected finite positive unitScaleMeters, got $rawUnitScale',
      );
    }

    return AssetManifest(
      schemaVersion: _asInt(
        json['schemaVersion'] ?? json['schema_version'],
        1,
      ),
      unitScaleMeters: unitScaleMeters,
      boardGlbPath: _asString(
        json['boardGlbPath'] ?? json['board_glb_path'],
        'assets/models/board/commander_board_11x12.glb',
      ),
      boardRootNodeName: _asString(
        json['boardRootNodeName'] ?? json['board_root_node_name'],
        'board_root',
      ),
      pieces: List<MeshAssetDescriptor>.unmodifiable(parsedPieces),
      factionMeshes:
          Map<FactionId, Map<PieceType, String>>.unmodifiable(parsedFactionMeshes),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'unitScaleMeters': unitScaleMeters,
        'boardGlbPath': boardGlbPath,
        'boardRootNodeName': boardRootNodeName,
        'pieces': pieces.map((e) => e.toJson()).toList(growable: false),
        if (factionMeshes.isNotEmpty)
          'factionMeshes': <String, dynamic>{
            for (final entry in factionMeshes.entries)
              entry.key.code: <String, String>{
                for (final pieceEntry in entry.value.entries)
                  pieceEntry.key.snakeCaseName: pieceEntry.value,
              },
          },
      };

  static Map<FactionId, Map<PieceType, String>> _freezeFactionMeshes(
    Map<FactionId, Map<PieceType, String>> source,
  ) {
    return Map<FactionId, Map<PieceType, String>>.unmodifiable(
      <FactionId, Map<PieceType, String>>{
        for (final entry in source.entries)
          entry.key: Map<PieceType, String>.unmodifiable(entry.value),
      },
    );
  }

  static String _asString(Object? raw, String fallback) {
    if (raw == null) return fallback;
    final str = raw.toString();
    return str.isEmpty ? fallback : str;
  }

  static int _asInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) {
      if (!raw.isFinite) {
        throw FormatException('Expected finite numeric value, got $raw');
      }
      return raw.toInt();
    }
    if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
    return fallback;
  }

  @override
  List<Object?> get props => <Object?>[
        schemaVersion,
        unitScaleMeters,
        boardGlbPath,
        boardRootNodeName,
        pieces,
        factionMeshes,
      ];
}
