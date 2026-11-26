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
        MaterialPageRoute<void>(builder: (_) => const CommanderGameScreen()),
      ),
    );
  }

  void _openSettings() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
    );
  }

  void _openHelp() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const HelpScreen())),
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

    final menuTheme = CommanderTheme.menu(theme);
    final colors = menuTheme.colorScheme;

    return Theme(
      data: menuTheme,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1711),
        body: LayoutBuilder(
          builder: (context, viewport) {
            final wide = viewport.maxWidth >= 760;
            final inset = wide
                ? (viewport.maxWidth * 0.07).clamp(42.0, 128.0)
                : 20.0;
            final secondaryStyle = OutlinedButton.styleFrom(
              foregroundColor: colors.onSurface,
              backgroundColor: colors.surface.withValues(alpha: 0.74),
              side: BorderSide(color: colors.outlineVariant),
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: wide ? viewport.maxHeight : 330,
                  child: Image.asset(
                    'assets/images/commander_table.webp',
                    fit: BoxFit.cover,
                    alignment: wide
                        ? Alignment.centerRight
                        : const Alignment(0.55, 0),
                    excludeFromSemantics: true,
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xD907100C),
                        Color(0x5907100C),
                        Color(0x0007100C),
                      ],
                      stops: [0, 0.42, 0.84],
                    ),
                  ),
                ),
                if (!wide)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 330,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x6007100C),
                            Color(0xFF0D1711),
                          ],
                          stops: [0.12, 1],
                        ),
                      ),
                    ),
                  ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, safeViewport) => SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(inset, 16, inset, 36),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (safeViewport.maxHeight - 52).clamp(
                            0.0,
                            double.infinity,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: wide
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton.filledTonal(
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
                            ),
                            SizedBox(height: wide ? 10 : 66),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 455),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Cờ Tư Lệnh',
                                    style: menuTheme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: const Color(0xFFF0CC8D),
                                          letterSpacing: 2.8,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Commander\nChess 3D',
                                    semanticsLabel: 'Commander Chess 3D',
                                    style: TextStyle(
                                      fontFamily: 'Georgia',
                                      fontFamilyFallback: const ['serif'],
                                      color: const Color(0xFFF9F2E3),
                                      fontSize: wide ? 56 : 38,
                                      fontWeight: FontWeight.w700,
                                      height: 1.03,
                                      letterSpacing: wide ? -2.5 : -1,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Card(
                                    color: isDark
                                        ? const Color(0xEE16231B)
                                        : colors.surface,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: colors.outlineVariant,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                'Active Matchup',
                                                style: menuTheme
                                                    .textTheme
                                                    .titleSmall,
                                              ),
                                              if (settings.isMirrorMatch)
                                                Text(
                                                  'Mirror Match',
                                                  key: MainMenuScreen
                                                      .mirrorMatchBadgeKey,
                                                  style: TextStyle(
                                                    color: colors.primary,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          _MenuFactionRow(
                                            sideLabel: 'Red (Side 1)',
                                            sideColor: const Color(0xFFF08077),
                                            faction: redDef,
                                          ),
                                          const SizedBox(height: 8),
                                          _MenuFactionRow(
                                            sideLabel: 'Blue (Side 2)',
                                            sideColor: const Color(0xFF82B8E4),
                                            faction: blueDef,
                                          ),
                                          const Divider(height: 24),
                                          Text(
                                            'Camera: ${_cameraPresetLabel(settings.defaultCameraPreset)}',
                                            style: menuTheme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
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
                                      minimumSize: const Size(0, 56),
                                      textStyle: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('Start'),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        key: MainMenuScreen.settingsButtonKey,
                                        style: secondaryStyle,
                                        onPressed: _openSettings,
                                        icon: const Icon(Icons.tune_rounded),
                                        label: const Text('Settings'),
                                      ),
                                      OutlinedButton.icon(
                                        key: MainMenuScreen.helpButtonKey,
                                        style: secondaryStyle,
                                        onPressed: _openHelp,
                                        icon: const Icon(
                                          Icons.help_outline_rounded,
                                        ),
                                        label: const Text('Help'),
                                      ),
                                      TextButton(
                                        key: MainMenuScreen.exitButtonKey,
                                        onPressed: () =>
                                            unawaited(_confirmExit()),
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(0, 48),
                                          foregroundColor: const Color(
                                            0xFFF9F2E3,
                                          ),
                                        ),
                                        child: const Text('Exit'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
    return Row(
      children: [
        Icon(Icons.circle, color: sideColor, size: 9),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$sideLabel: ${faction.id.displayName} (${faction.id.shortCode})',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
