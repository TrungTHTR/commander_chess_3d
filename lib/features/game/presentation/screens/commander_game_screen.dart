import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../engine/assets/piece_asset_provider.dart';
import '../../engine/shaders/board_shader_handle.dart';
import '../../models/game_state_model.dart';
import '../../state/game_hud_snapshot.dart';
import '../../state/game_providers.dart';
import '../theme/commander_theme.dart';
import '../widgets/board_3d_viewport.dart';
import '../widgets/game_hud_overlay.dart';
import 'main_menu_screen.dart';

/// Primary Commander Chess 3D gameplay screen composing the
/// [RepaintBoundary]-isolated 3D viewport and reactive Material 3 HUD bars
/// in a non-overlapping vertical layout so HUD cards never occlude the board.
final class CommanderGameScreen extends ConsumerWidget {
  const CommanderGameScreen({
    super.key,
    this.assetProviderFactory,
    this.rendererFactory,
    this.shaderHandleFactory,
    this.themeMode,
    this.onToggleTheme,
    this.onBackToMenu,
  });

  static const Key viewportKey = ValueKey<String>('board_3d_viewport');
  static const Key backToMenuButtonKey = GameHudOverlay.backToMenuButtonKey;
  static const Key confirmBackToMenuButtonKey = ValueKey<String>(
    'hud_confirm_back_to_menu_button',
  );
  static const Key cancelBackToMenuButtonKey = ValueKey<String>(
    'hud_cancel_back_to_menu_button',
  );
  static const Key undoButtonKey = GameHudOverlay.undoButtonKey;
  static const Key newMatchButtonKey = GameHudOverlay.newMatchButtonKey;
  static const Key themeToggleButtonKey = GameHudOverlay.themeToggleButtonKey;
  static const Key dismissErrorButtonKey = GameHudOverlay.dismissErrorButtonKey;

  static Key cameraPresetKey(OrbitCameraPreset preset) =>
      GameHudOverlay.cameraPresetKey(preset);

  final PieceAssetProvider Function()? assetProviderFactory;
  final BoardSceneRendererFactory? rendererFactory;
  final BoardShaderHandle Function()? shaderHandleFactory;
  final ThemeMode? themeMode;
  final VoidCallback? onToggleTheme;
  final VoidCallback? onBackToMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(gameSessionNotifierProvider.notifier);

    return Scaffold(
      body: _GameHudConnector(
        themeMode: themeMode,
        onToggleTheme: onToggleTheme,
        onBackToMenu: onBackToMenu,
        viewport: Board3DViewport(
          key: viewportKey,
          onCoordTapped: notifier.selectCoord,
          assetProviderFactory: assetProviderFactory,
          rendererFactory: rendererFactory,
          shaderHandleFactory: shaderHandleFactory,
        ),
      ),
    );
  }
}

final class _GameHudConnector extends ConsumerWidget {
  const _GameHudConnector({
    required this.themeMode,
    required this.onToggleTheme,
    required this.onBackToMenu,
    required this.viewport,
  });

  final ThemeMode? themeMode;
  final VoidCallback? onToggleTheme;
  final VoidCallback? onBackToMenu;
  final Widget viewport;

  bool _hasActiveMatch(GameHudSnapshot hud) =>
      hud.session.moveHistory.isNotEmpty &&
      hud.session.phase != MatchPhase.finished;

  Future<void> _handleBackToMenu(
    BuildContext context,
    GameHudSnapshot hud,
  ) async {
    if (onBackToMenu != null) {
      onBackToMenu!();
      return;
    }

    if (_hasActiveMatch(hud)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Leave Active Match?'),
            content: const SingleChildScrollView(
              child: Text(
                'You have moves in progress. Return to the main menu?',
              ),
            ),
            actions: <Widget>[
              TextButton(
                key: CommanderGameScreen.cancelBackToMenuButtonKey,
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: CommanderGameScreen.confirmBackToMenuButtonKey,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Back to Menu'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !context.mounted) return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      unawaited(
        navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const MainMenuScreen(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hud = ref.watch(gameSessionNotifierProvider);
    final watchedThemeMode = ref.watch(commanderThemeModeProvider);
    final activeThemeMode = themeMode ?? watchedThemeMode;
    final notifier = ref.read(gameSessionNotifierProvider.notifier);
    final hasActiveMatch = _hasActiveMatch(hud);

    return PopScope(
      canPop: !hasActiveMatch && onBackToMenu == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleBackToMenu(context, hud));
      },
      child: GameHudOverlay(
        hud: hud,
        themeMode: activeThemeMode,
        onUndo: () => unawaited(notifier.undoLastMove()),
        onNewMatch: () => unawaited(notifier.startNewMatch()),
        onToggleTheme:
            onToggleTheme ??
            () => ref.read(commanderThemeModeProvider.notifier).toggle(),
        onSelectCameraPreset: notifier.setCameraPreset,
        onDismissError: notifier.clearError,
        onBackToMenu: () => unawaited(_handleBackToMenu(context, hud)),
        viewport: viewport,
      ),
    );
  }
}
