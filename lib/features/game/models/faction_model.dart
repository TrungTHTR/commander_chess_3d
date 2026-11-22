import 'package:equatable/equatable.dart';

import 'piece_model.dart';

/// 11 playable national military factions in Commander Chess 3D.
enum FactionId {
  usa,
  vietnam,
  sovietUnion,
  unitedKingdom,
  germany,
  france,
  china,
  japan,
  southKorea,
  india,
  israel;

  /// Canonical `snake_case` identifier used in JSON and `.glb` asset filenames.
  String get code => switch (this) {
        FactionId.usa => 'usa',
        FactionId.vietnam => 'vietnam',
        FactionId.sovietUnion => 'soviet_union',
        FactionId.unitedKingdom => 'united_kingdom',
        FactionId.germany => 'germany',
        FactionId.france => 'france',
        FactionId.china => 'china',
        FactionId.japan => 'japan',
        FactionId.southKorea => 'south_korea',
        FactionId.india => 'india',
        FactionId.israel => 'israel',
      };

  /// Full English display name of the nation.
  String get displayName => switch (this) {
        FactionId.usa => 'United States',
        FactionId.vietnam => 'Vietnam',
        FactionId.sovietUnion => 'Soviet Union',
        FactionId.unitedKingdom => 'United Kingdom',
        FactionId.germany => 'Germany',
        FactionId.france => 'France',
        FactionId.china => 'China',
        FactionId.japan => 'Japan',
        FactionId.southKorea => 'South Korea',
        FactionId.india => 'India',
        FactionId.israel => 'Israel',
      };

  /// Compact tactical tag for HUD badges and compact pickers.
  String get shortCode => switch (this) {
        FactionId.usa => 'USA',
        FactionId.vietnam => 'VN',
        FactionId.sovietUnion => 'USSR',
        FactionId.unitedKingdom => 'UK',
        FactionId.germany => 'DE',
        FactionId.france => 'FR',
        FactionId.china => 'CN',
        FactionId.japan => 'JP',
        FactionId.southKorea => 'KR',
        FactionId.india => 'IN',
        FactionId.israel => 'IL',
      };

  /// High-level summary of national doctrine and visual force identity.
  String get doctrineSummary => switch (this) {
        FactionId.usa =>
          'Combined-arms precision firepower, carrier aviation, and networked armor.',
        FactionId.vietnam =>
          'Asymmetric riverine mobility, layered air defense, and resilient infantry.',
        FactionId.sovietUnion =>
          'Deep-battle armored spearheads, rocket artillery, and strategic missiles.',
        FactionId.unitedKingdom =>
          'Expeditionary naval projection, heavy composite armor, and coastal artillery.',
        FactionId.germany =>
          'Mechanized maneuver warfare, long-barrel armor, and precision self-propelled guns.',
        FactionId.france =>
          'Rapid-deployment wheeled armor, canard air superiority, and expeditionary carriers.',
        FactionId.china =>
          'Massed mechanized divisions, amphibious coastal forces, and mobile missile batteries.',
        FactionId.japan =>
          'Island-chain maritime defense, Aegis surface warfare, and high-tech armor.',
        FactionId.southKorea =>
          'High-tempo armored artillery, mountain infantry, and indigenous stealth wings.',
        FactionId.india =>
          'High-altitude mountain divisions, multi-origin armor, and blue-water carrier groups.',
        FactionId.israel =>
          'High-survivability urban armor, multi-tier air defense, and precision strike.',
      };

  static FactionId? tryFromJsonValue(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final upper = trimmed.toUpperCase();
      for (final faction in FactionId.values) {
        if (faction.shortCode == upper) return faction;
      }
      final normalized = trimmed
          .toLowerCase()
          .replaceAll('_', '')
          .replaceAll('-', '')
          .replaceAll(' ', '');
      for (final faction in FactionId.values) {
        if (faction.name.toLowerCase() == normalized ||
            faction.code.replaceAll('_', '') == normalized ||
            faction.displayName.toLowerCase().replaceAll(' ', '') ==
                normalized) {
          return faction;
        }
      }
    }
    return null;
  }

  static FactionId fromJsonValue(
    Object? raw, {
    FactionId fallback = FactionId.vietnam,
  }) =>
      tryFromJsonValue(raw) ?? fallback;
}

/// Pure-Dart 5-slot ARGB hex palette (`0xAARRGGBB`) for national armor paint,
/// tactical trim, uniforms, neutral metal, and national emblem highlights.
final class FactionColorPalette extends Equatable {
  const FactionColorPalette({
    required this.primaryHex,
    required this.accentHex,
    required this.uniformHex,
    required this.neutralMetalHex,
    required this.emblemHex,
  });

  final int primaryHex;
  final int accentHex;
  final int uniformHex;
  final int neutralMetalHex;
  final int emblemHex;

  FactionColorPalette copyWith({
    int? primaryHex,
    int? accentHex,
    int? uniformHex,
    int? neutralMetalHex,
    int? emblemHex,
  }) {
    return FactionColorPalette(
      primaryHex: primaryHex ?? this.primaryHex,
      accentHex: accentHex ?? this.accentHex,
      uniformHex: uniformHex ?? this.uniformHex,
      neutralMetalHex: neutralMetalHex ?? this.neutralMetalHex,
      emblemHex: emblemHex ?? this.emblemHex,
    );
  }

  factory FactionColorPalette.fromJson(Map<String, dynamic> json) {
    return FactionColorPalette(
      primaryHex: _parseHexInt(
        json['primaryHex'] ?? json['primary_hex'],
        0xFF4E6B42,
      ),
      accentHex: _parseHexInt(
        json['accentHex'] ?? json['accent_hex'],
        0xFFD4AF37,
      ),
      uniformHex: _parseHexInt(
        json['uniformHex'] ?? json['uniform_hex'],
        0xFF3E4F38,
      ),
      neutralMetalHex: _parseHexInt(
        json['neutralMetalHex'] ?? json['neutral_metal_hex'],
        0xFF37474F,
      ),
      emblemHex: _parseHexInt(
        json['emblemHex'] ?? json['emblem_hex'],
        0xFFFFD54F,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'primaryHex': primaryHex,
        'accentHex': accentHex,
        'uniformHex': uniformHex,
        'neutralMetalHex': neutralMetalHex,
        'emblemHex': emblemHex,
      };

  static int _parseHexInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is String) {
      var cleaned = raw.trim();
      if (cleaned.startsWith('#')) {
        cleaned = cleaned.substring(1);
        if (cleaned.length == 6) cleaned = 'FF$cleaned';
        return int.tryParse(cleaned, radix: 16) ?? fallback;
      }
      if (cleaned.startsWith('0x') || cleaned.startsWith('0X')) {
        return int.tryParse(cleaned.substring(2), radix: 16) ?? fallback;
      }
      return int.tryParse(cleaned) ?? fallback;
    }
    return fallback;
  }

  @override
  List<Object?> get props => <Object?>[
        primaryHex,
        accentHex,
        uniformHex,
        neutralMetalHex,
        emblemHex,
      ];
}

