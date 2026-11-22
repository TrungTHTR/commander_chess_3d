import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/game_providers.dart';

/// Manages the active [ThemeMode] for [CommanderChessApp], synchronized
/// bidirectionally with [gameSettingsProvider] (`isDarkMode`) without cycles.
final class CommanderThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final isDarkMode = ref.watch(
      gameSettingsProvider.select((settings) => settings.isDarkMode),
    );
    return isDarkMode ? ThemeMode.dark : ThemeMode.light;
  }

  void toggle() {
    final nextMode =
        state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setMode(nextMode);
  }

  void setMode(ThemeMode mode) {
    if (state == mode) return;
    state = mode;
    if (mode != ThemeMode.system) {
      unawaited(
        ref.read(gameSettingsProvider.notifier).setDarkMode(
              mode == ThemeMode.dark,
            ),
      );
    }
  }
}

/// Global presentation-layer theme mode provider for light/dark switching.
final commanderThemeModeProvider =
    NotifierProvider<CommanderThemeModeNotifier, ThemeMode>(
      CommanderThemeModeNotifier.new,
    );

/// Material 3 tactical board-game themes matching Red (`#C62828`) and
/// Blue (`#1565C0`) faction palettes.
abstract final class CommanderTheme {
  static const Color redFaction = Color(0xFFC62828);
  static const Color redAccent = Color(0xFFFFB300);
  static const Color blueFaction = Color(0xFF1565C0);
  static const Color blueAccent = Color(0xFF4FC3F7);
  static const Color heroGold = Color(0xFFFFD54F);
  static const Color darkSurface = Color(0xFF101923);
  static const Color darkCard = Color(0xFF16222E);
  static const Color lightSurface = Color(0xFFF3F5F8);
  static const Color lightCard = Color(0xFFFFFFFF);

  static ThemeData light() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: blueFaction,
      brightness: Brightness.light,
      primary: blueFaction,
      secondary: redFaction,
      tertiary: const Color(0xFF2E7D32),
      surface: lightSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: lightSurface,
      cardTheme: CardThemeData(
        color: lightCard.withValues(alpha: 0.94),
        elevation: 2,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: baseScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: blueFaction,
      brightness: Brightness.dark,
      primary: const Color(0xFF64B5F6),
      secondary: const Color(0xFFEF5350),
      tertiary: const Color(0xFF81C784),
      surface: darkSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: darkSurface,
      cardTheme: CardThemeData(
        color: darkCard.withValues(alpha: 0.92),
        elevation: 3,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: baseScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
