import 'package:material_ui/material_ui.dart';

import '../../models/piece_model.dart';
import '../../state/game_hud_snapshot.dart';
import '../theme/commander_theme.dart';

/// Responsive Material 3 tactical HUD framing the 3D viewport.
///
/// When [viewport] is supplied, places [_TopHudBar] above and [_BottomHudPanel]
/// below an [Expanded] [viewport] inside a [Column] so HUD cards never occlude
/// any board intersection. Uses solid Material cards without `Opacity`,
/// `BackdropFilter`, or `saveLayer` passes.
final class GameHudOverlay extends StatelessWidget {
  const GameHudOverlay({
    super.key,
    required this.hud,
    required this.themeMode,
    required this.onUndo,
    required this.onNewMatch,
    required this.onToggleTheme,
    required this.onSelectCameraPreset,
    required this.onDismissError,
    this.viewport,
  });

  static const Key undoButtonKey = ValueKey<String>('hud_undo_button');
  static const Key newMatchButtonKey = ValueKey<String>('hud_new_match_button');
  static const Key themeToggleButtonKey = ValueKey<String>(
    'hud_theme_toggle_button',
  );
  static const Key dismissErrorButtonKey = ValueKey<String>(
    'hud_dismiss_error_button',
  );

  static Key cameraPresetKey(OrbitCameraPreset preset) =>
      ValueKey<String>('hud_camera_${preset.name}');

  final GameHudSnapshot hud;
  final ThemeMode themeMode;
  final VoidCallback onUndo;
  final VoidCallback onNewMatch;
  final VoidCallback onToggleTheme;
  final ValueChanged<OrbitCameraPreset> onSelectCameraPreset;
  final VoidCallback onDismissError;
  final Widget? viewport;

