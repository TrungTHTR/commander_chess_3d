import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'features/game/presentation/screens/main_menu_screen.dart';
import 'features/game/presentation/theme/commander_theme.dart';

/// Root Material 3 application widget for Commander Chess 3D (Cờ Tư Lệnh).
final class CommanderChessApp extends ConsumerWidget {
  const CommanderChessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(commanderThemeModeProvider);

    return MaterialApp(
      title: 'Commander Chess 3D • Cờ Tư Lệnh',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: CommanderTheme.light(),
      darkTheme: CommanderTheme.dark(),
      home: const MainMenuScreen(),
    );
  }
}
