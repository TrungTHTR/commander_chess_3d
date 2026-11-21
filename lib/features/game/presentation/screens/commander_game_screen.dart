import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../engine/assets/piece_asset_provider.dart';
import '../../engine/shaders/board_shader_handle.dart';
import '../../state/game_hud_snapshot.dart';
import '../../state/game_providers.dart';
import '../theme/commander_theme.dart';
import '../widgets/board_3d_viewport.dart';
import '../widgets/game_hud_overlay.dart';

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
  });

  static const Key viewportKey = ValueKey<String>('board_3d_viewport');
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(gameSessionNotifierProvider.notifier);

    return Scaffold(
      body: _GameHudConnector(
        themeMode: themeMode,
        onToggleTheme: onToggleTheme,
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
    required this.viewport,
  });

  final ThemeMode? themeMode;
  final VoidCallback? onToggleTheme;
  final Widget viewport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hud = ref.watch(gameSessionNotifierProvider);
    final watchedThemeMode = ref.watch(commanderThemeModeProvider);
    final activeThemeMode = themeMode ?? watchedThemeMode;
    final notifier = ref.read(gameSessionNotifierProvider.notifier);

    return GameHudOverlay(
      hud: hud,
      themeMode: activeThemeMode,
      onUndo: () => unawaited(notifier.undoLastMove()),
      onNewMatch: () => unawaited(notifier.startNewMatch()),
      onToggleTheme:
          onToggleTheme ??
          () => ref.read(commanderThemeModeProvider.notifier).toggle(),
      onSelectCameraPreset: notifier.setCameraPreset,
      onDismissError: notifier.clearError,
      viewport: viewport,
    );
  }
}