  @override
  Widget build(BuildContext context) {
    final selectedCoord = hud.selectedCoord;
    final selectedPiece = selectedCoord == null
        ? null
        : hud.session.pieceAt(selectedCoord);

    if (viewport != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          final isCompact = !isWide || constraints.maxHeight < 640;
          final horizPad = isWide ? 10.0 : 8.0;
          final edgePad = isCompact ? 4.0 : 8.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SafeArea(
                bottom: false,
                minimum: EdgeInsets.fromLTRB(horizPad, edgePad, horizPad, 2),
                child: _TopHudBar(
                  hud: hud,
                  themeMode: themeMode,
                  isWide: isWide,
                  isCompact: isCompact,
                  onUndo: onUndo,
                  onNewMatch: onNewMatch,
                  onToggleTheme: onToggleTheme,
                ),
              ),
              Expanded(child: viewport!),
              SafeArea(
                top: false,
                minimum: EdgeInsets.fromLTRB(horizPad, 2, horizPad, edgePad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (hud.errorMessage != null) ...<Widget>[
                      _ErrorBanner(
                        message: hud.errorMessage!,
                        onDismiss: onDismissError,
                      ),
                      const SizedBox(height: 4),
                    ],
                    _BottomHudPanel(
                      hud: hud,
                      selectedPiece: selectedPiece,
                      isWide: isWide,
                      isCompact: isCompact,
                      onSelectCameraPreset: onSelectCameraPreset,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }

    return SafeArea(
      minimum: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          final isCompact = !isWide || constraints.maxHeight < 640;
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _TopHudBar(
                hud: hud,
                themeMode: themeMode,
                isWide: isWide,
                isCompact: isCompact,
                onUndo: onUndo,
                onNewMatch: onNewMatch,
                onToggleTheme: onToggleTheme,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (hud.errorMessage != null) ...<Widget>[
                    _ErrorBanner(
                      message: hud.errorMessage!,
                      onDismiss: onDismissError,
                    ),
                    const SizedBox(height: 8),
                  ],
                  _BottomHudPanel(
                    hud: hud,
                    selectedPiece: selectedPiece,
                    isWide: isWide,
                    isCompact: isCompact,
                    onSelectCameraPreset: onSelectCameraPreset,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _TopHudBar extends StatelessWidget {
  const _TopHudBar({
    required this.hud,
    required this.themeMode,
    required this.isWide,
    required this.isCompact,
    required this.onUndo,
    required this.onNewMatch,
    required this.onToggleTheme,
  });

  final GameHudSnapshot hud;
  final ThemeMode themeMode;
  final bool isWide;
  final bool isCompact;
  final VoidCallback onUndo;
  final VoidCallback onNewMatch;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canUndo = hud.canUndo && !hud.isBusy;
    final canNewMatch = !hud.isBusy;
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && theme.brightness == Brightness.dark);

    if (isWide) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: isCompact ? 8 : 10,
          ),
          child: Row(
            children: <Widget>[
              _TurnBadge(
                side: hud.session.currentTurn,
                turnNumber: hud.session.turnNumber,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Commander Chess 3D • Cờ Tư Lệnh',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hud.statusMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (hud.isBusy) ...<Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
              ],
              OutlinedButton.icon(
                key: GameHudOverlay.undoButtonKey,
                onPressed: canUndo ? onUndo : null,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Undo'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: GameHudOverlay.newMatchButtonKey,
                onPressed: canNewMatch ? onNewMatch : null,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('New Match'),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: GameHudOverlay.themeToggleButtonKey,
                tooltip: isDark
                    ? 'Switch to light theme'
                    : 'Switch to dark theme',
                onPressed: onToggleTheme,
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: isCompact ? 6 : 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Commander Chess 3D • Cờ Tư Lệnh',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: GameHudOverlay.undoButtonKey,
                  tooltip: 'Undo',
                  visualDensity: VisualDensity.compact,
                  padding: isCompact ? const EdgeInsets.all(4) : null,
                  constraints: isCompact
                      ? const BoxConstraints(minWidth: 32, minHeight: 32)
                      : null,
                  onPressed: canUndo ? onUndo : null,
                  icon: const Icon(Icons.undo, size: 20),
                ),
                IconButton(
                  key: GameHudOverlay.newMatchButtonKey,
                  tooltip: 'New Match',
                  visualDensity: VisualDensity.compact,
                  padding: isCompact ? const EdgeInsets.all(4) : null,
                  constraints: isCompact
                      ? const BoxConstraints(minWidth: 32, minHeight: 32)
                      : null,
                  onPressed: canNewMatch ? onNewMatch : null,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                IconButton(
                  key: GameHudOverlay.themeToggleButtonKey,
                  tooltip: isDark
                      ? 'Switch to light theme'
                      : 'Switch to dark theme',
                  visualDensity: VisualDensity.compact,
                  padding: isCompact ? const EdgeInsets.all(4) : null,
                  constraints: isCompact
                      ? const BoxConstraints(minWidth: 32, minHeight: 32)
                      : null,
                  onPressed: onToggleTheme,
                  icon: Icon(
                    isDark ? Icons.light_mode : Icons.dark_mode,
                    size: 20,
                  ),
                ),
              ],
            ),
            SizedBox(height: isCompact ? 2 : 4),
            Row(
              children: <Widget>[
                _TurnBadge(
                  side: hud.session.currentTurn,
                  turnNumber: hud.session.turnNumber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hud.statusMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (hud.isBusy)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _TurnBadge extends StatelessWidget {
  const _TurnBadge({required this.side, required this.turnNumber});

  final PlayerSide side;
  final int turnNumber;

  @override
  Widget build(BuildContext context) {
    final isRed = side == PlayerSide.red;
    final factionColor = isRed
        ? CommanderTheme.redFaction
        : CommanderTheme.blueFaction;
    final label = isRed ? 'Red • Turn $turnNumber' : 'Blue • Turn $turnNumber';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: factionColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: factionColor.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: factionColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

final class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: GameHudOverlay.dismissErrorButtonKey,
              tooltip: 'Dismiss error',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: Icon(
                Icons.close,
                size: 18,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _BottomHudPanel extends StatelessWidget {
  const _BottomHudPanel({
    required this.hud,
    required this.selectedPiece,
    required this.isWide,
    required this.isCompact,
    required this.onSelectCameraPreset,
  });

  final GameHudSnapshot hud;
  final PieceEntity? selectedPiece;
  final bool isWide;
  final bool isCompact;
  final ValueChanged<OrbitCameraPreset> onSelectCameraPreset;

  @override
  Widget build(BuildContext context) {
    final pieceInfo = _SelectedPieceInfo(
      hud: hud,
      selectedPiece: selectedPiece,
    );
    final cameraControls = _CameraPresetSelector(
      activePreset: hud.cameraPreset,
      isCompact: isCompact,
      onSelect: onSelectCameraPreset,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 12 : 10,
          vertical: isCompact ? 6 : 10,
        ),
        child: isWide
            ? Row(
                children: <Widget>[
                  Expanded(child: pieceInfo),
                  const SizedBox(width: 12),
                  cameraControls,
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  pieceInfo,
                  SizedBox(height: isCompact ? 4 : 8),
                  cameraControls,
                ],
              ),
      ),
    );
  }
}

final class _SelectedPieceInfo extends StatelessWidget {
  const _SelectedPieceInfo({required this.hud, required this.selectedPiece});

  final GameHudSnapshot hud;
  final PieceEntity? selectedPiece;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final piece = selectedPiece;
    if (piece == null) {
      final sideLabel = hud.session.currentTurn == PlayerSide.red
          ? 'Red'
          : 'Blue';
      return Text(
        'Tap a $sideLabel unit to inspect legal moves • Drag to orbit, pinch or scroll to zoom',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final factionColor = piece.side == PlayerSide.red
        ? CommanderTheme.redFaction
        : CommanderTheme.blueFaction;
    final moveCount = hud.legalHints.length;
    final moveWord = moveCount == 1 ? 'move' : 'moves';
    final detailParts = <String>['$moveCount legal $moveWord'];

    if (piece.carriedPieces.isNotEmpty) {
      final passengers = piece.carriedPieces
          .map((p) => p.type.displayNameEn)
          .join(', ');
      detailParts.add('Carrying: $passengers');
    } else if (piece.type.carrierCapacity > 0) {
      detailParts.add('Carrier (0/${piece.type.carrierCapacity})');
    }

    if (piece.isHero) {
      detailParts.add('Heroic (+10)');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: factionColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${piece.type.displayNameVi} • ${piece.type.displayNameEn}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                piece.position.toAlgebraic(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (piece.isHero) ...<Widget>[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CommanderTheme.heroGold.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: CommanderTheme.heroGold),
                ),
                child: Text(
                  'HERO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          detailParts.join(' • '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

final class _CameraPresetSelector extends StatelessWidget {
  const _CameraPresetSelector({
    required this.activePreset,
    required this.isCompact,
    required this.onSelect,
  });

  final OrbitCameraPreset activePreset;
  final bool isCompact;
  final ValueChanged<OrbitCameraPreset> onSelect;

  static String _labelFor(OrbitCameraPreset preset) => switch (preset) {
    OrbitCameraPreset.redCommander => 'Red',
    OrbitCameraPreset.blueCommander => 'Blue',
    OrbitCameraPreset.tacticalTop => 'Top',
    OrbitCameraPreset.sideOverview => 'Side',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: isCompact ? 4 : 6,
      alignment: WrapAlignment.end,
      children: <Widget>[
        for (final preset in OrbitCameraPreset.values)
          ChoiceChip(
            key: GameHudOverlay.cameraPresetKey(preset),
            label: Text(_labelFor(preset)),
            selected: activePreset == preset,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: isCompact
                ? const EdgeInsets.symmetric(horizontal: 6)
                : null,
            labelPadding: isCompact
                ? const EdgeInsets.symmetric(horizontal: 2)
                : null,
            onSelected: (_) => onSelect(preset),
          ),
      ],
    );
  }
}
