import 'package:material_ui/material_ui.dart';

import '../../models/faction_model.dart';
import '../../models/piece_model.dart';

/// Tabbed documentation screen covering the 11×12 board & terrain, all 11 unit
/// types (19 pieces/side), Commander/LoS/check rules, 3D controls, and the
/// 11-faction hardware catalog from [FactionCatalog.all].
final class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const Key backButtonKey = ValueKey<String>('help_back_button');
  static const Key tabBarKey = ValueKey<String>('help_tab_bar');
  static const Key boardTabKey = ValueKey<String>('help_tab_board');
  static const Key unitsTabKey = ValueKey<String>('help_tab_units');
  static const Key rulesTabKey = ValueKey<String>('help_tab_rules');
  static const Key controlsTabKey = ValueKey<String>('help_tab_controls');
  static const Key factionsTabKey = ValueKey<String>('help_tab_factions');

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: backButtonKey,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('How to Play • Help'),
          bottom: const TabBar(
            key: tabBarKey,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(key: boardTabKey, text: 'Board & Terrain'),
              Tab(key: unitsTabKey, text: 'Units (19/Side)'),
              Tab(key: rulesTabKey, text: 'Rules & Victory'),
              Tab(key: controlsTabKey, text: '3D Controls'),
              Tab(key: factionsTabKey, text: '11 Factions'),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: <Widget>[
              _BoardTerrainTab(),
              _UnitRosterTab(),
              _RulesVictoryTab(),
              _ControlsTab(),
              _FactionsCatalogTab(),
            ],
          ),
        ),
      ),
    );
  }
}

final class _BoardTerrainTab extends StatelessWidget {
  const _BoardTerrainTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: const <Widget>[
        _HelpCard(
          title: '11×12 Tactical Grid (132 Intersections)',
          icon: Icons.grid_on_rounded,
          body:
              'Commander Chess (Cờ Tư Lệnh) is played on 11 files (a–k) by 12 ranks (1–12), yielding 132 playable intersections. Pieces stand on intersections rather than inside squares.\n\n'
              '• Red (Side 1) deploys on ranks 1–5 and moves first.\n'
              '• Blue (Side 2) deploys on ranks 8–12.',
        ),
        SizedBox(height: 10),
        _HelpCard(
          title: 'Terrain Zones',
          icon: Icons.terrain_rounded,
          body:
              '• Deep Sea (files a–b, ranks 1–12): Passable for Navy vessels and airborne Air Force. Air Force can fly over Deep Sea and perform stay-capture strikes against naval targets, but cannot land on empty Deep Sea.\n'
              '• Coast & Estuary (Mixed — file c, ranks 1–12 plus estuary d6, e6, d7, e7): Shared amphibious zone passable by both land and naval units. Navy units may not cut diagonal land corners (such as c5↔d6 or c8↔d7).\n'
              '• Land (files d–k, excluding estuary d6, e6, d7, e7): Passable for all ground and air units; impassable to Navy.',
        ),
        SizedBox(height: 10),
        _HelpCard(
          title: 'River (Sông) & Shallow Fords (Ngầm)',
          icon: Icons.waves_rounded,
          body:
              'An inland river runs between ranks 6 and 7 across files c–k (files a–b are open Deep Sea).\n\n'
              '• Shallow Fords: Two ford crossings connect f6↔f7 and h6↔h7.\n'
              '• Heavy Unit Restriction: Heavy units (Artillery, Anti-Aircraft, Missile) cannot cross the deep river unassisted and must cross via fords f6–f7 or h6–h7, though they may fire across the bank within range.',
        ),
      ],
    );
  }
}

final class _UnitRosterTab extends StatelessWidget {
  const _UnitRosterTab();

