import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/faction_model.dart';
import '../../models/piece_model.dart';
import '../../state/game_hud_snapshot.dart';
import '../../state/game_providers.dart';
import '../theme/commander_theme.dart';

/// Settings screen allowing selection of opposing national factions (Red Side 1
/// and Blue Side 2 across all 11 nations), mirror match inspection, side swap,
/// unit hardware preview, theme mode, and default 3D camera preset.
final class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const Key backButtonKey = ValueKey<String>('settings_back_button');
  static const Key swapFactionsButtonKey = ValueKey<String>(
    'settings_swap_factions_button',
  );
  static const Key resetDefaultsButtonKey = ValueKey<String>(
    'settings_reset_defaults_button',
  );
  static const Key darkModeSwitchKey = ValueKey<String>(
    'settings_dark_mode_switch',
  );
  static const Key mirrorMatchBadgeKey = ValueKey<String>(
    'settings_mirror_match_badge',
  );
  static const Key doneButtonKey = ValueKey<String>('settings_done_button');

  static Key redFactionChipKey(FactionId faction) =>
      ValueKey<String>('settings_red_faction_${faction.code}');

  static Key blueFactionChipKey(FactionId faction) =>
      ValueKey<String>('settings_blue_faction_${faction.code}');

  static Key cameraPresetChipKey(String presetKey) =>
      ValueKey<String>('settings_camera_preset_$presetKey');

  static String _cameraPresetLabel(String presetKey) => switch (presetKey) {
    'classic' => 'Red Commander (Classic)',
    'high' => 'Tactical Top (High)',
    'side' => 'Side Overview',
    'top' => 'Blue Commander (Top)',
    _ => presetKey,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(gameSettingsProvider);
    final notifier = ref.read(gameSettingsProvider.notifier);
    final theme = CommanderTheme.settings(Theme.of(context));
    final colorScheme = theme.colorScheme;
    final redDef = FactionCatalog.of(settings.redFaction);
    final blueDef = FactionCatalog.of(settings.blueFaction);

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: backButtonKey,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Settings'),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 800;
              final horizPad = isWide ? 24.0 : 12.0;

              return ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizPad,
                  vertical: 12,
                ),
                children: <Widget>[
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1060),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  const _SectionHeader(
                                    title: 'Opposing Forces',
                                    subtitle: 'Choose a national roster for each side.',
                                  ),
                                  const SizedBox(height: 12),
                                  _FactionPickers(
                                    sideBySide: isWide,
                                    red: _FactionPickerSection(
                                      title: 'Red Force (Side 1 • Moves First)',
                                      sideColor: CommanderTheme.redFaction,
                                      selectedFaction: settings.redFaction,
                                      chipKeyBuilder: redFactionChipKey,
                                      onSelect: (faction) => unawaited(
                                        notifier.selectRedFaction(faction),
                                      ),
                                    ),
                                    blue: _FactionPickerSection(
                                      title: 'Blue Force (Side 2)',
                                      sideColor: CommanderTheme.blueFaction,
                                      selectedFaction: settings.blueFaction,
                                      chipKeyBuilder: blueFactionChipKey,
                                      onSelect: (faction) => unawaited(
                                        notifier.selectBlueFaction(faction),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      key: swapFactionsButtonKey,
                                      onPressed: () =>
                                          unawaited(notifier.swapFactions()),
                                      icon: const Icon(
                                        Icons.swap_horiz_rounded,
                                      ),
                                      label: const Text('Swap Sides'),
                                    ),
                                  ),
                                  if (settings.isMirrorMatch) ...<Widget>[
                                    const SizedBox(height: 12),
                                    Container(
                                      key: mirrorMatchBadgeKey,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: colorScheme.tertiaryContainer,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: colorScheme.tertiary,
                                        ),
                                      ),
                                      child: Row(
                                        children: <Widget>[
                                          Icon(
                                            Icons.compare_arrows_rounded,
                                            size: 18,
                                            color:
                                                colorScheme.onTertiaryContainer,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Mirror Match Active — Identical national forces are distinguished by Red vs Blue pedestal rings.',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onTertiaryContainer,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  const _SectionHeader(
                                    title: 'Appearance & 3D Camera',
                                  ),
                                  const SizedBox(height: 6),
                                  SwitchListTile(
                                    key: darkModeSwitchKey,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Dark Theme'),
                                    subtitle: Text(
                                      settings.isDarkMode
                                          ? 'Night tactical palette active'
                                          : 'Daylight tactical palette active',
                                    ),
                                    value: settings.isDarkMode,
                                    onChanged: (value) =>
                                        unawaited(notifier.setDarkMode(value)),
                                  ),
                                  const Divider(height: 16),
                                  Text(
                                    'Default Camera Preset',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: <Widget>[
                                      for (final presetKey
                                          in kSupportedCameraPresetKeys)
                                        ChoiceChip(
                                          key: cameraPresetChipKey(presetKey),
                                          label: Text(
                                            _cameraPresetLabel(presetKey),
                                          ),
                                          selected:
                                              settings.defaultCameraPreset ==
                                              presetKey,
                                          onSelected: (_) => unawaited(
                                            notifier.setDefaultCameraPreset(
                                              presetKey,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  const _SectionHeader(
                                    title: 'Unit Hardware Preview',
                                  ),
                                  const SizedBox(height: 12),
                                  if (isWide)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Expanded(
                                          child: _FactionHardwarePreview(
                                            sideLabel: 'Red Force',
                                            sideColor:
                                                CommanderTheme.redFaction,
                                            faction: redDef,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: _FactionHardwarePreview(
                                            sideLabel: 'Blue Force',
                                            sideColor:
                                                CommanderTheme.blueFaction,
                                            faction: blueDef,
                                          ),
                                        ),
                                      ],
                                    )
                                  else ...<Widget>[
                                    _FactionHardwarePreview(
                                      sideLabel: 'Red Force',
                                      sideColor: CommanderTheme.redFaction,
                                      faction: redDef,
                                    ),
                                    const Divider(height: 24),
                                    _FactionHardwarePreview(
                                      sideLabel: 'Blue Force',
                                      sideColor: CommanderTheme.blueFaction,
                                      faction: blueDef,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.spaceBetween,
                            children: <Widget>[
                              OutlinedButton.icon(
                                key: resetDefaultsButtonKey,
                                onPressed: () =>
                                    unawaited(notifier.resetDefaults()),
                                icon: const Icon(Icons.restart_alt_rounded),
                                label: const Text('Reset Defaults'),
                              ),
                              FilledButton.icon(
                                key: doneButtonKey,
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Done'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle case final String description) ...[
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

final class _FactionPickers extends StatelessWidget {
  const _FactionPickers({
    required this.sideBySide,
    required this.red,
    required this.blue,
  });

  final bool sideBySide;
  final Widget red;
  final Widget blue;

  @override
  Widget build(BuildContext context) {
    if (!sideBySide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [red, const SizedBox(height: 12), blue],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: red),
        const SizedBox(width: 12),
        Expanded(child: blue),
      ],
    );
  }
}

final class _FactionPickerSection extends StatelessWidget {
  const _FactionPickerSection({
    required this.title,
    required this.sideColor,
    required this.selectedFaction,
    required this.chipKeyBuilder,
    required this.onSelect,
  });

  final String title;
  final Color sideColor;
  final FactionId selectedFaction;
  final Key Function(FactionId) chipKeyBuilder;
  final ValueChanged<FactionId> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedDef = FactionCatalog.of(selectedFaction);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          sideColor.withValues(alpha: 0.09),
          theme.colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sideColor.withValues(alpha: 0.38)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: sideColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$title: ${selectedDef.id.displayName}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final def in FactionCatalog.all)
                  ChoiceChip(
                    key: chipKeyBuilder(def.id),
                    avatar: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color(def.palette.primaryHex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Color(def.palette.accentHex),
                          width: 1.5,
                        ),
                      ),
                    ),
                    label: Text('${def.id.displayName} (${def.id.shortCode})'),
                    selected: selectedFaction == def.id,
                    onSelected: (_) => onSelect(def.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _FactionHardwarePreview extends StatelessWidget {
  const _FactionHardwarePreview({
    required this.sideLabel,
    required this.sideColor,
    required this.faction,
  });

  final String sideLabel;
  final Color sideColor;
  final FactionDefinition faction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: sideColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$sideLabel • ${faction.id.displayName} (${faction.id.shortCode})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
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
        const SizedBox(height: 8),
        for (final pieceType in PieceType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _UnitHardwareTile(
              profile: faction.unitFor(pieceType),
              palette: faction.palette,
            ),
          ),
      ],
    );
  }
}

final class _UnitHardwareTile extends StatelessWidget {
  const _UnitHardwareTile({required this.profile, required this.palette});

  final FactionUnitProfile profile;
  final FactionColorPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Color(palette.primaryHex),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      profile.unitDesignation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      profile.pieceType.displayNameEn,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            profile.equipmentSummary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
