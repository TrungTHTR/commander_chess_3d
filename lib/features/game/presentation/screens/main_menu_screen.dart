import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/faction_model.dart';
import '../../state/game_providers.dart';
import '../theme/commander_theme.dart';
import 'commander_game_screen.dart';
import 'help_screen.dart';
import 'settings_screen.dart';

/// Main tactical landing screen for Commander Chess 3D (Cờ Tư Lệnh).
///
/// Displays the active Red vs Blue national matchup and camera preset from
/// [gameSettingsProvider] and provides `Start`, `Help`, `Settings`, and
/// platform-safe `Exit` actions.
final class MainMenuScreen extends ConsumerStatefulWidget {
  const MainMenuScreen({
    super.key,
    this.isWebPlatform = kIsWeb,
    this.onExitApp,
  });

  static const Key startButtonKey = ValueKey<String>('menu_start_button');
  static const Key helpButtonKey = ValueKey<String>('menu_help_button');
  static const Key settingsButtonKey = ValueKey<String>('menu_settings_button');
  static const Key exitButtonKey = ValueKey<String>('menu_exit_button');
  static const Key themeToggleButtonKey = ValueKey<String>(
    'menu_theme_toggle_button',
  );
  static const Key returnToMenuButtonKey = ValueKey<String>(
    'menu_return_to_menu_button',
  );
  static const Key confirmExitButtonKey = ValueKey<String>(
    'menu_confirm_exit_button',
  );
  static const Key cancelExitButtonKey = ValueKey<String>(
    'menu_cancel_exit_button',
  );
  static const Key mirrorMatchBadgeKey = ValueKey<String>(
    'menu_mirror_match_badge',
  );

  final bool isWebPlatform;
  final Future<void> Function()? onExitApp;

  @override
  ConsumerState<MainMenuScreen> createState() => _MainMenuScreenState();
}

final class _MainMenuScreenState extends ConsumerState<MainMenuScreen> {
  bool _sessionEnded = false;

  void _startMatch() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    unawaited(ref.read(gameSessionNotifierProvider.notifier).startNewMatch());
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const CommanderGameScreen(),
        ),
      ),
    );
  }

  void _openSettings() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SettingsScreen(),
        ),
      ),
    );
  }

  void _openHelp() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const HelpScreen(),
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Exit Commander Chess 3D?'),
          content: SingleChildScrollView(
            child: Text(
              widget.isWebPlatform
                  ? 'This will close your current browser session. You can return to the main menu at any time.'
                  : 'Are you sure you want to exit Commander Chess 3D?',
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: MainMenuScreen.cancelExitButtonKey,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: MainMenuScreen.confirmExitButtonKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Exit'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    if (widget.isWebPlatform) {
      setState(() {
        _sessionEnded = true;
      });
      return;
    }

    await (widget.onExitApp ?? SystemNavigator.pop)();
  }

  static String _cameraPresetLabel(String presetKey) => switch (presetKey) {
    'classic' => 'Red Commander (Classic)',
    'high' => 'Tactical Top (High)',
    'side' => 'Side Overview',
    'top' => 'Blue Commander (Top)',
    _ => 'Red Commander (Classic)',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeMode = ref.watch(commanderThemeModeProvider);
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && theme.brightness == Brightness.dark);

    if (_sessionEnded) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.power_settings_new_rounded,
                          size: 48,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Session Ended',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Commander Chess 3D has closed cleanly. Return to the main menu whenever you are ready to deploy.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: MainMenuScreen.returnToMenuButtonKey,
                            onPressed: () {
                              setState(() {
                                _sessionEnded = false;
                              });
                            },
                            icon: const Icon(Icons.home_rounded),
                            label: const Text('Return to Menu'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final settings = ref.watch(gameSettingsProvider);
    final redDef = FactionCatalog.of(settings.redFaction);
    final blueDef = FactionCatalog.of(settings.blueFaction);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 400;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 12 : 24,
                  vertical: isCompact ? 12 : 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '11×12 BOARD • 19 UNITS / SIDE',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: MainMenuScreen.themeToggleButtonKey,
                            tooltip: isDark
                                ? 'Switch to light theme'
                                : 'Switch to dark theme',
                            onPressed: () => ref
                                .read(commanderThemeModeProvider.notifier)
                                .toggle(),
                            icon: Icon(
                              isDark ? Icons.light_mode : Icons.dark_mode,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Commander Chess 3D',
                        style: (isCompact
                                ? theme.textTheme.headlineSmall
                                : theme.textTheme.headlineMedium)
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cờ Tư Lệnh • 11 National Military Factions',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(isCompact ? 12 : 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      'Active Matchup',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  if (settings.isMirrorMatch)
                                    Container(
                                      key: MainMenuScreen.mirrorMatchBadgeKey,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.tertiaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Mirror Match',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme
                                                  .onTertiaryContainer,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _MenuFactionRow(
                                sideLabel: 'Red (Side 1)',
                                sideColor: CommanderTheme.redFaction,
                                faction: redDef,
                              ),
                              const SizedBox(height: 8),
                              _MenuFactionRow(
                                sideLabel: 'Blue (Side 2)',
                                sideColor: CommanderTheme.blueFaction,
                                faction: blueDef,
                              ),
                              const Divider(height: 20),
                              Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.videocam_outlined,
                                    size: 16,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Camera: ${_cameraPresetLabel(settings.defaultCameraPreset)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: MainMenuScreen.startButtonKey,
                        onPressed: _startMatch,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start'),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        key: MainMenuScreen.settingsButtonKey,
                        onPressed: _openSettings,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('Settings'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: MainMenuScreen.helpButtonKey,
                        onPressed: _openHelp,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.help_outline_rounded),
                        label: const Text('Help'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: MainMenuScreen.exitButtonKey,
                        onPressed: () => unawaited(_confirmExit()),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.exit_to_app_rounded),
                        label: const Text('Exit'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

final class _MenuFactionRow extends StatelessWidget {
  const _MenuFactionRow({
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

    return Row(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$sideLabel: ${faction.id.displayName} (${faction.id.shortCode})',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                faction.id.doctrineSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _PaletteSwatchDot(color: Color(faction.palette.primaryHex)),
            const SizedBox(width: 3),
            _PaletteSwatchDot(color: Color(faction.palette.accentHex)),
            const SizedBox(width: 3),
            _PaletteSwatchDot(color: Color(faction.palette.emblemHex)),
          ],
        ),
      ],
    );
  }
}

final class _PaletteSwatchDot extends StatelessWidget {
  const _PaletteSwatchDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.8,
        ),
      ),
    );
  }
}