  static const List<_UnitDocEntry> _unitDocs = <_UnitDocEntry>[
    _UnitDocEntry(
      type: PieceType.commander,
      countPerSide: 1,
      rangeSummary: 'Unlimited orthogonal slide; 1-step orthogonal capture',
      notes:
          'Must stay on land/mixed terrain, never move into check, and never face the enemy Commander unobstructed on a file or rank.',
    ),
    _UnitDocEntry(
      type: PieceType.headquarters,
      countPerSide: 2,
      rangeSummary: 'Stationary (0 steps)',
      notes:
          'Immobile command post; cannot move or capture. Carrier capacity: 1.',
    ),
    _UnitDocEntry(
      type: PieceType.infantry,
      countPerSide: 2,
      rangeSummary: '1-step orthogonal move/capture',
      notes:
          'Crosses river freely on land/mixed; performs stay-capture against adjacent Deep Sea targets.',
    ),
    _UnitDocEntry(
      type: PieceType.militia,
      countPerSide: 1,
      rangeSummary: '1-step 8-way (orthogonal + diagonal)',
      notes:
          'Versatile 8-direction light scout; crosses river freely and stay-captures adjacent Deep Sea enemies.',
    ),
    _UnitDocEntry(
      type: PieceType.engineer,
      countPerSide: 2,
      rangeSummary: '1-step orthogonal move/capture',
      notes:
          'Crosses river freely; carries carrier capacity 1 metadata for full-rules ferrying.',
    ),
    _UnitDocEntry(
      type: PieceType.tank,
      countPerSide: 2,
      rangeSummary: '1–2 step orthogonal move/capture (blocked)',
      notes:
          'Crosses river freely on land/mixed; stay-captures adjacent Deep Sea enemies. Carrier capacity: 2.',
    ),
    _UnitDocEntry(
      type: PieceType.artillery,
      countPerSide: 2,
      rangeSummary: '1–3 step 8-way move; 1–3 step 8-way fire/capture',
      notes:
          'Heavy unit (crosses river via fords f/h only). Can jump intervening pieces when firing/capturing; supports stay-capture on Deep Sea.',
    ),
    _UnitDocEntry(
      type: PieceType.antiAircraft,
      countPerSide: 2,
      rangeSummary: '1-step orthogonal move/capture',
      notes:
          'Heavy unit (crosses river via fords f/h only). Air defense radius: 1.',
    ),
    _UnitDocEntry(
      type: PieceType.missile,
      countPerSide: 1,
      rangeSummary: '1–2 step orthogonal or 1-step diagonal',
      notes:
          'Heavy unit (crosses river via fords f/h only). Air defense radius: 2.',
    ),
    _UnitDocEntry(
      type: PieceType.airForce,
      countPerSide: 2,
      rangeSummary: '1–4 step 8-way flight over obstacles & sea',
      notes:
          'Cannot stop on empty Deep Sea. Supports both displacement capture (land/mixed) and stay-capture bomb-and-return strikes. Carrier capacity: 2.',
    ),
    _UnitDocEntry(
      type: PieceType.navy,
      countPerSide: 2,
      rangeSummary: '1–4 step 8-way sail; 1–3 bombardment onto land',
      notes:
          'Sails Deep Sea & Mixed zones (ignores friendly units; no diagonal land-corner cuts). Bombards coastal/land targets at range 1–3. Carrier capacity: 2, AD radius: 1.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        const _HelpCard(
          title: '11 Unit Types • 19 Pieces per Side (38 Total)',
          icon: Icons.military_tech_rounded,
          body:
              'Standard 19-piece force composition per side: 1C, 2H, 2I, 1M, 2E, 2T, 2A, 2G, 1S, 2F, 2N. All 11 national factions use this balanced ruleset with unique national 3D models and hardware profiles.\n\n'
              'Starter vs Full Rules Note: Carrier capacity, air-defense radii, and Heroic (+10 pts) metadata are modeled on units; active embark/disembark stacking and AD interception are reserved for full-rules mode.',
        ),
        const SizedBox(height: 10),
        for (final doc in _unitDocs) ...<Widget>[
          _UnitDocCard(doc: doc),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

final class _RulesVictoryTab extends StatelessWidget {
  const _RulesVictoryTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: const <Widget>[
        _HelpCard(
          title: 'Victory Condition — Commander Capture',
          icon: Icons.emoji_events_rounded,
          body:
              'Capturing the opposing Commander (Tư lệnh) immediately wins the match. Always guard your Commander and deny enemy firing lines.',
        ),
        SizedBox(height: 10),
        _HelpCard(
          title: 'Exposed Commander LoS (Flying General)',
          icon: Icons.visibility_rounded,
          body:
              'Red and Blue Commanders may never face each other along the same file or rank with zero intervening pieces. Any move or stay-capture that leaves both Commanders exposed to each other is illegal.',
        ),
        SizedBox(height: 10),
        _HelpCard(
          title: 'Check, Pinning & Headquarters Immobility',
          icon: Icons.shield_rounded,
          body:
              '• Check & Pinning: You may not make any move that leaves your own Commander in check. When a Commander is threatened, the HUD announces Check.\n'
              '• Headquarters (Sở chỉ huy): Headquarters pieces are stationary and cannot move or capture.\n'
              '• Stay-Capture: Air Force strikes, Navy coastal bombardments, and land attacks against adjacent Deep Sea targets destroy the enemy while keeping the attacker on its origin tile.',
        ),
      ],
    );
  }
}

final class _ControlsTab extends StatelessWidget {
  const _ControlsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: const <Widget>[
        _HelpCard(
          title: '3D Tabletop Interaction',
          icon: Icons.touch_app_rounded,
          body:
              '• Select & Move: Tap a friendly unit to inspect its designation and highlight legal destinations. Tap a highlighted intersection to move or stay-capture. Tap the same piece or an empty non-highlighted tile to deselect.\n'
              '• Orbit Camera: Drag with one finger or mouse button to rotate yaw and pitch around the board.\n'
              '• Zoom: Pinch with two fingers or scroll the mouse wheel to zoom in and out.',
        ),
        SizedBox(height: 10),
        _HelpCard(
          title: 'Camera Presets',
          icon: Icons.videocam_rounded,
          body:
              'Switch anytime in the bottom HUD or configure your starting view in Settings:\n'
              '• Red (Classic): Default tactical perspective behind Red lines.\n'
              '• Blue (Top): Flipped perspective behind Blue lines.\n'
              '• Top (High): High-angle overhead tactical overview.\n'
              '• Side: Angled flank perspective across the river and coast.',
        ),
      ],
    );
  }
}