/// National military unit identity for a single `(FactionId, PieceType)` pair.
final class FactionUnitProfile extends Equatable {
  const FactionUnitProfile({
    required this.faction,
    required this.pieceType,
    required this.unitDesignation,
    required this.equipmentSummary,
    required this.roleSilhouetteTag,
  });

  final FactionId faction;
  final PieceType pieceType;
  final String unitDesignation;
  final String equipmentSummary;
  final String roleSilhouetteTag;

  FactionUnitProfile copyWith({
    FactionId? faction,
    PieceType? pieceType,
    String? unitDesignation,
    String? equipmentSummary,
    String? roleSilhouetteTag,
  }) {
    return FactionUnitProfile(
      faction: faction ?? this.faction,
      pieceType: pieceType ?? this.pieceType,
      unitDesignation: unitDesignation ?? this.unitDesignation,
      equipmentSummary: equipmentSummary ?? this.equipmentSummary,
      roleSilhouetteTag: roleSilhouetteTag ?? this.roleSilhouetteTag,
    );
  }

  factory FactionUnitProfile.fromJson(Map<String, dynamic> json) {
    return FactionUnitProfile(
      faction: FactionId.fromJsonValue(json['faction']),
      pieceType: PieceType.fromJsonValue(
        json['pieceType'] ?? json['piece_type'],
      ),
      unitDesignation: _asString(
        json['unitDesignation'] ?? json['unit_designation'],
      ),
      equipmentSummary: _asString(
        json['equipmentSummary'] ?? json['equipment_summary'],
      ),
      roleSilhouetteTag: _asString(
        json['roleSilhouetteTag'] ?? json['role_silhouette_tag'],
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'faction': faction.name,
        'pieceType': pieceType.name,
        'unitDesignation': unitDesignation,
        'equipmentSummary': equipmentSummary,
        'roleSilhouetteTag': roleSilhouetteTag,
      };

  static String _asString(Object? raw, [String fallback = '']) =>
      raw == null ? fallback : raw.toString();

  @override
  List<Object?> get props => <Object?>[
        faction,
        pieceType,
        unitDesignation,
        equipmentSummary,
        roleSilhouetteTag,
      ];
}

/// Complete definition for one national faction across all 11 [PieceType]s.
final class FactionDefinition extends Equatable {
  const FactionDefinition({
    required this.id,
    required this.palette,
    required this.units,
  });

  final FactionId id;
  final FactionColorPalette palette;
  final Map<PieceType, FactionUnitProfile> units;

  String get code => id.code;
  String get displayName => id.displayName;
  String get shortCode => id.shortCode;
  String get doctrineSummary => id.doctrineSummary;

  FactionUnitProfile unitFor(PieceType type) {
    final profile = units[type];
    if (profile == null) {
      throw StateError('Missing FactionUnitProfile for ${id.name}.${type.name}');
    }
    return profile;
  }

  FactionDefinition copyWith({
    FactionId? id,
    FactionColorPalette? palette,
    Map<PieceType, FactionUnitProfile>? units,
  }) {
    return FactionDefinition(
      id: id ?? this.id,
      palette: palette ?? this.palette,
      units: units != null
          ? Map<PieceType, FactionUnitProfile>.unmodifiable(units)
          : this.units,
    );
  }

  factory FactionDefinition.fromJson(Map<String, dynamic> json) {
    final rawPalette = json['palette'];
    final paletteMap = rawPalette is Map<String, dynamic>
        ? rawPalette
        : rawPalette is Map
            ? Map<String, dynamic>.from(rawPalette)
            : const <String, dynamic>{};

    final parsedUnits = <PieceType, FactionUnitProfile>{};
    final rawUnits = json['units'];
    if (rawUnits is Map) {
      for (final entry in rawUnits.entries) {
        final type = PieceType.tryFromJsonValue(entry.key);
        if (type != null && entry.value is Map) {
          parsedUnits[type] = FactionUnitProfile.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    return FactionDefinition(
      id: FactionId.fromJsonValue(json['id']),
      palette: FactionColorPalette.fromJson(paletteMap),
      units: Map<PieceType, FactionUnitProfile>.unmodifiable(parsedUnits),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id.name,
        'palette': palette.toJson(),
        'units': <String, dynamic>{
          for (final entry in units.entries) entry.key.name: entry.value.toJson(),
        },
      };

  @override
  List<Object?> get props => <Object?>[id, palette, units];
}

/// Persisted user settings for opposing factions, default camera preset, and theme.
final class GameSettings extends Equatable {
  static const String defaultPresetName = 'classic';

  const GameSettings({
    this.redFaction = FactionId.vietnam,
    this.blueFaction = FactionId.usa,
    this.defaultCameraPreset = defaultPresetName,
    this.isDarkMode = true,
  });

  final FactionId redFaction;
  final FactionId blueFaction;
  final String defaultCameraPreset;
  final bool isDarkMode;

  bool get isMirrorMatch => redFaction == blueFaction;

  FactionId factionFor(PlayerSide side) =>
      side == PlayerSide.red ? redFaction : blueFaction;

  GameSettings copyWith({
    FactionId? redFaction,
    FactionId? blueFaction,
    String? defaultCameraPreset,
    bool? isDarkMode,
  }) {
    return GameSettings(
      redFaction: redFaction ?? this.redFaction,
      blueFaction: blueFaction ?? this.blueFaction,
      defaultCameraPreset: defaultCameraPreset ?? this.defaultCameraPreset,
      isDarkMode: isDarkMode ?? this.isDarkMode,
    );
  }

  factory GameSettings.fromJson(Map<String, dynamic> json) {
    final rawPreset =
        json['defaultCameraPreset'] ?? json['default_camera_preset'];
    final preset = (rawPreset is String && rawPreset.trim().isNotEmpty)
        ? rawPreset.trim()
        : defaultPresetName;

    return GameSettings(
      redFaction: FactionId.fromJsonValue(
        json['redFaction'] ?? json['red_faction'],
        fallback: FactionId.vietnam,
      ),
      blueFaction: FactionId.fromJsonValue(
        json['blueFaction'] ?? json['blue_faction'],
        fallback: FactionId.usa,
      ),
      defaultCameraPreset: preset,
      isDarkMode: _asBool(json['isDarkMode'] ?? json['is_dark_mode'], true),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'redFaction': redFaction.name,
        'blueFaction': blueFaction.name,
        'defaultCameraPreset': defaultCameraPreset,
        'isDarkMode': isDarkMode,
      };

  static bool _asBool(Object? raw, bool fallback) {
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
        redFaction,
        blueFaction,
        defaultCameraPreset,
        isDarkMode,
      ];
}

/// Authoritative catalog of all 11 factions × 11 unit types (121 distinct
/// unit profiles covering all 19 pieces per side on `kStandardCommanderFen`).
abstract final class FactionCatalog {
  static final Map<FactionId, FactionDefinition> _byId =
      Map<FactionId, FactionDefinition>.unmodifiable(
    <FactionId, FactionDefinition>{
      FactionId.usa: _buildUsa(),
      FactionId.vietnam: _buildVietnam(),
      FactionId.sovietUnion: _buildSovietUnion(),
      FactionId.unitedKingdom: _buildUnitedKingdom(),
      FactionId.germany: _buildGermany(),
      FactionId.france: _buildFrance(),
      FactionId.china: _buildChina(),
      FactionId.japan: _buildJapan(),
      FactionId.southKorea: _buildSouthKorea(),
      FactionId.india: _buildIndia(),
      FactionId.israel: _buildIsrael(),
    },
  );

  static final List<FactionDefinition> _allList =
      List<FactionDefinition>.unmodifiable(
    <FactionDefinition>[
      for (final id in FactionId.values) _byId[id]!,
    ],
  );

  static final List<FactionUnitProfile> _allProfiles =
      List<FactionUnitProfile>.unmodifiable(
    <FactionUnitProfile>[
      for (final faction in _allList)
        for (final type in PieceType.values) faction.unitFor(type),
    ],
  );

  static List<FactionDefinition> get all => _allList;

  static FactionDefinition of(FactionId id) => _byId[id]!;

  static FactionUnitProfile unitOf(FactionId id, PieceType type) =>
      of(id).unitFor(type);

  static List<FactionUnitProfile> get allUnitProfiles => _allProfiles;

  static FactionDefinition _buildFaction(
    FactionId id,
    FactionColorPalette palette,
    List<FactionUnitProfile> profiles,
  ) {
    return FactionDefinition(
      id: id,
      palette: palette,
      units: Map<PieceType, FactionUnitProfile>.unmodifiable(
        <PieceType, FactionUnitProfile>{
          for (final profile in profiles) profile.pieceType: profile,
        },
      ),
    );
  }

  static FactionDefinition _buildUsa() {
    return _buildFaction(
      FactionId.usa,
      const FactionColorPalette(
        primaryHex: 0xFF5A6B4C,
        accentHex: 0xFFD4AF37,
        uniformHex: 0xFF6B654B,
        neutralMetalHex: 0xFF3A4248,
        emblemHex: 0xFFF5F5F5,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.commander,
          unitDesignation: '4-Star Joint Commander',
          equipmentSummary:
              'Army Service Dress uniform with peaked garrison cap, four-star shoulder boards, and encrypted SATCOM tactical handset.',
          roleSilhouetteTag: 'peaked_cap_command',
        ),
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.headquarters,
          unitDesignation: 'TOC Tactical Bunker',
          equipmentSummary:
              'HESCO-bastion Tactical Operations Center with reinforced sandbag parapet, folding satellite dish, and dual whip antennas.',
          roleSilhouetteTag: 'sandbag_comms_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.infantry,
          unitDesignation: 'US Rifleman (M4A1 / ACH)',
          equipmentSummary:
              'OCP MultiCam combat uniform, Advanced Combat Helmet with NVG shroud, IOTV plate carrier, and M4A1 carbine with ACOG optic.',
          roleSilhouetteTag: 'ach_helmet_carbine',
        ),
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.militia,
          unitDesignation: 'National Guard Scout',
          equipmentSummary:
              'OCP field shirt with patrol boonie hat, light chest rig, and Mk 14 EBR designated marksman rifle.',
          roleSilhouetteTag: 'boonie_hat_marksman',
        ),
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.engineer,
          unitDesignation: 'M1150 Assault Breacher',
          equipmentSummary:
              'Abrams-chassis combat engineering hull with full-width V-shaped mine plow, lane-marking pods, and armored cupola.',
          roleSilhouetteTag: 'dozer_blade_rig',
        ),
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.tank,
          unitDesignation: 'M1A2 SEP v3 Abrams',
          equipmentSummary:
              'Composite Chobham-armored wedge turret, 120mm M256 smoothbore cannon, CROWS remote weapon station, and Coyote Tan CARC coat.',
          roleSilhouetteTag: 'composite_wedge_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.artillery,
          unitDesignation: 'M109A7 Paladin',
          equipmentSummary:
              'Tracked self-propelled howitzer with 155mm L/39 M284 tube, muzzle brake, travel lock, and armored bustle turret.',
          roleSilhouetteTag: 'long_howitzer_spg',
        ),
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'M-SHORAD Stryker',
          equipmentSummary:
              '8x8 Stryker armored chassis topped with dual-pod Stinger/Longbow Hellfire turret and 30mm XM914 chain gun.',
          roleSilhouetteTag: 'wheeled_sam_pod',
        ),
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.missile,
          unitDesignation: 'M142 HIMARS MLRS',
          equipmentSummary:
              'High-mobility 6x6 FMTV armored cab carrying an elevating 6-tube GMLRS / ATACMS rocket launcher pod.',
          roleSilhouetteTag: 'wheeled_rocket_pod',
        ),
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.airForce,
          unitDesignation: 'F-22A Raptor',
          equipmentSummary:
              'Twin-engine stealth air-superiority fighter with diamond cropped-delta wings, canted twin tails, and thrust-vectoring nozzles.',
          roleSilhouetteTag: 'stealth_twin_tail',
        ),
        FactionUnitProfile(
          faction: FactionId.usa,
          pieceType: PieceType.navy,
          unitDesignation: 'Arleigh Burke DDG-51',
          equipmentSummary:
              'Aegis guided-missile destroyer with octagonal SPY-1D phased-array deckhouse, Mk 45 5-inch gun, and helipad aft.',
          roleSilhouetteTag: 'aegis_stealth_destroyer',
        ),
      ],
    );
  }

  static FactionDefinition _buildVietnam() {
    return _buildFaction(
      FactionId.vietnam,
      const FactionColorPalette(
        primaryHex: 0xFF3E5F34,
        accentHex: 0xFFFFC107,
        uniformHex: 0xFF4B663E,
        neutralMetalHex: 0xFF37474F,
        emblemHex: 0xFFE53935,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.commander,
          unitDesignation: 'Tư Lệnh Chiến Dịch',
          equipmentSummary:
              'K20 olive-green campaign uniform with sun pith helmet (mũ cối) bearing golden star insignia, field binoculars, and map case.',
          roleSilhouetteTag: 'pith_helmet_command',
        ),
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.headquarters,
          unitDesignation: 'Sở Chỉ Huy Địa Đạo',
          equipmentSummary:
              'Reinforced jungle command bunker with camouflaged timber roof, earthen berm, and HF field radio mast.',
          roleSilhouetteTag: 'camouflage_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.infantry,
          unitDesignation: 'Bộ Binh (AKM / Mũ Cối)',
          equipmentSummary:
              'PAVN K20 olive-drab uniform, classic pith helmet with foliage netting, chest ammo pouches, and AKM 7.62mm rifle.',
          roleSilhouetteTag: 'pith_helmet_rifle',
        ),
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.militia,
          unitDesignation: 'Dân Quân Du Kích',
          equipmentSummary:
              'Black-indigo militia tunic with woven conical nón lá / soft field cap, bandolier, and SKS carbine.',
          roleSilhouetteTag: 'conical_hat_carbine',
        ),
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.engineer,
          unitDesignation: 'Công Binh Vượt Sông (PMP)',
          equipmentSummary:
              'Heavy 6x6 military bridging truck carrying folded PMP steel pontoon deck sections for rapid river-crossing.',
          roleSilhouetteTag: 'pontoon_bridge_truck',
        ),
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.tank,
          unitDesignation: 'T-90S / T-54B',
          equipmentSummary:
              'Low-silhouette cast-dome turret with 125mm 2A46M smoothbore cannon, Kontakt-5 ERA bricks, and Shtora IR dazzlers.',
          roleSilhouetteTag: 'cast_dome_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.artillery,
          unitDesignation: 'Pháo 130mm M-46',
          equipmentSummary:
              'Long-range 130mm towed field gun with split trail legs, heavy wheeled carriage, and armored gun shield.',
          roleSilhouetteTag: 'towed_split_trail_gun',
        ),
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'Pháo Cao Xạ 57mm S-60',
          equipmentSummary:
              'Elevating 57mm automatic anti-aircraft mount on cruciform outriggers with optical fire-control director.',
          roleSilhouetteTag: 'twin_flak_mount',
        ),
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.missile,
          unitDesignation: 'Tổ Hợp S-300PMU1',
          equipmentSummary:
              'Heavy 8x8 MAZ-543M transporter-erector-launcher elevating four vertical cylindrical surface-to-air missile canisters.',
          roleSilhouetteTag: 'vertical_tel_canister',
        ),
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.airForce,
          unitDesignation: 'Su-30MK2V Flanker',
          equipmentSummary:
              'Twin-engine multirole heavy fighter with wide blended fuselage, twin vertical tail fins, and maritime strike pylons.',
          roleSilhouetteTag: 'flanker_twin_fin',
        ),
        FactionUnitProfile(
          faction: FactionId.vietnam,
          pieceType: PieceType.navy,
          unitDesignation: 'Tàu Hộ Vệ Gepard 3.9',
          equipmentSummary:
              'Stealth guided-missile frigate with angled superstructure, AK-176 bow turret, Uran-E anti-ship tubes, and radar mast.',
          roleSilhouetteTag: 'guided_frigate_mast',
        ),
      ],
    );
  }

  static FactionDefinition _buildSovietUnion() {
    return _buildFaction(
      FactionId.sovietUnion,
      const FactionColorPalette(
        primaryHex: 0xFF475C38,
        accentHex: 0xFFE0A800,
        uniformHex: 0xFF6E6447,
        neutralMetalHex: 0xFF333C42,
        emblemHex: 0xFFD32F2F,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.commander,
          unitDesignation: 'Marshal of the USSR',
          equipmentSummary:
              'Khaki service greatcoat over striped telnyashka, fur ushanka / marshal peaked cap with red star crest, and Makarov holster.',
          roleSilhouetteTag: 'ushanka_fur_command',
        ),
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.headquarters,
          unitDesignation: 'Fortified Staff Pillbox',
          equipmentSummary:
              'Octagonal reinforced concrete command pillbox with firing slits, armored cupola hatch, and Whip-antenna array.',
          roleSilhouetteTag: 'octagonal_concrete_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.infantry,
          unitDesignation: 'Motor Rifleman (AK-74)',
          equipmentSummary:
              'Afghanka khaki field uniform, SSh-68 stamped steel helmet, canvas magazine rig, and AK-74 5.45mm rifle with bakelite mag.',
          roleSilhouetteTag: 'ssh68_steel_helmet',
        ),
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.militia,
          unitDesignation: 'Partisan Conscript (PPSh-41)',
          equipmentSummary:
              'Quilted telogreika jacket, pilotka garrison cap, drum-fed PPSh-41 submachine gun, and canvas satchel.',
          roleSilhouetteTag: 'garrison_cap_smg',
        ),
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.engineer,
          unitDesignation: 'BAT-2 Armored Tracklayer',
          equipmentSummary:
              'Tracked heavy route-clearing engineering vehicle with articulated V-dozer blade and rear hydraulic crane.',
          roleSilhouetteTag: 'armored_blade_crawler',
        ),
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.tank,
          unitDesignation: 'T-72B Obr. 1989',
          equipmentSummary:
              '4BO Russian Green hull with Kontakt-5 explosive reactive armor wedge tiles, 125mm gun, and external rear fuel drums.',
          roleSilhouetteTag: 'era_dome_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.artillery,
          unitDesignation: '2S19 Msta-S',
          equipmentSummary:
              'Tracked 152mm heavy self-propelled howitzer with large boxy turret, fume extractor barrel, and recoil spades.',
          roleSilhouetteTag: 'heavy_tracked_spg',
        ),
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'ZSU-23-4 Shilka',
          equipmentSummary:
              'Armored tracked SPAAG mounting four water-cooled 23mm autocannons beside a folding Gun Dish tracking radar.',
          roleSilhouetteTag: 'quad_barrel_radar_aa',
        ),
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.missile,
          unitDesignation: '9K72 Elbrus (Scud-B)',
          equipmentSummary:
              'MAZ-543 8x8 heavy wheeled TEL carrying a single long-range tactical ballistic missile on an elevating cradle.',
          roleSilhouetteTag: 'heavy_eight_wheel_tel',
        ),
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.airForce,
          unitDesignation: 'MiG-29 Fulcrum',
          equipmentSummary:
              'Swept-wing twin-engine fighter with wide lifting-body strakes, twin underslung intakes, and canted vertical stabilizers.',
          roleSilhouetteTag: 'swept_twin_intake',
        ),
        FactionUnitProfile(
          faction: FactionId.sovietUnion,
          pieceType: PieceType.navy,
          unitDesignation: 'Kirov Battlecruiser',
          equipmentSummary:
              'Nuclear-powered heavy missile cruiser with stepped superstructure, angled P-700 Granit silos, and towering radar masts.',
          roleSilhouetteTag: 'heavy_missile_cruiser',
        ),
      ],
    );
  }

  static FactionDefinition _buildUnitedKingdom() {
    return _buildFaction(
      FactionId.unitedKingdom,
      const FactionColorPalette(
        primaryHex: 0xFF42523B,
        accentHex: 0xFFC8A951,
        uniformHex: 0xFF535E42,
        neutralMetalHex: 0xFF37424A,
        emblemHex: 0xFFC62828,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.commander,
          unitDesignation: 'Field Marshal HQ',
          equipmentSummary:
              'British DPM / MTP tunic with crimson-banded peaked cap or maroon officer beret, Sam Browne belt, and swagger baton.',
          roleSilhouetteTag: 'beret_command_rig',
        ),
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.headquarters,
          unitDesignation: 'Royal Command Post',
          equipmentSummary:
              'Reinforced blast-walled command shelter with corrugated steel roof, camouflage scrim, and Bowman antenna mast.',
          roleSilhouetteTag: 'reinforced_blast_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.infantry,
          unitDesignation: 'Royal Rifleman (SA80A3)',
          equipmentSummary:
              'British Woodland DPM / MTP combat smock, Mk 7 ballistic helmet with scrim net, Osprey armor, and L85A3 bullpup rifle.',
          roleSilhouetteTag: 'mk7_helmet_bullpup',
        ),
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.militia,
          unitDesignation: 'Territorial Pathfinder',
          equipmentSummary:
              'Lightweight patrol webbing, distinctive maroon/khaki beret, and L119A2 compact carbine.',
          roleSilhouetteTag: 'maroon_beret_carbine',
        ),
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.engineer,
          unitDesignation: 'Trojan AVRE',
          equipmentSummary:
              'Challenger-based armored combat engineer tank equipped with hydraulic excavator arm and full-width mine-clearing plow.',
          roleSilhouetteTag: 'excavator_arm_tank',
        ),
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.tank,
          unitDesignation: 'Challenger 2',
          equipmentSummary:
              'Dorchester Chobham-armored heavy MBT with 120mm L30A1 rifled gun, armored side skirts, and British Bronze Green finish.',
          roleSilhouetteTag: 'chobham_slab_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.artillery,
          unitDesignation: 'AS-90 Braveheart',
          equipmentSummary:
              'Tracked 155mm self-propelled howitzer featuring a tall rectangular turret, muzzle reference sensor, and fume extractor.',
          roleSilhouetteTag: 'box_turret_howitzer',
        ),
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'Stormer HVM Starstreak',
          equipmentSummary:
              'Tracked Stormer armored chassis carrying an 8-round Starstreak high-velocity missile turret and panoramic IR sight.',
          roleSilhouetteTag: 'tracked_hvm_launcher',
        ),
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.missile,
          unitDesignation: 'M270B1 GMLRS',
          equipmentSummary:
              'Tracked armored rocket artillery carrier with twin 6-cell guided MLRS pods and reinforced cab.',
          roleSilhouetteTag: 'tracked_twin_pod_mlrs',
        ),
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.airForce,
          unitDesignation: 'Eurofighter Typhoon',
          equipmentSummary:
              'Agile delta-wing swing-role fighter with forward canards, rectangular chin intake, and single tall vertical tail.',
          roleSilhouetteTag: 'canard_delta_single_tail',
        ),
        FactionUnitProfile(
          faction: FactionId.unitedKingdom,
          pieceType: PieceType.navy,
          unitDesignation: 'Type 45 Daring DDG',
          equipmentSummary:
              'Stealth air-defense destroyer distinguished by its tall foremast topped by the rotating spherical SAMPSON radar dome.',
          roleSilhouetteTag: 'faceted_sampson_mast',
        ),
      ],
    );
  }

  static FactionDefinition _buildGermany() {
    return _buildFaction(
      FactionId.germany,
      const FactionColorPalette(
        primaryHex: 0xFF4B5440,
        accentHex: 0xFFB0BEC5,
        uniformHex: 0xFF565E4A,
        neutralMetalHex: 0xFF2F383E,
        emblemHex: 0xFFD9A404,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.commander,
          unitDesignation: 'Generalinspekteur',
          equipmentSummary:
              'Bundeswehr Flecktarn field jacket with silver-piped peaked officer cap, tactical headset, and armored command baton.',
          roleSilhouetteTag: 'visor_peaked_command',
        ),
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.headquarters,
          unitDesignation: 'Gefechtsstand Shelter',
          equipmentSummary:
              'Modular angular steel command shelter with armored blast doors, NBC filtration vents, and telescopic mast.',
          roleSilhouetteTag: 'angular_steel_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.infantry,
          unitDesignation: 'Panzergrenadier (G36)',
          equipmentSummary:
              '5-color Flecktarn combat suit, M92 Gefechtshelm with tactical goggles, IdZ vest, and HK G36 rifle with integrated dual optic.',
          roleSilhouetteTag: 'helm_goggles_rifle',
        ),
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.militia,
          unitDesignation: 'Heimatschutz Scout',
          equipmentSummary:
              'Flecktarn field blouse with peaked Feldmütze cap, light patrol harness, and HK416A7 carbine.',
          roleSilhouetteTag: 'field_cap_carbine',
        ),
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.engineer,
          unitDesignation: 'Dachs Pionierpanzer',
          equipmentSummary:
              'Leopard-based armored engineer tank fitted with telescopic excavator boom, winch, and wide hydraulic dozer blade.',
          roleSilhouetteTag: 'crane_arm_dozer',
        ),
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.tank,
          unitDesignation: 'Leopard 2A7',
          equipmentSummary:
              'Signature arrowhead spaced-armor turret cheeks, long L/55 120mm Rheinmetall smoothbore barrel, and Iron Cross markings.',
          roleSilhouetteTag: 'arrowhead_wedge_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.artillery,
          unitDesignation: 'PzH 2000',
          equipmentSummary:
              'Heavy tracked 155mm L/52 self-propelled howitzer with rear-mounted turret, slotted muzzle brake, and high hull roofline.',
          roleSilhouetteTag: 'extended_52cal_spg',
        ),
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'Flakpanzer Gepard',
          equipmentSummary:
              'Twin 35mm Oerlikon KDA autocannons mounted laterally on an armored turret with search and tracking radar dishes.',
          roleSilhouetteTag: 'twin_35mm_radar_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.missile,
          unitDesignation: 'MARS II MLRS',
          equipmentSummary:
              'Tracked armored rocket artillery system carrying dual 6-tube European GMLRS pods on an elevating turntable.',
          roleSilhouetteTag: 'armored_cab_rocket_pod',
        ),
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.airForce,
          unitDesignation: 'Panavia Tornado IDS',
          equipmentSummary:
              'Twin-engine strike jet featuring variable-geometry swept wings, tall swept vertical fin, and tandem cockpit.',
          roleSilhouetteTag: 'variable_sweep_wing',
        ),
        FactionUnitProfile(
          faction: FactionId.germany,
          pieceType: PieceType.navy,
          unitDesignation: 'F125 Baden-Württemberg',
          equipmentSummary:
              'Stabilization frigate with distinctive twin-island superstructure, stealth-angled bow hull, and APAR radar pyramids.',
          roleSilhouetteTag: 'twin_island_frigate',
        ),
      ],
    );
  }

  static FactionDefinition _buildFrance() {
    return _buildFaction(
      FactionId.france,
      const FactionColorPalette(
        primaryHex: 0xFF4F5D43,
        accentHex: 0xFFE6B800,
        uniformHex: 0xFF6B684E,
        neutralMetalHex: 0xFF39434B,
        emblemHex: 0xFF1E88E5,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.commander,
          unitDesignation: "Général d'Armée",
          equipmentSummary:
              'French CCE camouflage jacket with gold-braided cylindrical képi command cap, star insignia, and encrypted field tablet.',
          roleSilhouetteTag: 'kepi_command_rig',
        ),
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.headquarters,
          unitDesignation: 'Poste de Commandement',
          equipmentSummary:
              'Vaulted-arch reinforced concrete command shelter with armored visor ports and tactical Syracuse dish.',
          roleSilhouetteTag: 'vaulted_arch_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.infantry,
          unitDesignation: 'Fantassin FELIN (HK416F)',
          equipmentSummary:
              'CCE Central Europe camouflage, Spectra/FELIN helmet with digital visor monocle, and HK416F 5.56mm rifle.',
          roleSilhouetteTag: 'visor_comms_rifle',
        ),
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.militia,
          unitDesignation: 'Chasseur Alpin',
          equipmentSummary:
              'Mountain scout uniform with wide traditional alpine tarte beret, climbing harness, and FAMAS/HK carbine.',
          roleSilhouetteTag: 'wide_beret_marksman',
        ),
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.engineer,
          unitDesignation: 'EBG Génie Sapeur',
          equipmentSummary:
              'AMX-30-derived armored engineering tractor with front dozer blade and overhead hydraulic demolition boom.',
          roleSilhouetteTag: 'armored_boom_sapper',
        ),
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.tank,
          unitDesignation: 'AMX-56 Leclerc',
          equipmentSummary:
              'Compact autoloader turret with modular composite side blocks, 120mm CN120-26 L/52 gun, and commander panoramic sight.',
          roleSilhouetteTag: 'compact_autoloader_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.artillery,
          unitDesignation: 'CAESAR 155mm',
          equipmentSummary:
              '6x6 armored tactical truck mounting an exposed rear-deck 155mm L/52 howitzer with hydraulic ground spade.',
          roleSilhouetteTag: 'wheeled_open_howitzer',
        ),
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'Crotale NG',
          equipmentSummary:
              'Wheeled armored air-defense vehicle with 8-cell VT1 missile launcher turret and central monopulse tracking radar.',
          roleSilhouetteTag: 'wheeled_octuple_sam',
        ),
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.missile,
          unitDesignation: 'LRU Lance-Roquettes',
          equipmentSummary:
              'Armored tracked rocket artillery launcher with twin 6-round guided rocket pods and French CCE tricolor coat.',
          roleSilhouetteTag: 'armored_twin_pod_mlrs',
        ),
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.airForce,
          unitDesignation: 'Dassault Rafale',
          equipmentSummary:
              'Omnirole twin-engine delta fighter with close-coupled foreplanes, curved side intakes, and swept single fin.',
          roleSilhouetteTag: 'coupled_canard_delta',
        ),
        FactionUnitProfile(
          faction: FactionId.france,
          pieceType: PieceType.navy,
          unitDesignation: 'FREMM Aquitaine',
          equipmentSummary:
              'Stealth multi-mission frigate featuring a clean sloped hull and distinctive tapered pyramid radar mast.',
          roleSilhouetteTag: 'stealth_cone_frigate',
        ),
      ],
    );
  }

  static FactionDefinition _buildChina() {
    return _buildFaction(
      FactionId.china,
      const FactionColorPalette(
        primaryHex: 0xFF3D5941,
        accentHex: 0xFFFFB300,
        uniformHex: 0xFF4E6247,
        neutralMetalHex: 0xFF313A40,
        emblemHex: 0xFFD32F2F,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.commander,
          unitDesignation: 'Theater Command HQ',
          equipmentSummary:
              'Type 21 Xingkong tactical uniform with gold-piped peaked command cap, PLA chest ribbon rack, and command intercom.',
          roleSilhouetteTag: 'pla_peaked_command',
        ),
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.headquarters,
          unitDesignation: 'C4ISR Command Bunker',
          equipmentSummary:
              'Hardened theater command bunker crowned with a geodesic radome and phased-array relay antennas.',
          roleSilhouetteTag: 'antenna_dome_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.infantry,
          unitDesignation: 'PLA Rifleman (QBZ-191)',
          equipmentSummary:
              'Type 07/21 woodland digicam uniform, QGF-11 aramid helmet, tactical chest rig, and QBZ-191 5.8mm assault rifle.',
          roleSilhouetteTag: 'qgf_helmet_bullpup',
        ),
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.militia,
          unitDesignation: 'Reserve Militia Scout',
          equipmentSummary:
              'Woodland digital field uniform with soft patrol cap, utility webbing, and QBZ-95B compact carbine.',
          roleSilhouetteTag: 'soft_cap_carbine',
        ),
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.engineer,
          unitDesignation: 'GSL-130 Mineclearer',
          equipmentSummary:
              'Armored tracked engineering vehicle equipped with heavy front mine-clearing roller plow and rocket line-charge rack.',
          roleSilhouetteTag: 'roller_plow_tank',
        ),
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.tank,
          unitDesignation: 'ZTZ-99A',
          equipmentSummary:
              'Sloped arrowhead FY-4 ERA turret front, 125mm ZPT-98 smoothbore gun, and laser active-protection mast.',
          roleSilhouetteTag: 'sloped_era_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.artillery,
          unitDesignation: 'PLZ-05 155mm',
          equipmentSummary:
              'Tracked self-propelled howitzer with elongated 52-caliber barrel, wide muzzle brake, and spacious welded turret.',
          roleSilhouetteTag: 'long_muzzle_brake_spg',
        ),
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'PGZ-09 Twin-35',
          equipmentSummary:
              'Tracked SPAAG mounting dual 35mm autocannons, side-mounted missile rails, and rotating rear acquisition radar.',
          roleSilhouetteTag: 'track_twin_cannon_radar',
        ),
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.missile,
          unitDesignation: 'PHL-16 / DF-16 TEL',
          equipmentSummary:
              'Heavy 8x8 / 10x10 transporter-erector-launcher carrying modular long-range rocket and ballistic missile canisters.',
          roleSilhouetteTag: 'ten_wheel_erector_tel',
        ),
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.airForce,
          unitDesignation: 'J-20 Mighty Dragon',
          equipmentSummary:
              'Long-fuselage fifth-generation stealth fighter with forward canards, DSI intakes, and all-moving canted twin tails.',
          roleSilhouetteTag: 'canard_stealth_twin_fin',
        ),
        FactionUnitProfile(
          faction: FactionId.china,
          pieceType: PieceType.navy,
          unitDesignation: 'Type 055 Renhai',
          equipmentSummary:
              'Large stealth guided-missile destroyer/cruiser with flush foredeck, 112 VLS cells, and sleek integrated mast.',
          roleSilhouetteTag: 'integrated_mast_cruiser',
        ),
      ],
    );
  }

  static FactionDefinition _buildJapan() {
    return _buildFaction(
      FactionId.japan,
      const FactionColorPalette(
        primaryHex: 0xFF4A583E,
        accentHex: 0xFFFBC02D,
        uniformHex: 0xFF5B634A,
        neutralMetalHex: 0xFF363F45,
        emblemHex: 0xFFE53935,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.commander,
          unitDesignation: 'JSDF Joint Chief',
          equipmentSummary:
              'JGSDF olive-khaki dress tunic with gold-braided visor cap, sakura rank stars, and tactical field handset.',
          roleSilhouetteTag: 'jsdf_visor_command',
        ),
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.headquarters,
          unitDesignation: 'Coastal Command Shelter',
          equipmentSummary:
              'Stepped reinforced concrete island-defense bunker with armored shutter embrasures and radar relay.',
          roleSilhouetteTag: 'stepped_concrete_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.infantry,
          unitDesignation: 'JGSDF Rifleman (Type 20)',
          equipmentSummary:
              'Type 2 camouflage uniform, Type 88 Kevlar helmet, Type 18 body armor, and Howa Type 20 5.56mm rifle.',
          roleSilhouetteTag: 'type88_helmet_rifle',
        ),
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.militia,
          unitDesignation: 'Home Island Ranger',
          equipmentSummary:
              'Type 2 woodland patrol uniform with structured work cap, chest harness, and Type 89 folding-stock carbine.',
          roleSilhouetteTag: 'patrol_cap_carbine',
        ),
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.engineer,
          unitDesignation: 'Type 91 Tank Bridge',
          equipmentSummary:
              'Tracked armored bridgelayer carrying an overhead scissor-folding steel assault span for river crossings.',
          roleSilhouetteTag: 'folding_scissors_bridge',
        ),
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.tank,
          unitDesignation: 'Type 10 Hitomaru',
          equipmentSummary:
              'Lightweight modular-armor MBT with compact angular turret, 120mm L/44 smoothbore cannon, and side skirts.',
          roleSilhouetteTag: 'compact_modular_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.artillery,
          unitDesignation: 'Type 99 155mm HSP',
          equipmentSummary:
              'Tracked 155mm L/52 self-propelled howitzer featuring a tall boxy turret, automated loader bustle, and muzzle brake.',
          roleSilhouetteTag: 'tall_box_howitzer',
        ),
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'Type 87 Guntank',
          equipmentSummary:
              'Armored anti-aircraft tank with twin external 35mm Oerlikon cannon pods flanking a central radar turret.',
          roleSilhouetteTag: 'twin_side_pod_aa',
        ),
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.missile,
          unitDesignation: 'Type 12 SSM Launcher',
          equipmentSummary:
              'Heavy 8x8 coastal defense missile truck carrying an elevating 6-tube anti-ship / surface-strike canister rack.',
          roleSilhouetteTag: 'coastal_canister_truck',
        ),
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.airForce,
          unitDesignation: 'Mitsubishi F-2',
          equipmentSummary:
              'Maritime multirole fighter with enlarged cropped-delta wings, chin intake, bubble canopy, and ventral stabilizer strakes.',
          roleSilhouetteTag: 'blended_delta_single_fin',
        ),
        FactionUnitProfile(
          faction: FactionId.japan,
          pieceType: PieceType.navy,
          unitDesignation: 'Maya-Class Aegis DDG',
          equipmentSummary:
              'JMSDF guided-missile destroyer with stepped pyramidal deckhouse, SPY-1D(V) faces, and stealth lattice mast.',
          roleSilhouetteTag: 'pyramidal_phased_ddg',
        ),
      ],
    );
  }

  static FactionDefinition _buildSouthKorea() {
    return _buildFaction(
      FactionId.southKorea,
      const FactionColorPalette(
        primaryHex: 0xFF495A47,
        accentHex: 0xFFFFCA28,
        uniformHex: 0xFF5D6659,
        neutralMetalHex: 0xFF353E45,
        emblemHex: 0xFF1976D2,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.commander,
          unitDesignation: 'ROK Field Commander',
          equipmentSummary:
              'ROK Granite B digital service uniform with peaked commander visor cap, gold star rank, and tactical radio.',
          roleSilhouetteTag: 'beret_visor_command',
        ),
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.headquarters,
          unitDesignation: 'DMZ Command Bunker',
          equipmentSummary:
              'Sloped rebar-concrete fortified command bunker with steel blast overhang and tactical microwave dish.',
          roleSilhouetteTag: 'sloped_rebar_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.infantry,
          unitDesignation: 'ROK Rifleman (K2C1)',
          equipmentSummary:
              'Granite B digital camo uniform, ballistic K-helmet, plate carrier, and Daewoo K2C1 5.56mm tactical rifle.',
          roleSilhouetteTag: 'k_helmet_rifle',
        ),
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.militia,
          unitDesignation: 'Homeland Reserve',
          equipmentSummary:
              'Granite field uniform with boonie patrol hat, magazine bandolier, and K1A submachine carbine.',
          roleSilhouetteTag: 'boonie_carbine',
        ),
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.engineer,
          unitDesignation: 'K600 Rhino CEV',
          equipmentSummary:
              'K1-chassis combat engineering vehicle equipped with full-width mine plow, magnetic signature duplicator, and excavator arm.',
          roleSilhouetteTag: 'wide_mine_plow_tank',
        ),
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.tank,
          unitDesignation: 'K2 Black Panther',
          equipmentSummary:
              'Low-profile composite-armored turret with 120mm L/55 autoloaded smoothbore gun and hydropneumatic suspension.',
          roleSilhouetteTag: 'low_profile_autoloader',
        ),
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.artillery,
          unitDesignation: 'K9A1 Thunder',
          equipmentSummary:
              'Tracked 155mm L/52 self-propelled howitzer with angular welded turret, auxiliary power unit, and heavy muzzle brake.',
          roleSilhouetteTag: 'angular_turret_spg',
        ),
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'K30 Biho Hybrid',
          equipmentSummary:
              'Tracked short-range air-defense turret combining twin 30mm autocannons, Chiron SAM pods, and TPS-830K radar.',
          roleSilhouetteTag: 'twin_30mm_sam_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.missile,
          unitDesignation: 'K239 Chunmoo MLRS',
          equipmentSummary:
              'Armored 8x8 wheeled chassis mounting dual modular pods capable of 130mm/239mm guided rockets and KTSSM missiles.',
          roleSilhouetteTag: 'eight_wheel_dual_pod',
        ),
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.airForce,
          unitDesignation: 'KF-21 Boramae',
          equipmentSummary:
              'Twin-engine low-observable multirole fighter with chined nose, canted twin tail fins, and semi-recessed pylons.',
          roleSilhouetteTag: 'canted_twin_tail_jet',
        ),
        FactionUnitProfile(
          faction: FactionId.southKorea,
          pieceType: PieceType.navy,
          unitDesignation: 'Sejong the Great DDG',
          equipmentSummary:
              'Heavy Aegis guided-missile destroyer with 128 VLS cells, twin funnels, and multi-tiered phased-array superstructure.',
          roleSilhouetteTag: 'heavy_aegis_destroyer',
        ),
      ],
    );
  }

  static FactionDefinition _buildIndia() {
    return _buildFaction(
      FactionId.india,
      const FactionColorPalette(
        primaryHex: 0xFF53633F,
        accentHex: 0xFFFF9800,
        uniformHex: 0xFF6B6548,
        neutralMetalHex: 0xFF384148,
        emblemHex: 0xFF1E88E5,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.commander,
          unitDesignation: 'Chief of Army Staff',
          equipmentSummary:
              'Indian Army olive-drab service tunic with saffron-trimmed officer cap/turban crest, medal ribbons, and baton.',
          roleSilhouetteTag: 'turban_peaked_command',
        ),
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.headquarters,
          unitDesignation: 'Forward Command Bastion',
          equipmentSummary:
              'Sandstone-colored reinforced forward bastion with embrasure slits and high-altitude satellite communications mast.',
          roleSilhouetteTag: 'sandstone_reinforced_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.infantry,
          unitDesignation: 'Gorkha Rifleman (INSAS)',
          equipmentSummary:
              'Brushstroke khaki-olive combat uniform, Patka steel-band helmet, chest rig, and INSAS / AK-203 assault rifle.',
          roleSilhouetteTag: 'patka_helmet_rifle',
        ),
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.militia,
          unitDesignation: 'Territorial Scout',
          equipmentSummary:
              'High-altitude olive patrol uniform with wide-brimmed slouch hat, kukri scabbard, and 9mm Sterling / carbine.',
          roleSilhouetteTag: 'slouch_hat_carbine',
        ),
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.engineer,
          unitDesignation: 'Sarvatra Bridge Truck',
          equipmentSummary:
              '8x8 Tatra heavy mobility chassis carrying a multi-span folding aluminum scissor bridge for mountain gorges.',
          roleSilhouetteTag: 'multi_span_bridge_truck',
        ),
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.tank,
          unitDesignation: 'Arjun Mk-1A',
          equipmentSummary:
              'Broad Kanchan composite-armored turret with 120mm rifled cannon, explosive reactive blocks, and panoramic commander sight.',
          roleSilhouetteTag: 'broad_box_composite_turret',
        ),
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.artillery,
          unitDesignation: 'K9 Vajra-T',
          equipmentSummary:
              'Desert-tan modified 155mm L/52 tracked self-propelled howitzer tuned for hot-weather and high-altitude fire missions.',
          roleSilhouetteTag: 'desert_spg_howitzer',
        ),
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'Akash SAM Battery',
          equipmentSummary:
              'Tracked BMP-derived launcher chassis mounting three ramjet-powered Akash surface-to-air missiles on an elevating rail.',
          roleSilhouetteTag: 'triple_rail_tracked_sam',
        ),
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.missile,
          unitDesignation: 'BrahMos Mobile TEL',
          equipmentSummary:
              'Heavy 12x12 autonomous mobile launcher raising three cylindrical supersonic BrahMos cruise missile canisters.',
          roleSilhouetteTag: 'triple_canister_heavy_tel',
        ),
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.airForce,
          unitDesignation: 'HAL Tejas Mk1A',
          equipmentSummary:
              'Compact tailless compound-delta lightweight fighter with single dorsal tail fin and bifurcated side air intakes.',
          roleSilhouetteTag: 'tailless_compound_delta',
        ),
        FactionUnitProfile(
          faction: FactionId.india,
          pieceType: PieceType.navy,
          unitDesignation: 'INS Visakhapatnam',
          equipmentSummary:
              'Project 15B stealth guided-missile destroyer with sloped hull, MF-STAR radar mast, and vertical BrahMos tubes.',
          roleSilhouetteTag: 'sloped_stealth_ddg',
        ),
      ],
    );
  }

  static FactionDefinition _buildIsrael() {
    return _buildFaction(
      FactionId.israel,
      const FactionColorPalette(
        primaryHex: 0xFF7B7763,
        accentHex: 0xFFD4AF37,
        uniformHex: 0xFF63644B,
        neutralMetalHex: 0xFF353B40,
        emblemHex: 0xFF29B6F6,
      ),
      const <FactionUnitProfile>[
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.commander,
          unitDesignation: 'Aluf Field Commander',
          equipmentSummary:
              'IDF olive-drab Aleph/Bet field uniform with draped mitznefet camouflage helmet cover, tactical headset, and map pouch.',
          roleSilhouetteTag: 'mitznefet_command',
        ),
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.headquarters,
          unitDesignation: 'Armored Command Hub',
          equipmentSummary:
              'Low-profile concrete dome bunker shielded by gabion walls and directional tactical communications antennas.',
          roleSilhouetteTag: 'low_profile_dome_bunker',
        ),
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.infantry,
          unitDesignation: 'Golani Rifleman (Tavor X95)',
          equipmentSummary:
              'IDF olive-drab combat uniform, Kasda helmet wrapped in iconic bulbous mitznefet mesh, and Tavor X95 bullpup rifle.',
          roleSilhouetteTag: 'mitznefet_bullpup',
        ),
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.militia,
          unitDesignation: 'Border Recon Scout',
          equipmentSummary:
              'Sinai-olive field shirt with wide boonie hat, light recon chest rig, and Galil ACE / M4 carbine.',
          roleSilhouetteTag: 'boonie_idf_carbine',
        ),
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.engineer,
          unitDesignation: 'Puma CEV',
          equipmentSummary:
              'Centurion-hulled heavy armored combat engineering vehicle with front mine-roller / dozer blade and rear demolition mortars.',
          roleSilhouetteTag: 'heavy_apc_dozer',
        ),
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.tank,
          unitDesignation: 'Merkava Mk.4M',
          equipmentSummary:
              'Sinai grey-tan main battle tank with rear-set wedge turret, Trophy APS radar panels, 120mm gun, and rear ball-and-chain curtain.',
          roleSilhouetteTag: 'rear_turret_sloped_hull',
        ),
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.artillery,
          unitDesignation: 'ATMOS 2000',
          equipmentSummary:
              'Armored 6x6 wheeled chassis mounting an open-deck 155mm L/52 long-range howitzer with automated breech.',
          roleSilhouetteTag: 'armored_truck_howitzer',
        ),
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.antiAircraft,
          unitDesignation: 'Iron Dome Tamir',
          equipmentSummary:
              'Angled 20-cell interceptor missile battery box mounted on stabilizing outriggers with Elta multi-mission radar unit.',
          roleSilhouetteTag: 'angled_20_cell_launcher',
        ),
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.missile,
          unitDesignation: 'PULS / Lynx MLRS',
          equipmentSummary:
              'Armored 6x6 tactical truck carrying dual modular precision-rocket pods for Accular, EXTRA, and Predator Hawk missiles.',
          roleSilhouetteTag: 'armored_dual_pod_truck',
        ),
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.airForce,
          unitDesignation: 'F-35I Adir',
          equipmentSummary:
              'Single-engine fifth-generation stealth strike fighter with chined fuselage, canted twin tail fins, and internal bays.',
          roleSilhouetteTag: 'chined_stealth_jet',
        ),
        FactionUnitProfile(
          faction: FactionId.israel,
          pieceType: PieceType.navy,
          unitDesignation: "Sa'ar 6 Corvette",
          equipmentSummary:
              'Compact stealth patrol corvette bristling with Naval Iron Dome, Barak-8 VLS cells, and ELM-2248 radar mast.',
          roleSilhouetteTag: 'compact_barak_corvette',
        ),
      ],
    );
  }
}