final class _FactionsCatalogTab extends StatelessWidget {
  const _FactionsCatalogTab();

  @override
  Widget build(BuildContext context) {
    final factions = FactionCatalog.all;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: factions.length,
      itemBuilder: (context, index) {
        final faction = factions[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Color(faction.palette.primaryHex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Color(faction.palette.accentHex),
                            width: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${faction.id.displayName} (${faction.id.shortCode})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    faction.id.doctrineSummary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Divider(height: 16),
                  for (final pieceType in PieceType.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 24,
                            child: Text(
                              pieceType.fenChar,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  '${faction.unitFor(pieceType).unitDesignation} (${pieceType.displayNameEn})',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  faction.unitFor(pieceType).equipmentSummary,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _HelpCard extends StatelessWidget {
  const _HelpCard({
    required this.title,
    required this.icon,
    required this.body,
  });

  final String title;
  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _UnitDocEntry {
  const _UnitDocEntry({
    required this.type,
    required this.countPerSide,
    required this.rangeSummary,
    required this.notes,
  });

  final PieceType type;
  final int countPerSide;
  final String rangeSummary;
  final String notes;
}

final class _UnitDocCard extends StatelessWidget {
  const _UnitDocCard({required this.doc});

  final _UnitDocEntry doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tags = <String>[
      '${doc.countPerSide}× / side',
      '${doc.type.basePoints} pts',
      if (doc.type.isHeavy) 'Heavy',
      if (doc.type.carrierCapacity > 0) 'Carrier ${doc.type.carrierCapacity}',
      if (doc.type.airDefenseRadius > 0) 'AD ${doc.type.airDefenseRadius}',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    doc.type.fenChar,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${doc.type.displayNameVi} • ${doc.type.displayNameEn}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                for (final tag in tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tag,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              doc.rangeSummary,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              doc.notes,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
