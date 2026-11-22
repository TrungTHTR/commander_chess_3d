import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:commander_chess_3d/app.dart';
import 'package:commander_chess_3d/features/game/models/piece_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Authoritative 11 national factions from PROJECT.md & ORIGINAL_REQUEST.md.
const List<String> kAllFactionNames = <String>[
  'United States',
  'Vietnam',
  'Soviet Union',
  'United Kingdom',
  'Germany',
  'France',
  'China',
  'Japan',
  'South Korea',
  'India',
  'Israel',
];

/// Canonical normalized faction ID tokens accepted in `asset_manifest.json`.
const Map<String, List<String>> kFactionManifestAliases = <String, List<String>>{
  'United States': <String>['usa', 'unitedstates', 'united_states'],
  'Vietnam': <String>['vietnam', 'vn'],
  'Soviet Union': <String>['sovietunion', 'soviet_union', 'ussr'],
  'United Kingdom': <String>['unitedkingdom', 'united_kingdom', 'uk'],
  'Germany': <String>['germany', 'de'],
  'France': <String>['france', 'fr'],
  'China': <String>['china', 'cn'],
  'Japan': <String>['japan', 'jp'],
  'South Korea': <String>['southkorea', 'south_korea', 'kr'],
  'India': <String>['india', 'in'],
  'Israel': <String>['israel', 'il'],
};

/// Opaque-box mirror of the 4 documented 3D camera presets.
enum E2ECameraPreset {
  redCommander,
  blueCommander,
  tacticalTop,
  sideOverview,
}

/// Pumps the real application entry point ([CommanderChessApp]) wrapped only in
/// [ProviderScope] at [size] and optional [textScaleFactor].
Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  double textScaleFactor = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  if (textScaleFactor != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  await tester.pumpWidget(const ProviderScope(child: CommanderChessApp()));
  await pumpFrames(tester, count: 8);
}

/// Advances a bounded number of frames without hanging on active 3D Tickers.
Future<void> pumpFrames(
  WidgetTester tester, {
  int count = 12,
  Duration step = const Duration(milliseconds: 35),
}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(step);
  }
}

/// Pumps enough frames for Material route push/pop transitions (450ms+) to
/// complete and unmount offstage routes before querying the active screen.
Future<void> _pumpRouteTransition(WidgetTester tester) async {
  await pumpFrames(tester, count: 20, step: const Duration(milliseconds: 35));
}

/// Ensures [finder] is visible inside its scrollable ancestor and pumps one
/// frame so RenderBox layout coordinates update before tapping.
Future<void> _ensureVisibleAndPump(
  WidgetTester tester,
  Finder finder,
) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Returns the topmost mounted vertical [Scrollable] (typically the active
/// route or modal sheet), avoiding background route scrollables.
Finder? _findTopmostVerticalScrollable(WidgetTester tester) {
  final vertical = <Element>[];
  for (final el in find.byType(Scrollable).evaluate()) {
    if (el is StatefulElement && el.state is ScrollableState) {
      final state = el.state as ScrollableState;
      if (state.mounted && state.position.axis == Axis.vertical) {
        vertical.add(el);
      }
    }
  }
  if (vertical.isEmpty) return null;
  final target = vertical.last;
  return find.byElementPredicate((e) => e == target);
}

const List<String> _kCameraExcludeTerms = <String>[
  'commander',
  'tactical',
  'overview',
  'classic',
  'high',
  'top',
  'camera',
  'preset',
];

/// Disposes the widget tree and asserts zero unhandled exceptions or overflows.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

/// Returns the current [Brightness] from the active Material theme.
Brightness readActiveBrightness(WidgetTester tester) {
  final scaffolds = find.byType(Scaffold);
  if (scaffolds.evaluate().isNotEmpty) {
    return Theme.of(tester.element(scaffolds.first)).brightness;
  }
  final materialApps = find.byType(MaterialApp);
  expect(materialApps, findsAtLeastNWidgets(1));
  return Theme.of(tester.element(materialApps.first)).brightness;
}

/// Finds a visible/tappable menu button or list tile matching [label].
Finder findMenuButton(WidgetTester tester, String label) {
  final exact = find.text(label);
  if (exact.evaluate().isNotEmpty) {
    return _preferTappableAncestor(exact);
  }

  final lower = label.toLowerCase();
  final fuzzy = find.byWidgetPredicate((widget) {
    if (widget is Text) {
      final value = (widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .trim()
          .toLowerCase();
      return value == lower || value.startsWith('$lower ');
    }
    return false;
  });
  return _preferTappableAncestor(fuzzy);
}

Finder _preferTappableAncestor(Finder textFinder) {
  if (textFinder.evaluate().isEmpty) return textFinder;
  final interactive = _findInteractiveAncestor(textFinder);
  if (interactive.evaluate().isNotEmpty) {
    return interactive;
  }
  return textFinder;
}

bool _isInteractiveControlWidget(Widget widget) {
  return widget is ButtonStyleButton ||
      widget is IconButton ||
      widget is ChoiceChip ||
      widget is FilterChip ||
      widget is ActionChip ||
      widget is RawChip ||
      (widget is ListTile && (widget.onTap != null || widget.onLongPress != null)) ||
      widget is RadioListTile ||
      widget is SwitchListTile ||
      widget is CheckboxListTile ||
      widget is InkWell ||
      widget is Tab ||
      widget is MenuItemButton ||
      widget is DropdownMenuItem;
}

Finder _findInteractiveAncestor(Finder targetFinder) {
  if (targetFinder.evaluate().isEmpty) return targetFinder;
  for (final type in const <Type>[
    ChoiceChip,
    FilterChip,
    ActionChip,
    RawChip,
  ]) {
    final ancestor = find.ancestor(of: targetFinder, matching: find.byType(type));
    if (ancestor.evaluate().isNotEmpty) {
      return ancestor;
    }
  }
  final tappableListTile = find.ancestor(
    of: targetFinder,
    matching: find.byWidgetPredicate(
      (w) => w is ListTile && (w.onTap != null || w.onLongPress != null),
    ),
  );
  if (tappableListTile.evaluate().isNotEmpty) {
    return tappableListTile;
  }
  for (final type in const <Type>[
    InkWell,
    Tab,
    MenuItemButton,
  ]) {
    final ancestor = find.ancestor(of: targetFinder, matching: find.byType(type));
    if (ancestor.evaluate().isNotEmpty) {
      return ancestor;
    }
  }
  final buttonStyle = find.ancestor(
    of: targetFinder,
    matching: find.bySubtype<ButtonStyleButton>(),
  );
  if (buttonStyle.evaluate().isNotEmpty) {
    return buttonStyle;
  }
  final iconBtn = find.ancestor(
    of: targetFinder,
    matching: find.byType(IconButton),
  );
  if (iconBtn.evaluate().isNotEmpty) {
    return iconBtn;
  }
  final dropdownItem = find.ancestor(
    of: targetFinder,
    matching: find.bySubtype<DropdownMenuItem<dynamic>>(),
  );
  if (dropdownItem.evaluate().isNotEmpty) {
    return dropdownItem;
  }
  final gestureAncestor = find.ancestor(
    of: targetFinder,
    matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null),
  );
  if (gestureAncestor.evaluate().isNotEmpty) {
    // Exclude outer GestureDetectors wrapping Scrollables/Viewports.
    final validGestures = <Element>[];
    for (final el in gestureAncestor.evaluate()) {
      final elFinder = find.byElementPredicate((e) => e == el);
      final hasScrollable = find
          .descendant(of: elFinder, matching: find.byType(Scrollable))
          .evaluate()
          .isNotEmpty;
      if (!hasScrollable) {
        validGestures.add(el);
      }
    }
    if (validGestures.isNotEmpty) {
      return find.byElementPredicate((e) => validGestures.contains(e));
    }
  }
  return find.byWidgetPredicate((_) => false);
}

Finder _findInteractiveTextButtonContaining(String snippet) {
  final lower = snippet.toLowerCase();
  final textFinder = find.byWidgetPredicate((widget) {
    if (widget is Text) {
      final value = (widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .toLowerCase();
      return value.contains(lower);
    }
    return false;
  });
  return _findInteractiveAncestor(textFinder);
}

/// Asserts that all 4 Main Menu options (`Start`, `Help`, `Settings`, `Exit`)
/// are rendered on screen.
void expectOnMainMenu(WidgetTester tester) {
  for (final option in const <String>['Start', 'Help', 'Settings', 'Exit']) {
    expect(
      findMenuButton(tester, option),
      findsAtLeastNWidgets(1),
      reason: 'Expected Main Menu option "$option" to be present.',
    );
  }
}

/// Taps a Main Menu option (`Start`, `Help`, `Settings`, `Exit`).
Future<void> tapMenuOption(WidgetTester tester, String label) async {
  final finder = findMenuButton(tester, label);
  expect(
    finder,
    findsAtLeastNWidgets(1),
    reason: 'Menu option "$label" must be present before tapping.',
  );
  await _ensureVisibleAndPump(tester, finder.first);
  await tester.tap(finder.first);
  await _pumpRouteTransition(tester);
}

/// Collects all visible text across the current widget tree (both [Text] and
/// [RichText]) into [buffer].
void _collectVisibleTextInto(WidgetTester tester, Set<String> buffer) {
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final value = (widget.data ?? widget.textSpan?.toPlainText() ?? '').trim();
    if (value.isNotEmpty) {
      buffer.add(value);
    }
  }
  for (final element in find.byType(RichText).evaluate()) {
    final widget = element.widget as RichText;
    final value = widget.text.toPlainText().trim();
    if (value.isNotEmpty) {
      buffer.add(value);
    }
  }
}

/// Scrolls all scrollables and visits every tab / expansion tile on the Help
/// screen, returning the full normalized text content.
Future<String> collectHelpScreenText(WidgetTester tester) async {
  final collected = <String>{};

  Future<void> sweepCurrentTab() async {
    _collectVisibleTextInto(tester, collected);

    // Expand any collapsed ExpansionTiles without relying on stale indices.
    final tappedExpansions = <Element>{};
    while (true) {
      Element? nextTile;
      for (final el in find.byType(ExpansionTile).evaluate()) {
        if (!tappedExpansions.contains(el)) {
          nextTile = el;
          break;
        }
      }
      if (nextTile == null) break;
      tappedExpansions.add(nextTile);
      final tileFinder = find.byElementPredicate((e) => e == nextTile);
      await _ensureVisibleAndPump(tester, tileFinder);
      await tester.tap(tileFinder, warnIfMissed: false);
      await pumpFrames(tester, count: 4);
      _collectVisibleTextInto(tester, collected);
    }

    // Iterate mounted vertical scrollables with positive scroll extent without
    // indexing across await boundaries (TabBarView unmounts outgoing tabs).
    final visitedStates = <ScrollableState>{};
    while (true) {
      ScrollableState? nextState;
      for (final el in find.byType(Scrollable).evaluate()) {
        if (el is StatefulElement && el.state is ScrollableState) {
          final state = el.state as ScrollableState;
          if (!state.mounted) continue;
          final pos = state.position;
          if (pos.axis == Axis.vertical &&
              pos.maxScrollExtent > 0 &&
              !visitedStates.contains(state)) {
            nextState = state;
            break;
          }
        }
      }
      if (nextState == null) break;
      visitedStates.add(nextState);

      final position = nextState.position;
      final startPixels = position.pixels;
      final stepPx = (position.viewportDimension * 0.7).clamp(160.0, 500.0);

      position.jumpTo(0.0);
      await pumpFrames(tester, count: 2);
      _collectVisibleTextInto(tester, collected);

      var offset = 0.0;
      while (nextState.mounted && offset < position.maxScrollExtent - 1.0) {
        offset = math.min(offset + stepPx, position.maxScrollExtent);
        position.jumpTo(offset);
        await pumpFrames(tester, count: 2);
        _collectVisibleTextInto(tester, collected);
      }
      if (nextState.mounted && position.pixels != startPixels) {
        position.jumpTo(startPixels);
        await pumpFrames(tester, count: 2);
      }
    }
  }

  final tabCount = find.byType(Tab).evaluate().length;
  if (tabCount > 0) {
    for (var i = 0; i < tabCount; i++) {
      final tabFinder = find.byType(Tab).at(i);
      await _ensureVisibleAndPump(tester, tabFinder);
      await tester.tap(tabFinder);
      await pumpFrames(tester, count: 10);
      await sweepCurrentTab();
    }
  } else {
    await sweepCurrentTab();
  }

  return collected.join(' | ');
}

/// Collects all visible text on the current screen (without scrolling).
String readAllVisibleText(WidgetTester tester) {
  final collected = <String>{};
  _collectVisibleTextInto(tester, collected);
  return collected.join(' | ');
}

List<Element> _findInteractiveElementsFor(Finder targetFinder) {
  final seen = <Element>{};
  final result = <Element>[];
  for (final textEl in targetFinder.evaluate()) {
    final singleText = find.byElementPredicate((e) => e == textEl);
    Element? foundInteractive;
    // Pass 1: prefer canonical Material interactive controls (ListTile, Chip,
    // ButtonStyleButton, InkWell, etc.) over inner GestureDetectors.
    textEl.visitAncestorElements((ancestor) {
      if (_isInteractiveControlWidget(ancestor.widget)) {
        foundInteractive = ancestor;
        return false;
      }
      return true;
    });
    if (foundInteractive == null) {
      // Fallback check via find.ancestor for ButtonStyleButton / ListTile generics.
      final fallbackButton = find.ancestor(
        of: singleText,
        matching: find.bySubtype<ButtonStyleButton>(),
      );
      if (fallbackButton.evaluate().isNotEmpty) {
        foundInteractive = fallbackButton.evaluate().first;
      }
    }
    if (foundInteractive == null) {
      // Pass 2: tight GestureDetector(onTap != null) not wrapping a Scrollable.
      textEl.visitAncestorElements((ancestor) {
        final w = ancestor.widget;
        if (w is GestureDetector && w.onTap != null) {
          final ancestorFinder = find.byElementPredicate((e) => e == ancestor);
          final wrapsScrollable = find
              .descendant(of: ancestorFinder, matching: find.byType(Scrollable))
              .evaluate()
              .isNotEmpty;
          if (!wrapsScrollable) {
            foundInteractive = ancestor;
            return false;
          }
        }
        return true;
      });
    }
    if (foundInteractive != null && seen.add(foundInteractive!)) {
      result.add(foundInteractive!);
    }
  }
  return result;
}

Finder _findInteractiveElementsFinder(Finder targetFinder) {
  final elements = _findInteractiveElementsFor(targetFinder);
  if (elements.isEmpty) {
    return find.byWidgetPredicate((_) => false);
  }
  return find.byElementPredicate((e) => elements.contains(e));
}

/// Navigates back from Help or Settings to the Main Menu.
Future<void> navigateBackFromSubscreen(WidgetTester tester) async {
  final backTooltipFinder = find.byWidgetPredicate((widget) {
    if (widget is IconButton && widget.tooltip != null) {
      return widget.tooltip!.toLowerCase().contains('back');
    }
    if (widget is Tooltip) {
      return (widget.message ?? '').toLowerCase().contains('back');
    }
    return false;
  });

  for (final candidate in <Finder>[
    find.byType(BackButton),
    find.byIcon(Icons.arrow_back),
    find.byIcon(Icons.arrow_back_rounded),
    find.byIcon(Icons.arrow_back_ios_new),
    find.byIcon(Icons.arrow_back_ios),
    find.byIcon(Icons.close),
    backTooltipFinder,
    _findInteractiveTextButtonContaining('Back'),
    _findInteractiveTextButtonContaining('Done'),
    _findInteractiveTextButtonContaining('Return to Menu'),
    _findInteractiveTextButtonContaining('Return'),
  ]) {
    if (candidate.evaluate().isNotEmpty) {
      await _ensureVisibleAndPump(tester, candidate.first);
      await tester.tap(candidate.first);
      await _pumpRouteTransition(tester);
      return;
    }
  }
  fail('Could not find a back navigation control on the current subscreen.');
}

Finder _findTextButtonContaining(String snippet) {
  return _findInteractiveTextButtonContaining(snippet);
}

/// Navigates back to the Main Menu from an active game screen.
Future<void> navigateBackToMenuFromGame(
  WidgetTester tester, {
  required bool confirm,
}) async {
  final backFinder = _findGameBackToMenuControl();
  expect(
    backFinder,
    findsAtLeastNWidgets(1),
    reason: 'Expected a Back-to-Menu control on the in-game HUD.',
  );
  await _ensureVisibleAndPump(tester, backFinder.first);
  await tester.tap(backFinder.first);
  await _pumpRouteTransition(tester);

  final dialogs = find.byType(AlertDialog).evaluate().isNotEmpty
      ? find.byType(AlertDialog)
      : find.byType(Dialog);
  if (dialogs.evaluate().isNotEmpty) {
    final labels = confirm
        ? const <String>[
            'Leave',
            'Confirm',
            'Exit',
            'Yes',
            'Back to Menu',
            'Return',
          ]
        : const <String>['Cancel', 'Stay', 'Resume', 'Keep Playing', 'No'];
    final action = _findDialogAction(dialogs.last, labels);
    expect(
      action,
      findsAtLeastNWidgets(1),
      reason:
          'Expected ${confirm ? "confirm" : "cancel"} button inside Back-to-Menu dialog.',
    );
    await tester.tap(action.first);
    await _pumpRouteTransition(tester);
  }
}

Finder _findGameBackToMenuControl() {
  for (final keyName in const <String>[
    'hud_back_to_menu_button',
    'hud_menu_button',
    'hud_back_button',
  ]) {
    final byKey = find.byKey(ValueKey<String>(keyName));
    if (byKey.evaluate().isNotEmpty) return byKey;
  }
  for (final label in const <String>['Back to Menu', 'Main Menu', 'Menu']) {
    final byText = _findInteractiveTextButtonContaining(label);
    if (byText.evaluate().isNotEmpty) return byText;
  }
  for (final tooltipSnippet in const <String>['Menu', 'Back']) {
    final byTooltip = find.byWidgetPredicate((widget) {
      if (widget is IconButton && widget.tooltip != null) {
        return widget.tooltip!.toLowerCase().contains(
          tooltipSnippet.toLowerCase(),
        );
      }
      if (widget is Tooltip) {
        return (widget.message ?? '').toLowerCase().contains(
          tooltipSnippet.toLowerCase(),
        );
      }
      return false;
    });
    if (byTooltip.evaluate().isNotEmpty) return byTooltip;
  }
  final homeIcon = find.byIcon(Icons.home);
  if (homeIcon.evaluate().isNotEmpty) return homeIcon;
  for (final icon in const <IconData>[
    Icons.arrow_back,
    Icons.arrow_back_rounded,
    Icons.arrow_back_ios_new,
  ]) {
    final f = find.byIcon(icon);
    if (f.evaluate().isNotEmpty) return f;
  }
  return find.byIcon(Icons.arrow_back);
}

Finder _findDialogAction(Finder dialogFinder, List<String> candidateLabels) {
  Finder findInteractiveInDialog(bool Function(String lowerText) matcher) {
    final textMatches = find.descendant(
      of: dialogFinder,
      matching: find.byWidgetPredicate((widget) {
        if (widget is Text) {
          final value = (widget.data ?? widget.textSpan?.toPlainText() ?? '')
              .trim()
              .toLowerCase();
          return matcher(value);
        }
        return false;
      }),
    );
    for (final textEl in textMatches.evaluate()) {
      Element? buttonEl;
      textEl.visitAncestorElements((ancestor) {
        if (ancestor.widget is Dialog || ancestor.widget is AlertDialog) {
          return false;
        }
        final w = ancestor.widget;
        if (w is ButtonStyleButton || w is InkWell || w is IconButton) {
          buttonEl = ancestor;
          return false;
        }
        return true;
      });
      if (buttonEl != null) {
        return find.byElementPredicate((e) => e == buttonEl);
      }
    }
    return find.byWidgetPredicate((_) => false);
  }

  // Pass 1: exact text match inside an interactive button.
  for (final label in candidateLabels) {
    final lower = label.toLowerCase();
    final exactBtn = findInteractiveInDialog((v) => v == lower);
    if (exactBtn.evaluate().isNotEmpty) {
      return exactBtn;
    }
  }

  // Pass 2: substring match inside an interactive button.
  for (final label in candidateLabels) {
    final lower = label.toLowerCase();
    final containsBtn = findInteractiveInDialog((v) => v.contains(lower));
    if (containsBtn.evaluate().isNotEmpty) {
      return containsBtn;
    }
  }

  // Pass 3: tight GestureDetector button fallback (never raw title/body Text).
  for (final label in candidateLabels) {
    final lower = label.toLowerCase();
    final textMatches = find.descendant(
      of: dialogFinder,
      matching: find.byWidgetPredicate((widget) {
        if (widget is Text) {
          final value = (widget.data ?? widget.textSpan?.toPlainText() ?? '')
              .trim()
              .toLowerCase();
          return value == lower || value.contains(lower);
        }
        return false;
      }),
    );
    for (final textEl in textMatches.evaluate()) {
      Element? gestureEl;
      textEl.visitAncestorElements((ancestor) {
        if (ancestor.widget is Dialog || ancestor.widget is AlertDialog) {
          return false;
        }
        final w = ancestor.widget;
        if (w is GestureDetector && w.onTap != null) {
          gestureEl = ancestor;
          return false;
        }
        return true;
      });
      if (gestureEl != null) {
        return find.byElementPredicate((e) => e == gestureEl);
      }
    }
  }

  return find.byWidgetPredicate((_) => false);
}

/// Handles the Main Menu `Exit` action and its confirmation dialog / web view.
Future<void> triggerAndHandleExit(
  WidgetTester tester, {
  required bool confirm,
}) async {
  await tapMenuOption(tester, 'Exit');

  final dialogs = find.byType(AlertDialog).evaluate().isNotEmpty
      ? find.byType(AlertDialog)
      : find.byType(Dialog);
  if (dialogs.evaluate().isNotEmpty) {
    final labels = confirm
        ? const <String>['Exit', 'Quit', 'Confirm', 'Yes']
        : const <String>['Cancel', 'Stay', 'No'];
    final action = _findDialogAction(dialogs.last, labels);
    expect(
      action,
      findsAtLeastNWidgets(1),
      reason:
          'Expected ${confirm ? "confirm" : "cancel"} button in Exit dialog.',
    );
    await tester.tap(action.first);
    await pumpFrames(tester, count: 10);
    return;
  }

  // If Exit immediately rendered a Web-style "Session Ended" view without a dialog.
  if (!confirm) {
    final returnBtn = _findTextButtonContaining('Return to Menu');
    if (returnBtn.evaluate().isNotEmpty) {
      await tester.tap(returnBtn.first);
      await pumpFrames(tester, count: 10);
    }
  }
}

/// Scrolls Settings until a widget matching [buildFinder] becomes visible, if any.
/// Re-evaluates [buildFinder] on every scroll step so lazy `ListView` recycling
/// never leaves stale `Element` references.
Future<bool> _scrollSettingsUntilFound(
  WidgetTester tester,
  Finder Function() buildFinder, {
  bool jumpToTopFirst = true,
}) async {
  final scrollableFinder = _findTopmostVerticalScrollable(tester);
  if (scrollableFinder == null) {
    return buildFinder().evaluate().isNotEmpty;
  }
  final scrollableState =
      (scrollableFinder.evaluate().first as StatefulElement).state
          as ScrollableState;
  final position = scrollableState.position;

  if (!jumpToTopFirst) {
    if (buildFinder().hitTestable().evaluate().isNotEmpty) {
      return true;
    }
    for (var i = 0; i < 24; i++) {
      if (position.pixels >= position.maxScrollExtent - 1.0) {
        break;
      }
      await tester.drag(scrollableFinder, const Offset(0, -240));
      await pumpFrames(tester, count: 3);
      if (buildFinder().hitTestable().evaluate().isNotEmpty) {
        return true;
      }
    }
  }

  if (position.pixels > 0.0) {
    position.jumpTo(0.0);
    await pumpFrames(tester, count: 2);
  }
  if (buildFinder().hitTestable().evaluate().isNotEmpty) {
    return true;
  }

  for (var i = 0; i < 24; i++) {
    if (position.pixels >= position.maxScrollExtent - 1.0) {
      break;
    }
    await tester.drag(scrollableFinder, const Offset(0, -240));
    await pumpFrames(tester, count: 3);
    if (buildFinder().hitTestable().evaluate().isNotEmpty) {
      return true;
    }
  }
  return buildFinder().evaluate().isNotEmpty;
}

List<Element> _sortElementsByPosition(
  WidgetTester tester,
  Iterable<Element> elements,
) {
  final sorted = List<Element>.from(elements)
    ..sort((a, b) {
      final ca = tester.getCenter(find.byElementPredicate((e) => e == a));
      final cb = tester.getCenter(find.byElementPredicate((e) => e == b));
      final dyDiff = ca.dy - cb.dy;
      if (dyDiff.abs() > 24.0) {
        return dyDiff < 0 ? -1 : 1;
      }
      return ca.dx.compareTo(cb.dx);
    });
  return sorted;
}

List<Element> _findMountedFactionDropdowns(WidgetTester tester) {
  final dropdownFinder = find.byWidgetPredicate(
    (w) => w is DropdownButton || w is DropdownMenu,
  );
  final factionDropdowns = <Element>[];
  for (final el in dropdownFinder.evaluate()) {
    final elFinder = find.byElementPredicate((e) => e == el);
    final textBuffer = <String>{};
    for (final te in find
        .descendant(of: elFinder, matching: find.byType(Text))
        .evaluate()) {
      final t = te.widget as Text;
      textBuffer.add(t.data ?? t.textSpan?.toPlainText() ?? '');
    }
    for (final ee in find
        .descendant(of: elFinder, matching: find.byType(EditableText))
        .evaluate()) {
      final et = ee.widget as EditableText;
      textBuffer.add(et.controller.text);
    }
    final combined = textBuffer.join(' ');
    if (kAllFactionNames.any(combined.contains)) {
      factionDropdowns.add(el);
    }
  }
  return _sortElementsByPosition(tester, factionDropdowns);
}

bool _isExpansionTileHeaderListTile(Element el) {
  var isHeader = false;
  el.visitAncestorElements((ancestor) {
    if (ancestor.widget is ExpansionTile) {
      final tileFinder = find.byElementPredicate((e) => e == ancestor);
      final headerTiles = find.descendant(
        of: tileFinder,
        matching: find.byType(ListTile),
      );
      if (headerTiles.evaluate().isNotEmpty &&
          headerTiles.evaluate().first == el) {
        isHeader = true;
      }
      return false;
    }
    return true;
  });
  return isHeader;
}

Finder? _findSideExpansionTile(
  WidgetTester tester,
  List<String> sideHeaders,
) {
  final tiles = find.byType(ExpansionTile);
  if (tiles.evaluate().isEmpty) return null;
  for (final header in sideHeaders) {
    final lower = header.toLowerCase();
    for (final tileEl in tiles.evaluate()) {
      final tileFinder = find.byElementPredicate((e) => e == tileEl);
      final headerListTiles = find.descendant(
        of: tileFinder,
        matching: find.byType(ListTile),
      );
      final headerScope = headerListTiles.evaluate().isNotEmpty
          ? headerListTiles.first
          : tileFinder;
      final headerTexts = find
          .descendant(of: headerScope, matching: find.byType(Text))
          .evaluate()
          .map((e) {
            final t = e.widget as Text;
            return (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase();
          })
          .join(' ');
      if (_kCameraExcludeTerms.any(headerTexts.contains)) {
        continue;
      }
      final matched = (lower == 'red' || lower == 'blue')
          ? RegExp('\\b$lower\\b').hasMatch(headerTexts)
          : headerTexts.contains(lower);
      if (matched) {
        return tileFinder;
      }
    }
  }
  return null;
}

Future<bool> _selectFactionInExpansionTile(
  WidgetTester tester,
  List<String> sideHeaders,
  String factionName,
) async {
  final initialTile = _findSideExpansionTile(tester, sideHeaders);
  if (initialTile == null) return false;

  final distinctFactions = <String>{};
  for (final textEl in find
      .descendant(of: initialTile, matching: find.byType(Text))
      .evaluate()) {
    final t = textEl.widget as Text;
    final s = (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase();
    for (final f in kAllFactionNames) {
      if (s.contains(f.toLowerCase())) {
        distinctFactions.add(f);
      }
    }
  }
  final listTilesInTile = find
      .descendant(of: initialTile, matching: find.byType(ListTile))
      .evaluate()
      .length;
  final nonTileInteractiveInTile = find
      .descendant(
        of: initialTile,
        matching: find.byWidgetPredicate(
          (w) =>
              w is ButtonStyleButton ||
              w is ChoiceChip ||
              w is FilterChip ||
              w is ActionChip ||
              w is RawChip ||
              w is RadioListTile ||
              w is CheckboxListTile ||
              w is SwitchListTile,
        ),
      )
      .evaluate()
      .length;
  final alreadyExpanded =
      distinctFactions.length >= 2 ||
      listTilesInTile > 1 ||
      nonTileInteractiveInTile > 0;

  if (!alreadyExpanded) {
    final headerTiles = find.descendant(
      of: initialTile,
      matching: find.byType(ListTile),
    );
    final headerTapTarget = headerTiles.evaluate().isNotEmpty
        ? headerTiles.first
        : initialTile;
    await _ensureVisibleAndPump(tester, headerTapTarget);
    await tester.tap(headerTapTarget);
    await pumpFrames(tester, count: 10);
  }

  Finder buildInTileOption() {
    final currentTile = _findSideExpansionTile(tester, sideHeaders);
    if (currentTile == null) {
      return find.byWidgetPredicate((_) => false);
    }
    final headerTiles = find.descendant(
      of: currentTile,
      matching: find.byType(ListTile),
    );
    final headerEl = headerTiles.evaluate().isNotEmpty
        ? headerTiles.evaluate().first
        : null;
    final currentTileEl = currentTile.evaluate().first;
    final inTileTexts = find.descendant(
      of: currentTile,
      matching: find.textContaining(factionName),
    );
    final interactive = _findInteractiveElementsFor(inTileTexts)
        .where((el) => el != headerEl && el != currentTileEl)
        .toList();
    if (interactive.isEmpty) {
      return find.byWidgetPredicate((_) => false);
    }
    return find.byElementPredicate((e) => interactive.contains(e));
  }

  final found = await _scrollSettingsUntilFound(
    tester,
    buildInTileOption,
    jumpToTopFirst: false,
  );
  if (!found) return false;

  final option = buildInTileOption();
  final sorted = _sortElementsByPosition(tester, option.evaluate());
  if (sorted.isEmpty) return false;
  final target = find.byElementPredicate((e) => e == sorted.first);
  await _ensureVisibleAndPump(tester, target);
  await tester.tap(target);
  await pumpFrames(tester, count: 8);
  return true;
}

/// Selects [factionName] on the Settings screen for [side] (`red` = Side 1,
/// `blue` = Side 2). Resilient across DropdownButton, Material 3 DropdownMenu,
/// SegmentedButton/TabBar side switchers, ExpansionTiles, dual-list Chips/Cards,
/// and modal picker sheets/dialogs.
Future<void> selectFactionForSide(
  WidgetTester tester,
  PlayerSide side,
  String factionName,
) async {
  final sideHeaders = side == PlayerSide.red
      ? const <String>['Side 1', 'Red Faction', 'Red Side', 'Red Force', 'Red']
      : const <String>['Side 2', 'Blue Faction', 'Blue Side', 'Blue Force', 'Blue'];

  // 1. DropdownButton / Material 3 DropdownMenu faction pickers
  //    (strictly excluding DropdownMenuItem!), scrolling if the 2nd dropdown
  //    is below the fold in a lazy Scrollable.
  final branch1Scrollable = _findTopmostVerticalScrollable(tester);
  if (branch1Scrollable != null) {
    final scrollableState =
        (branch1Scrollable.evaluate().first as StatefulElement).state
            as ScrollableState;
    if (scrollableState.position.pixels > 0.0) {
      scrollableState.position.jumpTo(0.0);
      await pumpFrames(tester, count: 2);
    }
  }

  Element? targetDropdownEl;
  final initialDropdowns = _findMountedFactionDropdowns(tester);
  if (initialDropdowns.length >= 2) {
    targetDropdownEl = side == PlayerSide.red
        ? initialDropdowns.first
        : initialDropdowns[1];
  } else if (branch1Scrollable != null) {
    final scrollableState =
        (branch1Scrollable.evaluate().first as StatefulElement).state
            as ScrollableState;
    final position = scrollableState.position;

    final discovered = <({double docY, double dx})>[];
    void recordVisibleDropdowns() {
      for (final el in _findMountedFactionDropdowns(tester)) {
        final center = tester.getCenter(
          find.byElementPredicate((e) => e == el),
        );
        final docY = position.pixels + center.dy;
        final alreadyRecorded = discovered.any(
          (d) =>
              (d.docY - docY).abs() <= 24.0 &&
              (d.dx - center.dx).abs() <= 24.0,
        );
        if (!alreadyRecorded) {
          discovered.add((docY: docY, dx: center.dx));
        }
      }
    }

    recordVisibleDropdowns();
    for (var i = 0; i < 24 && discovered.length < 2; i++) {
      if (position.pixels >= position.maxScrollExtent - 1.0) {
        break;
      }
      await tester.drag(branch1Scrollable, const Offset(0, -240));
      await pumpFrames(tester, count: 3);
      recordVisibleDropdowns();
    }

    if (discovered.length >= 2) {
      discovered.sort((a, b) {
        final dyDiff = a.docY - b.docY;
        if (dyDiff.abs() > 24.0) {
          return dyDiff < 0 ? -1 : 1;
        }
        return a.dx.compareTo(b.dx);
      });
      final targetPos =
          side == PlayerSide.red ? discovered.first : discovered.last;

      Element? findDropdownAtTarget() {
        for (final el in _findMountedFactionDropdowns(tester)) {
          final center = tester.getCenter(
            find.byElementPredicate((e) => e == el),
          );
          final docY = position.pixels + center.dy;
          if ((docY - targetPos.docY).abs() <= 24.0 &&
              (center.dx - targetPos.dx).abs() <= 24.0) {
            return el;
          }
        }
        return null;
      }

      targetDropdownEl = findDropdownAtTarget();
      if (targetDropdownEl == null) {
        if (position.pixels > 0.0) {
          position.jumpTo(0.0);
          await pumpFrames(tester, count: 2);
          targetDropdownEl = findDropdownAtTarget();
        }
        for (var i = 0; i < 24 && targetDropdownEl == null; i++) {
          if (position.pixels >= position.maxScrollExtent - 1.0) {
            break;
          }
          await tester.drag(branch1Scrollable, const Offset(0, -240));
          await pumpFrames(tester, count: 3);
          targetDropdownEl = findDropdownAtTarget();
        }
      }
    }
  }

  if (targetDropdownEl != null) {
    final targetEl = targetDropdownEl;
    final targetFinder = find.byElementPredicate((e) => e == targetEl);
    final isMaterial3Menu = targetEl.widget is DropdownMenu;

    await _ensureVisibleAndPump(tester, targetFinder);
    final preOpenScrollables = find.byType(Scrollable).evaluate().toSet();

    Future<void> scrollOverlayUntilFound(Finder Function() buildOption) async {
      if (buildOption().evaluate().isNotEmpty) return;
      final overlayScrollables = find
          .byType(Scrollable)
          .evaluate()
          .where((e) => !preOpenScrollables.contains(e))
          .toList();
      if (overlayScrollables.isEmpty) return;
      final overlayScrollable = find.byElementPredicate(
        (e) => e == overlayScrollables.last,
      );
      final scrollableState =
          (overlayScrollables.last as StatefulElement).state as ScrollableState;
      final position = scrollableState.position;
      if (position.pixels > 0.0) {
        position.jumpTo(0.0);
        await pumpFrames(tester, count: 2);
        if (buildOption().evaluate().isNotEmpty) {
          return;
        }
      }
      for (var i = 0; i < 16; i++) {
        if (position.pixels >= position.maxScrollExtent - 1.0) {
          break;
        }
        await tester.drag(overlayScrollable, const Offset(0, -200));
        await pumpFrames(tester, count: 3);
        if (buildOption().evaluate().isNotEmpty) {
          return;
        }
      }
    }

    if (isMaterial3Menu) {
      final textFields = find.descendant(
        of: targetFinder,
        matching: find.byType(TextField),
      );
      final anchorTap = textFields.evaluate().isNotEmpty
          ? textFields.first
          : targetFinder;
      await tester.tap(anchorTap);
      await pumpFrames(tester, count: 8);

      Finder buildMenuOption() {
        final menuItemBtns = find.ancestor(
          of: find.textContaining(factionName),
          matching: find.byType(MenuItemButton),
        );
        final visibleMenuBtns = menuItemBtns.hitTestable();
        return visibleMenuBtns.evaluate().isNotEmpty
            ? visibleMenuBtns
            : menuItemBtns;
      }

      await scrollOverlayUntilFound(buildMenuOption);
      final option = buildMenuOption();
      expect(
        option,
        findsAtLeastNWidgets(1),
        reason: 'DropdownMenu must list "$factionName".',
      );
      await _ensureVisibleAndPump(tester, option.last);
      await tester.tap(option.last);
      await pumpFrames(tester, count: 16, step: const Duration(milliseconds: 35));
    } else {
      await tester.tap(targetFinder);
      await pumpFrames(tester, count: 10);

      Finder buildDropdownOption() {
        final dropdownItems = find.ancestor(
          of: find.textContaining(factionName),
          matching: find.bySubtype<DropdownMenuItem<dynamic>>(),
        );
        final overlayItems = dropdownItems.evaluate().where((el) {
          final elFinder = find.byElementPredicate((e) => e == el);
          return find
              .ancestor(
                of: elFinder,
                matching: find.bySubtype<DropdownButton<dynamic>>(),
              )
              .evaluate()
              .isEmpty;
        }).toList();
        if (overlayItems.isEmpty) {
          return find.byWidgetPredicate((_) => false);
        }
        final overlayFinder = find.byElementPredicate(
          (e) => overlayItems.contains(e),
        );
        final visibleItems = overlayFinder.hitTestable();
        return visibleItems.evaluate().isNotEmpty ? visibleItems : overlayFinder;
      }

      await scrollOverlayUntilFound(buildDropdownOption);
      final option = buildDropdownOption();
      expect(
        option,
        findsAtLeastNWidgets(1),
        reason: 'DropdownButton must list "$factionName".',
      );
      await _ensureVisibleAndPump(tester, option.last);
      final inkAncestor = find.ancestor(
        of: option.last,
        matching: find.byType(InkWell),
      );
      final tapTarget = inkAncestor.evaluate().isNotEmpty
          ? inkAncestor.first
          : option.last;
      await tester.tap(tapTarget);
      // Must exceed Flutter's 300ms _DropdownRoute close animation (>= 450ms)
      // so back-to-back selectFactionForSide calls never hit the closing overlay.
      await pumpFrames(tester, count: 16, step: const Duration(milliseconds: 35));
    }
    return;
  }

  // Scroll to top before Branches 2–5.
  final topScrollable = _findTopmostVerticalScrollable(tester);
  if (topScrollable != null) {
    final scrollableState =
        (topScrollable.evaluate().first as StatefulElement).state
            as ScrollableState;
    if (scrollableState.position.pixels > 0.0) {
      scrollableState.position.jumpTo(0.0);
      await pumpFrames(tester, count: 2);
    }
  }

  // 2. SegmentedButton / TabBar side switcher BEFORE dual-list / ExpansionTile
  //    so a static Matchup Summary + single Wrap of ChoiceChips never short-circuits.
  final sideSwitcherTarget = _findSegmentedOrTabSideTarget(tester, sideHeaders);
  if (sideSwitcherTarget != null) {
    await _ensureVisibleAndPump(tester, sideSwitcherTarget);
    await tester.tap(sideSwitcherTarget);
    await pumpFrames(tester, count: 8);

    List<Element> nonSwitcherFactionMatches() {
      return _findInteractiveElementsFor(
        find.textContaining(factionName),
      ).where((el) {
        if (_isExpansionTileHeaderListTile(el)) return false;
        var insideSwitcher = false;
        el.visitAncestorElements((ancestor) {
          final w = ancestor.widget;
          if (w is TabBar ||
              w is SegmentedButton ||
              w.runtimeType.toString().startsWith('SegmentedButton')) {
            insideSwitcher = true;
            return false;
          }
          return true;
        });
        if (insideSwitcher) return false;
        final elFinder = find.byElementPredicate((e) => e == el);
        final text = find
            .descendant(of: elFinder, matching: find.byType(Text))
            .evaluate()
            .map((te) {
              final t = te.widget as Text;
              return (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase();
            })
            .join(' ');
        return !_kCameraExcludeTerms.any(text.contains);
      }).toList();
    }

    Finder nonSwitcherFactionFinder() {
      final matches = nonSwitcherFactionMatches();
      if (matches.isEmpty) {
        return find.byWidgetPredicate((_) => false);
      }
      return find.byElementPredicate((e) => matches.contains(e));
    }

    final foundAfterSwitch = await _scrollSettingsUntilFound(
      tester,
      nonSwitcherFactionFinder,
    );
    if (foundAfterSwitch) {
      final sorted = _sortElementsByPosition(
        tester,
        nonSwitcherFactionMatches(),
      );
      final chosen = sorted.length >= 2
          ? (side == PlayerSide.red ? sorted.first : sorted.last)
          : sorted.last;
      final target = find.byElementPredicate((e) => e == chosen);
      await _ensureVisibleAndPump(tester, target);
      await tester.tap(target);
      await pumpFrames(tester, count: 8);
      return;
    }
  }

  // 3. Header-scoped ExpansionTile handling (runs BEFORE dual-list matching so
  //    an expanded Side 1 tile embedding the selected faction name in its header
  //    can never collide with mirror-match selection).
  if (find.byType(ExpansionTile).evaluate().isNotEmpty) {
    var sideTile = _findSideExpansionTile(tester, sideHeaders);
    if (sideTile == null && topScrollable != null) {
      final scrollableState =
          (topScrollable.evaluate().first as StatefulElement).state
              as ScrollableState;
      final position = scrollableState.position;
      for (var i = 0; i < 24 && sideTile == null; i++) {
        if (position.pixels >= position.maxScrollExtent - 1.0) {
          break;
        }
        await tester.drag(topScrollable, const Offset(0, -200));
        await pumpFrames(tester, count: 3);
        sideTile = _findSideExpansionTile(tester, sideHeaders);
      }
    }
    if (sideTile != null) {
      if (await _selectFactionInExpansionTile(tester, sideHeaders, factionName)) {
        return;
      }
    } else if (topScrollable != null) {
      final scrollableState =
          (topScrollable.evaluate().first as StatefulElement).state
              as ScrollableState;
      if (scrollableState.position.pixels > 0.0) {
        scrollableState.position.jumpTo(0.0);
        await pumpFrames(tester, count: 2);
      }
    }
  }

  // 4. Non-ExpansionTile explicit/paired side-switcher control (e.g. ChoiceChip
  //    'Side 1'/'Side 2' or modal-opening ListTile('Side 1 (Red)', onTap: ...)).
  var usedSideControl = false;
  final nonExpSideControl = _findNonExpansionSideSelectorControl(tester, side);
  if (nonExpSideControl != null) {
    await _ensureVisibleAndPump(tester, nonExpSideControl);
    await tester.tap(nonExpSideControl);
    await pumpFrames(tester, count: 6);
    usedSideControl = true;
  }

  // 5. Full-scroll (docY, dx) interactive list discovery (dual-list chips/cards,
  //    or single/modal list opened by Branch 4).
  bool isExcludedFactionOption(Element el) {
    if (_isExpansionTileHeaderListTile(el)) return true;
    var excluded = false;
    el.visitAncestorElements((ancestor) {
      final w = ancestor.widget;
      if (w is TabBar ||
          w is SegmentedButton ||
          w.runtimeType.toString().startsWith('SegmentedButton') ||
          w is DropdownButton ||
          w is DropdownMenu) {
        excluded = true;
        return false;
      }
      return true;
    });
    if (excluded) return true;

    final elFinder = find.byElementPredicate((e) => e == el);
    final combined = find
        .descendant(of: elFinder, matching: find.byType(Text))
        .evaluate()
        .map((te) {
          final t = te.widget as Text;
          return (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase();
        })
        .join(' ');
    return _kCameraExcludeTerms.any(combined.contains);
  }

  List<Element> findMountedFactionOptions({Finder? scope}) {
    final textFinder = scope == null
        ? find.textContaining(factionName)
        : find.descendant(of: scope, matching: find.textContaining(factionName));
    return _findInteractiveElementsFor(textFinder)
        .where((el) => !isExcludedFactionOption(el))
        .toList();
  }

  if (usedSideControl) {
    final modalFinders = find.byType(AlertDialog).evaluate().isNotEmpty
        ? find.byType(AlertDialog)
        : (find.byType(Dialog).evaluate().isNotEmpty
              ? find.byType(Dialog)
              : find.byType(BottomSheet));
    final modalScope = modalFinders.evaluate().isNotEmpty
        ? modalFinders.last
        : null;

    Finder buildScopedFinder() {
      final matches = findMountedFactionOptions(scope: modalScope);
      if (matches.isEmpty) {
        return find.byWidgetPredicate((_) => false);
      }
      return find.byElementPredicate((e) => matches.contains(e));
    }

    if (await _scrollSettingsUntilFound(tester, buildScopedFinder)) {
      final sorted = _sortElementsByPosition(
        tester,
        findMountedFactionOptions(scope: modalScope),
      );
      if (sorted.isNotEmpty) {
        final chosen = sorted.length >= 2
            ? (side == PlayerSide.red ? sorted.first : sorted.last)
            : sorted.first;
        final target = find.byElementPredicate((e) => e == chosen);
        await _ensureVisibleAndPump(tester, target);
        await tester.tap(target);
        await pumpFrames(tester, count: 8);
        return;
      }
    }
  } else {
    final scrollableFinder = _findTopmostVerticalScrollable(tester);
    if (scrollableFinder == null) {
      final matches = findMountedFactionOptions();
      if (matches.isNotEmpty) {
        final sorted = _sortElementsByPosition(tester, matches);
        final chosen = sorted.length >= 2
            ? (side == PlayerSide.red ? sorted.first : sorted.last)
            : sorted.first;
        final target = find.byElementPredicate((e) => e == chosen);
        await _ensureVisibleAndPump(tester, target);
        await tester.tap(target);
        await pumpFrames(tester, count: 8);
        return;
      }
    } else {
      final scrollableState =
          (scrollableFinder.evaluate().first as StatefulElement).state
              as ScrollableState;
      final position = scrollableState.position;
      if (position.pixels > 0.0) {
        position.jumpTo(0.0);
        await pumpFrames(tester, count: 2);
      }

      final discovered = <({double docY, double dx})>[];
      void recordVisibleOptions() {
        for (final el in findMountedFactionOptions()) {
          final center = tester.getCenter(
            find.byElementPredicate((e) => e == el),
          );
          final docY = position.pixels + center.dy;
          final alreadyRecorded = discovered.any(
            (d) =>
                (d.docY - docY).abs() <= 24.0 &&
                (d.dx - center.dx).abs() <= 24.0,
          );
          if (!alreadyRecorded) {
            discovered.add((docY: docY, dx: center.dx));
          }
        }
      }

      if (_findSideExpansionTile(tester, sideHeaders) != null) {
        if (await _selectFactionInExpansionTile(tester, sideHeaders, factionName)) {
          return;
        }
      }
      recordVisibleOptions();

      for (var i = 0; i < 32 && discovered.length < 2; i++) {
        if (position.pixels >= position.maxScrollExtent - 1.0) {
          break;
        }
        await tester.drag(scrollableFinder, const Offset(0, -200));
        await pumpFrames(tester, count: 3);
        if (_findSideExpansionTile(tester, sideHeaders) != null) {
          if (await _selectFactionInExpansionTile(tester, sideHeaders, factionName)) {
            return;
          }
        }
        recordVisibleOptions();
      }

      if (discovered.isNotEmpty) {
        discovered.sort((a, b) {
          final dyDiff = a.docY - b.docY;
          if (dyDiff.abs() > 24.0) {
            return dyDiff < 0 ? -1 : 1;
          }
          return a.dx.compareTo(b.dx);
        });
        final targetPos = discovered.length >= 2
            ? (side == PlayerSide.red ? discovered.first : discovered.last)
            : discovered.first;

        Element? findOptionAtTarget() {
          for (final el in findMountedFactionOptions()) {
            final center = tester.getCenter(
              find.byElementPredicate((e) => e == el),
            );
            final docY = position.pixels + center.dy;
            if ((docY - targetPos.docY).abs() <= 24.0 &&
                (center.dx - targetPos.dx).abs() <= 24.0) {
              return el;
            }
          }
          return null;
        }

        var targetEl = findOptionAtTarget();
        if (targetEl == null) {
          if (position.pixels > 0.0) {
            position.jumpTo(0.0);
            await pumpFrames(tester, count: 2);
            targetEl = findOptionAtTarget();
          }
          for (var i = 0; i < 32 && targetEl == null; i++) {
            if (position.pixels >= position.maxScrollExtent - 1.0) {
              break;
            }
            await tester.drag(scrollableFinder, const Offset(0, -200));
            await pumpFrames(tester, count: 3);
            targetEl = findOptionAtTarget();
          }
        }

        if (targetEl != null) {
          final targetFinder = find.byElementPredicate((e) => e == targetEl);
          await _ensureVisibleAndPump(tester, targetFinder);
          await tester.tap(targetFinder);
          await pumpFrames(tester, count: 8);
          return;
        }
      }
    }
  }

  fail('Could not select "$factionName" for ${side.name} in Settings.');
}

Finder? _findSegmentedOrTabSideTarget(
  WidgetTester tester,
  List<String> targetSideHeaders,
) {
  final switchers = find.byWidgetPredicate(
    (w) =>
        w is TabBar ||
        w is SegmentedButton ||
        w.runtimeType.toString().startsWith('SegmentedButton'),
  );

  Finder? bestTarget;
  var bestScore = -1;

  for (final switcherEl in switchers.evaluate()) {
    final widget = switcherEl.widget;
    var optionCount = 0;
    if (widget is TabBar) {
      if (widget.tabs.length > 2) continue;
      optionCount = widget.tabs.length;
    } else if (widget is SegmentedButton) {
      if (widget.segments.length > 2) continue;
      optionCount = widget.segments.length;
    }

    final switcherFinder = find.byElementPredicate((e) => e == switcherEl);
    final texts = find.descendant(
      of: switcherFinder,
      matching: find.byType(Text),
    );
    final combined = texts
        .evaluate()
        .map((e) {
          final t = e.widget as Text;
          return (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase();
        })
        .join(' ');
    if (_kCameraExcludeTerms.any(combined.contains)) continue;

    final hasRed =
        combined.contains('side 1') || combined.contains('red');
    final hasBlue =
        combined.contains('side 2') || combined.contains('blue');
    if (!hasRed || !hasBlue) continue;

    var score = 0;
    if (combined.contains('side 1') && combined.contains('side 2')) {
      score += 3;
    }
    if (combined.contains('faction')) {
      score += 2;
    }
    if (optionCount == 2) {
      score += 1;
    }

    for (final header in targetSideHeaders) {
      final lower = header.toLowerCase();
      final match = find.descendant(
        of: switcherFinder,
        matching: find.byWidgetPredicate((w) {
          if (w is Text) {
            final v = (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase();
            return v.contains(lower);
          }
          return false;
        }),
      );
      if (match.evaluate().isNotEmpty) {
        final interactive = _findInteractiveElementsFinder(match);
        final candidate = interactive.evaluate().isNotEmpty
            ? interactive.first
            : match.first;
        if (score > bestScore) {
          bestScore = score;
          bestTarget = candidate;
        }
        break;
      }
    }
  }
  return bestTarget;
}

Finder? _findNonExpansionSideSelectorControl(
  WidgetTester tester,
  PlayerSide side,
) {
  final explicitLabels = side == PlayerSide.red
      ? const <String>[
          'Side 1',
          'Red Faction',
          'Red Side',
          'Red Force',
          'Player 1',
        ]
      : const <String>[
          'Side 2',
          'Blue Faction',
          'Blue Side',
          'Blue Force',
          'Player 2',
        ];

  bool hasExcludedAncestor(Element el) {
    var excluded = false;
    el.visitAncestorElements((ancestor) {
      final w = ancestor.widget;
      if (w is ExpansionTile ||
          w is TabBar ||
          w is SegmentedButton ||
          w.runtimeType.toString().startsWith('SegmentedButton') ||
          w is DropdownButton ||
          w is DropdownMenu) {
        excluded = true;
        return false;
      }
      return true;
    });
    return excluded;
  }

  String elementCombinedText(Element el) {
    final elFinder = find.byElementPredicate((e) => e == el);
    return find
        .descendant(of: elFinder, matching: find.byType(Text))
        .evaluate()
        .map((te) {
          final t = te.widget as Text;
          return (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase();
        })
        .join(' ')
        .trim();
  }

  for (final label in explicitLabels) {
    final finder = _findInteractiveTextButtonContaining(label);
    for (final el in finder.evaluate()) {
      if (hasExcludedAncestor(el)) continue;
      final text = elementCombinedText(el);
      if (_kCameraExcludeTerms.any(text.contains)) continue;
      return find.byElementPredicate((e) => e == el);
    }
  }

  // Paired bare 'Red'/'Blue' bar fallback: only when a Row/Wrap/ToggleButtons
  // holds both 'red' and 'blue' controls and zero camera-preset controls.
  final targetSideWord = side == PlayerSide.red ? 'red' : 'blue';
  final candidateControls = _findInteractiveTextButtonContaining(targetSideWord);
  for (final el in candidateControls.evaluate()) {
    if (hasExcludedAncestor(el)) continue;
    final text = elementCombinedText(el);
    if (_kCameraExcludeTerms.any(text.contains)) continue;
    if (text != targetSideWord && !text.startsWith('$targetSideWord ')) {
      continue;
    }

    Element? groupEl;
    el.visitAncestorElements((ancestor) {
      final w = ancestor.widget;
      if (w is Row || w is Wrap || w is ToggleButtons) {
        groupEl = ancestor;
        return false;
      }
      if (w is Card || w is ListView || w is Scaffold || w is Scrollable) {
        return false;
      }
      return true;
    });
    if (groupEl == null) continue;

    final groupFinder = find.byElementPredicate((e) => e == groupEl);
    final groupTexts = find
        .descendant(of: groupFinder, matching: find.byType(Text))
        .evaluate()
        .map((te) {
          final t = te.widget as Text;
          return (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase().trim();
        })
        .toList();
    if (groupTexts.any((t) => _kCameraExcludeTerms.any(t.contains))) {
      continue;
    }

    final hasRedCtrl = groupTexts.any((t) => t == 'red' || t.startsWith('red '));
    final hasBlueCtrl =
        groupTexts.any((t) => t == 'blue' || t.startsWith('blue '));
    if (hasRedCtrl && hasBlueCtrl) {
      return find.byElementPredicate((e) => e == el);
    }
  }

  return null;
}

/// Taps the Swap Factions button on the Settings screen.
Future<void> tapSwapFactionsInSettings(WidgetTester tester) async {
  Finder buildSwapTarget() {
    final textTarget = _findInteractiveTextButtonContaining('Swap');
    if (textTarget.evaluate().isNotEmpty) return textTarget;
    final byKey = find.byKey(const ValueKey<String>('settings_swap_factions'));
    if (byKey.evaluate().isNotEmpty) return byKey;
    return find.byIcon(Icons.swap_horiz).evaluate().isNotEmpty
        ? find.byIcon(Icons.swap_horiz)
        : find.byIcon(Icons.swap_vert);
  }

  await _scrollSettingsUntilFound(tester, buildSwapTarget);
  final target = buildSwapTarget();
  expect(
    target,
    findsAtLeastNWidgets(1),
    reason: 'Settings screen must expose a Swap Factions control.',
  );
  await _ensureVisibleAndPump(tester, target.first);
  await tester.tap(target.first);
  await pumpFrames(tester, count: 8);
}

/// Taps the Reset Defaults button on the Settings screen.
Future<void> tapResetDefaultsInSettings(WidgetTester tester) async {
  Finder buildResetTarget() => _findInteractiveTextButtonContaining('Reset');
  await _scrollSettingsUntilFound(tester, buildResetTarget);
  final target = buildResetTarget();
  expect(
    target,
    findsAtLeastNWidgets(1),
    reason: 'Settings screen must expose a Reset Defaults control.',
  );
  await _ensureVisibleAndPump(tester, target.first);
  await tester.tap(target.first);
  await pumpFrames(tester, count: 8);
}

/// Selects [mode] (`ThemeMode.light` or `ThemeMode.dark`) in Settings.
Future<void> selectSettingsThemeMode(
  WidgetTester tester,
  ThemeMode mode,
) async {
  final expectedBrightness = mode == ThemeMode.light
      ? Brightness.light
      : Brightness.dark;
  if (readActiveBrightness(tester) == expectedBrightness) {
    return;
  }

  final targetLabel = mode == ThemeMode.light ? 'light' : 'dark';
  final oppositeLabel = mode == ThemeMode.light ? 'dark' : 'light';

  bool switchListTileMatchesTarget(SwitchListTile tile, Element el) {
    final titleText = find
        .descendant(
          of: find.byElementPredicate((e) => e == el),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((e) {
          final t = e.widget as Text;
          return (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase();
        })
        .join(' ');
    if (titleText.contains('dark') && !titleText.contains('light')) {
      return (mode == ThemeMode.dark && tile.value) ||
          (mode == ThemeMode.light && !tile.value);
    }
    if (titleText.contains('light') && !titleText.contains('dark')) {
      return (mode == ThemeMode.light && tile.value) ||
          (mode == ThemeMode.dark && !tile.value);
    }
    return false;
  }

  // Tier 1: Explicit target-label interactive control (e.g. SegmentedButton
  // or ChoiceChip 'Light'/'Dark', or SwitchListTile('Dark Mode') when Dark).
  Finder buildThemeTarget() {
    final matchingTexts = find.byWidgetPredicate((widget) {
      if (widget is Text) {
        final value = (widget.data ?? widget.textSpan?.toPlainText() ?? '')
            .toLowerCase();
        return value.contains(targetLabel) && !value.contains(oppositeLabel);
      }
      return false;
    });
    return _findInteractiveElementsFinder(matchingTexts);
  }

  await _scrollSettingsUntilFound(tester, buildThemeTarget);
  final interactiveTarget = buildThemeTarget();

  if (interactiveTarget.evaluate().isNotEmpty) {
    final targetEl = interactiveTarget.evaluate().first;
    final targetWidget = targetEl.widget;
    final alreadyMatchesSwitch =
        targetWidget is SwitchListTile &&
        switchListTileMatchesTarget(targetWidget, targetEl);
    if (!alreadyMatchesSwitch) {
      await _ensureVisibleAndPump(tester, interactiveTarget.first);
      await tester.tap(interactiveTarget.first);
      await pumpFrames(tester, count: 8);
    }
  } else {
    // Tier 2: Theme-labeled SwitchListTile or Row/ListTile owning 1 Switch
    // (stops ancestor walk at Card/ListView/Scaffold/Scrollable).
    Finder buildLabeledThemeSwitchFinder() {
      final themeTexts = find.byWidgetPredicate((widget) {
        if (widget is Text) {
          final v = (widget.data ?? widget.textSpan?.toPlainText() ?? '')
              .toLowerCase();
          return v.contains('dark') ||
              v.contains('light') ||
              v.contains('theme');
        }
        return false;
      });
      final matchedControls = <Element>[];
      final seen = <Element>{};
      for (final textEl in themeTexts.evaluate()) {
        Element? ownerControl;
        textEl.visitAncestorElements((ancestor) {
          final w = ancestor.widget;
          if (w is SwitchListTile) {
            ownerControl = ancestor;
            return false;
          }
          if (w is Card || w is ListView || w is Scaffold || w is Scrollable) {
            return false;
          }
          if (w is Row || w is ListTile) {
            final ancestorFinder = find.byElementPredicate(
              (e) => e == ancestor,
            );
            final switches = find.descendant(
              of: ancestorFinder,
              matching: find.byType(Switch),
            );
            if (switches.evaluate().length == 1) {
              Element? switchListTileOwner;
              ancestor.visitAncestorElements((outer) {
                if (outer.widget is SwitchListTile) {
                  switchListTileOwner = outer;
                  return false;
                }
                if (outer.widget is Card ||
                    outer.widget is ListView ||
                    outer.widget is Scaffold ||
                    outer.widget is Scrollable) {
                  return false;
                }
                return true;
              });
              ownerControl = switchListTileOwner ?? switches.evaluate().first;
              return false;
            }
          }
          return true;
        });
        if (ownerControl != null && seen.add(ownerControl!)) {
          matchedControls.add(ownerControl!);
        }
      }
      if (matchedControls.isEmpty) {
        return find.byWidgetPredicate((_) => false);
      }
      return find.byElementPredicate((e) => matchedControls.contains(e));
    }

    await _scrollSettingsUntilFound(tester, buildLabeledThemeSwitchFinder);
    final labeledSwitches = buildLabeledThemeSwitchFinder();

    if (labeledSwitches.evaluate().isNotEmpty) {
      final targetEl = labeledSwitches.evaluate().first;
      final targetWidget = targetEl.widget;
      final alreadyMatchesSwitch =
          targetWidget is SwitchListTile &&
          switchListTileMatchesTarget(targetWidget, targetEl);
      if (!alreadyMatchesSwitch &&
          readActiveBrightness(tester) != expectedBrightness) {
        await _ensureVisibleAndPump(tester, labeledSwitches.first);
        await tester.tap(labeledSwitches.first);
        await pumpFrames(tester, count: 8);
      }
    } else {
      // Tier 3: Last-resort Switch / SwitchListTile fallback.
      Finder buildSwitchFinder() => find.byType(Switch).evaluate().isNotEmpty
          ? find.byType(Switch)
          : find.byType(SwitchListTile);
      await _scrollSettingsUntilFound(tester, buildSwitchFinder);
      final switches = buildSwitchFinder();
      expect(
        switches,
        findsAtLeastNWidgets(1),
        reason: 'Expected Light/Dark selector or Switch in Settings.',
      );
      if (readActiveBrightness(tester) != expectedBrightness) {
        await _ensureVisibleAndPump(tester, switches.first);
        await tester.tap(switches.first);
        await pumpFrames(tester, count: 8);
      }
    }
  }

  expect(readActiveBrightness(tester), expectedBrightness);
}

/// Selects the default [preset] camera angle in Settings.
Future<void> selectSettingsCameraPreset(
  WidgetTester tester,
  E2ECameraPreset preset,
) async {
  final specificLabels = switch (preset) {
    E2ECameraPreset.redCommander => const <String>['Red Commander', 'Classic'],
    E2ECameraPreset.blueCommander => const <String>['Blue Commander'],
    E2ECameraPreset.tacticalTop => const <String>[
      'Tactical Top',
      'Top',
      'High',
    ],
    E2ECameraPreset.sideOverview => const <String>[
      'Side Overview',
      'Overview',
    ],
  };
  final fallbackShortLabels = switch (preset) {
    E2ECameraPreset.redCommander => const <String>['Red'],
    E2ECameraPreset.blueCommander => const <String>['Blue'],
    E2ECameraPreset.tacticalTop => const <String>[],
    E2ECameraPreset.sideOverview => const <String>['Side'],
  };
  final allLabels = <String>[...specificLabels, ...fallbackShortLabels];

  // 1. Check DropdownButton / DropdownMenu camera preset pickers (strictly
  //    excluding faction dropdowns so scrolling never stops early on them).
  List<Element> findMountedCameraDropdowns() {
    final dropdownFinder = find.byWidgetPredicate(
      (w) => w is DropdownButton || w is DropdownMenu,
    );
    final cameraDropdowns = <Element>[];
    for (final el in dropdownFinder.evaluate()) {
      final elFinder = find.byElementPredicate((e) => e == el);
      final textBuffer = <String>{};
      for (final te in find
          .descendant(of: elFinder, matching: find.byType(Text))
          .evaluate()) {
        final t = te.widget as Text;
        textBuffer.add(t.data ?? t.textSpan?.toPlainText() ?? '');
      }
      for (final ee in find
          .descendant(of: elFinder, matching: find.byType(EditableText))
          .evaluate()) {
        final et = ee.widget as EditableText;
        textBuffer.add(et.controller.text);
      }
      final combined = textBuffer.join(' ');
      final combinedLower = combined.toLowerCase();
      final isFactionDropdown = kAllFactionNames.any(combined.contains);
      final isCameraDropdown =
          !isFactionDropdown &&
          (_kCameraExcludeTerms.any(combinedLower.contains) ||
              combinedLower.trim() == 'red' ||
              combinedLower.trim() == 'blue' ||
              combinedLower.trim() == 'side');
      if (isCameraDropdown) {
        cameraDropdowns.add(el);
      }
    }
    return cameraDropdowns;
  }

  Finder buildCameraDropdownFinder() {
    final matches = findMountedCameraDropdowns();
    if (matches.isEmpty) {
      return find.byWidgetPredicate((_) => false);
    }
    return find.byElementPredicate((e) => matches.contains(e));
  }

  await _scrollSettingsUntilFound(tester, buildCameraDropdownFinder);
  for (final el in findMountedCameraDropdowns()) {
    final elFinder = find.byElementPredicate((e) => e == el);
    final isMaterial3Menu = el.widget is DropdownMenu;
    await _ensureVisibleAndPump(tester, elFinder);
    final preOpenScrollables = find.byType(Scrollable).evaluate().toSet();

    Future<void> scrollOverlayUntilFound(Finder Function() buildOption) async {
      if (buildOption().evaluate().isNotEmpty) return;
      final overlayScrollables = find
          .byType(Scrollable)
          .evaluate()
          .where((e) => !preOpenScrollables.contains(e))
          .toList();
      if (overlayScrollables.isEmpty) return;
      final overlayScrollable = find.byElementPredicate(
        (e) => e == overlayScrollables.last,
      );
      final scrollableState =
          (overlayScrollables.last as StatefulElement).state as ScrollableState;
      final position = scrollableState.position;
      if (position.pixels > 0.0) {
        position.jumpTo(0.0);
        await pumpFrames(tester, count: 2);
        if (buildOption().evaluate().isNotEmpty) {
          return;
        }
      }
      for (var i = 0; i < 16; i++) {
        if (position.pixels >= position.maxScrollExtent - 1.0) {
          break;
        }
        await tester.drag(overlayScrollable, const Offset(0, -200));
        await pumpFrames(tester, count: 3);
        if (buildOption().evaluate().isNotEmpty) {
          return;
        }
      }
    }

    if (isMaterial3Menu) {
      final textFields = find.descendant(
        of: elFinder,
        matching: find.byType(TextField),
      );
      await tester.tap(
        textFields.evaluate().isNotEmpty ? textFields.first : elFinder,
      );
      await pumpFrames(tester, count: 8);
      for (final label in allLabels) {
        Finder buildMenuOption() {
          final menuBtns = find.ancestor(
            of: find.textContaining(label),
            matching: find.byType(MenuItemButton),
          );
          final hitBtns = menuBtns.hitTestable();
          return hitBtns.evaluate().isNotEmpty ? hitBtns : menuBtns;
        }

        await scrollOverlayUntilFound(buildMenuOption);
        final option = buildMenuOption();
        if (option.evaluate().isNotEmpty) {
          await _ensureVisibleAndPump(tester, option.last);
          await tester.tap(option.last);
          await pumpFrames(
            tester,
            count: 16,
            step: const Duration(milliseconds: 35),
          );
          return;
        }
      }
    } else {
      await tester.tap(elFinder);
      await pumpFrames(tester, count: 10);
      for (final label in allLabels) {
        Finder buildCameraDropdownOption() {
          final dropdownItems = find.ancestor(
            of: find.textContaining(label),
            matching: find.bySubtype<DropdownMenuItem<dynamic>>(),
          );
          final overlayItems = dropdownItems.evaluate().where((itemEl) {
            final itemFinder = find.byElementPredicate((e) => e == itemEl);
            return find
                .ancestor(
                  of: itemFinder,
                  matching: find.bySubtype<DropdownButton<dynamic>>(),
                )
                .evaluate()
                .isEmpty;
          }).toList();
          if (overlayItems.isEmpty) {
            return find.byWidgetPredicate((_) => false);
          }
          final overlayFinder = find.byElementPredicate(
            (e) => overlayItems.contains(e),
          );
          final hitItems = overlayFinder.hitTestable();
          return hitItems.evaluate().isNotEmpty ? hitItems : overlayFinder;
        }

        await scrollOverlayUntilFound(buildCameraDropdownOption);
        final option = buildCameraDropdownOption();
        if (option.evaluate().isNotEmpty) {
          await _ensureVisibleAndPump(tester, option.last);
          final inkAncestor = find.ancestor(
            of: option.last,
            matching: find.byType(InkWell),
          );
          final tapTarget = inkAncestor.evaluate().isNotEmpty
              ? inkAncestor.first
              : option.last;
          await tester.tap(tapTarget);
          await pumpFrames(
            tester,
            count: 16,
            step: const Duration(milliseconds: 35),
          );
          return;
        }
      }
    }
  }

  // 2. Try specific non-colliding labels inside interactive controls first.
  for (final label in specificLabels) {
    Finder buildCandidate() => _findInteractiveTextButtonContaining(label);
    final found = await _scrollSettingsUntilFound(tester, buildCandidate);
    if (found) {
      final candidate = buildCandidate();
      await _ensureVisibleAndPump(tester, candidate.last);
      await tester.tap(candidate.last);
      await pumpFrames(tester, count: 8);
      return;
    }
  }

  // 3. Fallback short labels ('Red'/'Blue'/'Side') only on interactive controls
  //    that are NOT Side 1 / Side 2 faction headers.
  for (final label in fallbackShortLabels) {
    final lower = label.toLowerCase();
    Finder buildCandidate() {
      final safeTextFinder = find.byWidgetPredicate((widget) {
        if (widget is Text) {
          final v = (widget.data ?? widget.textSpan?.toPlainText() ?? '')
              .trim()
              .toLowerCase();
          if (v.contains('side 1') ||
              v.contains('side 2') ||
              v.contains('faction') ||
              v.contains('red side') ||
              v.contains('blue side')) {
            return false;
          }
          return v == lower || v.contains(lower);
        }
        return false;
      });
      return _findInteractiveElementsFinder(safeTextFinder);
    }

    final found = await _scrollSettingsUntilFound(tester, buildCandidate);
    if (found) {
      final candidate = buildCandidate();
      await _ensureVisibleAndPump(tester, candidate.last);
      await tester.tap(candidate.last);
      await pumpFrames(tester, count: 8);
      return;
    }
  }

  fail('Could not find camera preset option for ${preset.name} in Settings.');
}

/// Returns the bounding rectangle of the mounted 3D board viewport and asserts
/// its height is at least `180.0` logical pixels.
Rect findBoardViewportRect(WidgetTester tester) {
  final byKey = find.byKey(const ValueKey<String>('board_3d_viewport'));
  if (byKey.evaluate().isNotEmpty) {
    final rect = tester.getRect(byKey.first);
    expect(rect.height, greaterThanOrEqualTo(180.0));
    return rect;
  }

  Rect? largest;
  for (final el in find.byType(CustomPaint).evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == el));
    if (rect.height >= 180.0 &&
        (largest == null ||
            rect.width * rect.height > largest.width * largest.height)) {
      largest = rect;
    }
  }
  expect(
    largest,
    isNotNull,
    reason: 'Expected an active 3D board CustomPaint viewport (height >= 180).',
  );
  return largest!;
}

/// Pure-Dart 3D world-to-screen projection matching `SpringOrbitCamera3D`
/// (`fov = 42.0°`, `boardHalfWidth = 5.2`, `boardHalfDepth = 5.7`, `fill = 0.96`).
Offset projectBoardCoordToScreen(
  String algebraic,
  Rect viewportRect, {
  E2ECameraPreset preset = E2ECameraPreset.redCommander,
}) {
  final trimmed = algebraic.trim().toLowerCase();
  if (trimmed.length < 2 || trimmed.length > 3) {
    throw FormatException('Invalid algebraic coordinate: "$algebraic".');
  }
  final file = trimmed.codeUnitAt(0) - 97;
  final rank = int.parse(trimmed.substring(1)) - 1;
  if (file < 0 || file >= 11 || rank < 0 || rank >= 12) {
    throw RangeError('Board coordinate out of bounds: "$algebraic".');
  }
  final worldX = file - 5.0;
  const worldY = 0.0;
  final worldZ = -(rank - 5.5);

  final (double yaw, double pitch, double baseDistance) = switch (preset) {
    E2ECameraPreset.redCommander => (0.0, 0.86, 16.2),
    E2ECameraPreset.blueCommander => (math.pi, 0.86, 16.2),
    E2ECameraPreset.tacticalTop => (0.0, 1.42, 17.5),
    E2ECameraPreset.sideOverview => (-math.pi / 2.6, 0.72, 17.8),
  };

  final aspect = viewportRect.width / viewportRect.height;
  const fovDegrees = 42.0;
  const halfFovY = (fovDegrees * math.pi / 180.0) * 0.5;
  final tanHalfY = math.tan(halfFovY);
  final tanHalfX = tanHalfY * aspect;

  final cosYaw = math.cos(yaw);
  final sinYaw = math.sin(yaw);
  final cosPitch = math.cos(pitch);
  final sinPitch = math.sin(pitch);

  final rx = cosYaw;
  final rz = -sinYaw;
  final ux = -sinPitch * sinYaw;
  final uz = -sinPitch * cosYaw;
  final fx = -cosPitch * sinYaw;
  final fz = -cosPitch * cosYaw;

  var distance = baseDistance;
  const fill = 0.96;
  for (final sx in const <double>[-1.0, 1.0]) {
    final px = sx * 5.2;
    for (final sz in const <double>[-1.0, 1.0]) {
      final pz = sz * 5.7;
      final xCam = (px * rx + pz * rz).abs();
      final yCam = (px * ux + pz * uz).abs();
      final pDotF = px * fx + pz * fz;
      final cornerMinD = math.max(
        xCam / (fill * tanHalfX) - pDotF,
        yCam / (fill * tanHalfY) - pDotF,
      );
      if (cornerMinD > distance) {
        distance = cornerMinD;
      }
    }
  }
  distance = distance.clamp(7.5, 64.0);

  final horiz = distance * cosPitch;
  final eyeX = horiz * sinYaw;
  final eyeY = distance * sinPitch;
  final eyeZ = horiz * cosYaw;

  // Orthonormal camera view basis (`zAxis` points from target to eye).
  final zLen = math.sqrt(eyeX * eyeX + eyeY * eyeY + eyeZ * eyeZ);
  final zx = eyeX / zLen;
  final zy = eyeY / zLen;
  final zz = eyeZ / zLen;

  // `xAxis = normalize(cross(up(0,1,0), zAxis))` -> (zz, 0, -zx)
  final xRawX = zz;
  final xRawZ = -zx;
  final xLen = math.sqrt(xRawX * xRawX + xRawZ * xRawZ);
  final xx = xRawX / xLen;
  final xz = xRawZ / xLen;

  // `yAxis = cross(zAxis, xAxis)`
  final yx = zy * xz;
  final yy = zz * xx - zx * xz;
  final yz = -zy * xx;

  final dx = worldX - eyeX;
  final dy = worldY - eyeY;
  final dz = worldZ - eyeZ;

  final xc = dx * xx + dz * xz;
  final yc = dx * yx + dy * yy + dz * yz;
  final zc = dx * zx + dy * zy + dz * zz;

  final negZc = -zc;
  final ndcX = (xc / negZc) / tanHalfX;
  final ndcY = (yc / negZc) / tanHalfY;

  final localX = (ndcX * 0.5 + 0.5) * viewportRect.width;
  final localY = (0.5 - ndcY * 0.5) * viewportRect.height;
  return viewportRect.topLeft + Offset(localX, localY);
}

/// Projects [algebraic] onto the 3D viewport and taps that intersection.
Future<void> tapBoardCoord(
  WidgetTester tester,
  String algebraic, {
  E2ECameraPreset preset = E2ECameraPreset.redCommander,
}) async {
  final viewportRect = findBoardViewportRect(tester);
  final screenPt = projectBoardCoordToScreen(
    algebraic,
    viewportRect,
    preset: preset,
  );
  expect(
    viewportRect.contains(screenPt),
    isTrue,
    reason:
        'Projected coordinate $algebraic ($screenPt) must lie inside $viewportRect.',
  );
  await tester.tapAt(screenPt);
  await pumpFrames(tester, count: 4);
}

/// Selects [fromAlg], verifies its coordinate appears in the HUD selection
/// badge, and taps [toAlg] to execute the move.
Future<void> playMove(
  WidgetTester tester,
  String fromAlg,
  String toAlg, {
  E2ECameraPreset preset = E2ECameraPreset.redCommander,
}) async {
  await tapBoardCoord(tester, fromAlg, preset: preset);
  final viewportRect = findBoardViewportRect(tester);
  final bottomText = readBottomHudText(tester, viewportRect);
  expect(
    bottomText,
    contains(fromAlg),
    reason: 'Tapping $fromAlg must select the unit and show $fromAlg in HUD.',
  );
  await tapBoardCoord(tester, toAlg, preset: preset);
  await pumpFrames(tester, count: 6);
}

/// Reads all text displayed in the top HUD bar (above [viewportRect]).
String readTopHudText(WidgetTester tester, Rect viewportRect) {
  final parts = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final finder = find.byElementPredicate((e) => e == element);
    final pos = tester.getTopLeft(finder);
    if (pos.dy <= viewportRect.top + 2.0) {
      final widget = element.widget as Text;
      final value = (widget.data ?? widget.textSpan?.toPlainText() ?? '').trim();
      if (value.isNotEmpty) {
        parts.add(value);
      }
    }
  }
  return parts.join(' | ');
}

/// Reads all text displayed in the bottom HUD panel (below [viewportRect]).
String readBottomHudText(WidgetTester tester, Rect viewportRect) {
  final parts = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final finder = find.byElementPredicate((e) => e == element);
    final pos = tester.getTopLeft(finder);
    if (pos.dy >= viewportRect.bottom - 2.0) {
      final widget = element.widget as Text;
      final value = (widget.data ?? widget.textSpan?.toPlainText() ?? '').trim();
      if (value.isNotEmpty) {
        parts.add(value);
      }
    }
  }
  return parts.join(' | ');
}

/// Verifies [expectedType] is displayed in the bottom HUD (including
/// `'Tư lệnh • Commander'` when [expectedType] is [PieceType.commander]) and
/// returns normalized piece-info text across the entire selected-piece panel,
/// excluding camera preset chip labels (`Red`, `Blue`, `Top`, `Side`),
/// algebraic coordinates (`g1`..`g12`), and legal-move / carrier / hero status
/// boilerplate so both single-`Text` and multi-`Text` M4 HUD layouts work.
String readPiecePanelSummaryFromBottomHud(
  WidgetTester tester,
  Rect viewportRect,
  PieceType expectedType,
) {
  final raw = readBottomHudText(tester, viewportRect);
  expect(
    raw,
    contains(expectedType.displayNameEn),
    reason: 'Expected bottom HUD to contain "${expectedType.displayNameEn}" in "$raw".',
  );
  if (expectedType == PieceType.commander) {
    expect(
      raw,
      contains('Tư lệnh • Commander'),
      reason: 'Expected bottom HUD to preserve "Tư lệnh • Commander" in "$raw".',
    );
  }

  final coordPattern = RegExp(r'^[a-k](?:1[0-2]|[1-9])$', caseSensitive: true);
  final inlineCoordPattern = RegExp(
    r'\b[a-k](?:1[0-2]|[1-9])\b',
    caseSensitive: true,
  );
  final legalMovesPattern = RegExp(
    r'\b\d+\s+legal\s+moves?\b',
    caseSensitive: false,
  );
  final carrierPattern = RegExp(
    r'\bCarrier\s*\(\d+/\d+\)',
    caseSensitive: false,
  );
  final heroicPattern = RegExp(
    r'\bHeroic\s*\(\+10\)',
    caseSensitive: false,
  );
  final sideFactionTagPattern = RegExp(
    r'^(?:Red|Blue|Side\s*[12])\s*\(([^)]+)\)$',
    caseSensitive: false,
  );

  String normalizeToken(String token) {
    final trimmed = token.trim();
    final match = sideFactionTagPattern.firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return trimmed;
  }

  bool isBoilerplateToken(String token) {
    final trimmed = token.trim();
    final lower = trimmed.toLowerCase();
    return lower.isEmpty ||
        lower == 'red' ||
        lower == 'blue' ||
        lower == 'top' ||
        lower == 'side' ||
        lower == 'hero' ||
        lower == 'side 1' ||
        lower == 'side 2' ||
        coordPattern.hasMatch(trimmed);
  }

  final normalizedSegments = <String>[];
  for (final rawSeg in raw.split(' | ')) {
    final seg = rawSeg.trim();
    if (seg.isEmpty) continue;
    if (coordPattern.hasMatch(seg)) {
      continue;
    }

    var cleaned = seg
        .replaceAll(legalMovesPattern, '')
        .replaceAll(carrierPattern, '')
        .replaceAll(heroicPattern, '')
        .replaceAll(inlineCoordPattern, '')
        .trim();
    cleaned = cleaned.replaceAll(RegExp(r'^[\s•|·-]+|[\s•|·-]+$'), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s*[•·]\s*(?:[•·]\s*)+'), ' • ').trim();
    cleaned = normalizeToken(cleaned);
    if (cleaned.isEmpty || isBoilerplateToken(cleaned)) continue;

    if (cleaned.contains('•') || cleaned.contains('·')) {
      final subParts = cleaned
          .split(RegExp(r'\s*[•·]\s*'))
          .map(normalizeToken)
          .where((p) => !isBoilerplateToken(p))
          .toList();
      if (subParts.isEmpty) continue;
      cleaned = subParts.join(' • ');
    }
    normalizedSegments.add(cleaned);
  }

  if (normalizedSegments.isEmpty) {
    fail('Expected non-empty selected-piece summary in bottom HUD "$raw".');
  }
  return normalizedSegments.join(' | ');
}

/// Taps the Undo button in the in-game HUD.
Future<void> tapHudUndo(WidgetTester tester) async {
  final finder = _firstNonEmpty(<Finder>[
    find.byKey(const ValueKey<String>('hud_undo_button')),
    find.byTooltip('Undo'),
    _findTextButtonContaining('Undo'),
  ]);
  expect(finder, findsAtLeastNWidgets(1), reason: 'HUD Undo button missing.');
  await tester.tap(finder.first);
  await pumpFrames(tester, count: 6);
}

/// Taps the Rematch / New Match button in the in-game HUD.
Future<void> tapHudRematch(WidgetTester tester) async {
  final finder = _firstNonEmpty(<Finder>[
    find.byKey(const ValueKey<String>('hud_new_match_button')),
    _findTextButtonContaining('Rematch'),
    _findTextButtonContaining('New Match'),
    find.byTooltip('Rematch'),
    find.byTooltip('New Match'),
  ]);
  expect(
    finder,
    findsAtLeastNWidgets(1),
    reason: 'HUD Rematch / New Match button missing.',
  );
  await tester.tap(finder.first);
  await pumpFrames(tester, count: 6);
}

/// Taps the Theme Toggle button in the in-game HUD.
Future<void> tapHudThemeToggle(WidgetTester tester) async {
  final finder = _firstNonEmpty(<Finder>[
    find.byKey(const ValueKey<String>('hud_theme_toggle_button')),
    find.byIcon(Icons.light_mode),
    find.byIcon(Icons.dark_mode),
  ]);
  expect(
    finder,
    findsAtLeastNWidgets(1),
    reason: 'HUD Theme Toggle button missing.',
  );
  await tester.tap(finder.first);
  await pumpFrames(tester, count: 6);
}

/// Selects a camera preset chip in the in-game HUD and waits for spring
/// camera interpolation to settle.
Future<void> tapHudCameraPreset(
  WidgetTester tester,
  E2ECameraPreset preset,
) async {
  final label = switch (preset) {
    E2ECameraPreset.redCommander => 'Red',
    E2ECameraPreset.blueCommander => 'Blue',
    E2ECameraPreset.tacticalTop => 'Top',
    E2ECameraPreset.sideOverview => 'Side',
  };
  final finder = _firstNonEmpty(<Finder>[
    find.byKey(ValueKey<String>('hud_camera_${preset.name}')),
    find.widgetWithText(ChoiceChip, label),
  ]);
  expect(
    finder,
    findsAtLeastNWidgets(1),
    reason: 'HUD camera preset "$label" missing.',
  );
  await tester.tap(finder.first);
  await pumpFrames(tester, count: 30, step: const Duration(milliseconds: 50));
}

Finder _firstNonEmpty(List<Finder> candidates) {
  for (final candidate in candidates) {
    if (candidate.evaluate().isNotEmpty) {
      return candidate;
    }
  }
  return candidates.first;
}

/// Parsed representation of a Khronos glTF 2.0 binary (`.glb`) asset.
final class GlbParsedData {
  const GlbParsedData({
    required this.totalLength,
    required this.gltfJson,
    required this.binBytes,
    required this.nodeNames,
    required this.socketNodeWorldPositions,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.minZ,
    required this.maxZ,
    required this.vertexCount,
    required this.geometryHash,
    required this.materialHash,
    required this.rawFileHash,
  });

  final int totalLength;
  final Map<String, dynamic> gltfJson;
  final Uint8List binBytes;
  final List<String> nodeNames;
  final Map<String, List<double>> socketNodeWorldPositions;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double minZ;
  final double maxZ;
  final int vertexCount;
  final int geometryHash;
  final int materialHash;
  final int rawFileHash;
}

/// Opaque-box Khronos glTF 2.0 `.glb` binary parser and contract validator.
///
/// Traverses the glTF scene node hierarchy composing full 4×4 column-major
/// transforms (`matrix` or `T * R * S`) for every node instance referencing a
/// mesh, validates BIN padding (`<= 3`), non-negative offsets, bufferView
/// bounds, indexed referenced triangle extent, and `BLENDER_ASSET_CONTRACT`
/// bounds `[-0.425, +0.425] × [0.0, +1.20] × [-0.425, +0.425]`.
GlbParsedData parseGlbBinaryOpaque(Uint8List bytes) {
  if (bytes.length < 20 || bytes.length % 4 != 0) {
    throw FormatException('Invalid GLB byte length: ${bytes.length}.');
  }

  final view = ByteData.sublistView(bytes);
  final magic = view.getUint32(0, Endian.little);
  if (magic != 0x46546C67) {
    throw FormatException(
      'Invalid GLB magic: 0x${magic.toRadixString(16)}.',
    );
  }

  final version = view.getUint32(4, Endian.little);
  if (version != 2) {
    throw FormatException('Unsupported glTF version: $version.');
  }

  final declaredLength = view.getUint32(8, Endian.little);
  if (declaredLength != bytes.length) {
    throw FormatException(
      'GLB length mismatch: header=$declaredLength actual=${bytes.length}.',
    );
  }

  final chunk0Len = view.getUint32(12, Endian.little);
  final chunk0Type = view.getUint32(16, Endian.little);
  if (chunk0Type != 0x4E4F534A) {
    throw FormatException(
      'Expected JSON chunk (0x4E4F534A), got 0x${chunk0Type.toRadixString(16)}.',
    );
  }
  if (chunk0Len <= 0 || chunk0Len % 4 != 0 || 20 + chunk0Len > bytes.length) {
    throw FormatException('Invalid JSON chunk length: $chunk0Len.');
  }

  final jsonText = utf8.decode(bytes.sublist(20, 20 + chunk0Len));
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('GLB JSON chunk must decode to an object.');
  }

  final asset = decoded['asset'];
  if (asset is! Map || asset['version'] != '2.0') {
    throw const FormatException('glTF asset.version must be "2.0".');
  }

  final binOffset = 20 + chunk0Len;
  if (binOffset + 8 > bytes.length) {
    throw const FormatException('Missing BIN chunk.');
  }
  final chunk1Len = view.getUint32(binOffset, Endian.little);
  final chunk1Type = view.getUint32(binOffset + 4, Endian.little);
  if (chunk1Type != 0x004E4942) {
    throw FormatException(
      'Expected BIN chunk (0x004E4942), got 0x${chunk1Type.toRadixString(16)}.',
    );
  }
  if (chunk1Len <= 0 ||
      chunk1Len % 4 != 0 ||
      binOffset + 8 + chunk1Len != bytes.length) {
    throw FormatException('Invalid BIN chunk length: $chunk1Len.');
  }
  final binBytes = Uint8List.sublistView(
    bytes,
    binOffset + 8,
    binOffset + 8 + chunk1Len,
  );
  final binView = ByteData.sublistView(binBytes);

  final buffers = decoded['buffers'];
  final bufferViews = decoded['bufferViews'];
  final accessors = decoded['accessors'];
  final meshes = decoded['meshes'];
  final nodes = decoded['nodes'];
  final materials = decoded['materials'];

  if (buffers is! List ||
      buffers.isEmpty ||
      bufferViews is! List ||
      bufferViews.isEmpty ||
      accessors is! List ||
      accessors.isEmpty ||
      meshes is! List ||
      meshes.isEmpty ||
      nodes is! List ||
      nodes.isEmpty ||
      materials is! List ||
      materials.isEmpty) {
    throw const FormatException(
      'glTF JSON missing required non-empty arrays (buffers/bufferViews/accessors/meshes/nodes/materials).',
    );
  }

  final buf0 = buffers.first;
  if (buf0 is! Map || buf0['byteLength'] is! int) {
    throw const FormatException('Invalid glTF buffer[0] byteLength.');
  }
  final buf0ByteLength = buf0['byteLength'] as int;
  if (buf0ByteLength <= 0 ||
      buf0ByteLength > binBytes.length ||
      (binBytes.length - buf0ByteLength) > 3) {
    throw FormatException(
      'glTF buffer[0].byteLength ($buf0ByteLength) mismatches BIN chunk (${binBytes.length}).',
    );
  }

  for (final bv in bufferViews) {
    if (bv is! Map || bv['byteLength'] is! int) {
      throw const FormatException('Invalid bufferView descriptor.');
    }
    final rawBufIdx = bv['buffer'];
    if (rawBufIdx != null && rawBufIdx != 0) {
      throw FormatException('Unsupported bufferView.buffer: $rawBufIdx.');
    }
    final rawOffset = bv['byteOffset'];
    if (rawOffset != null && rawOffset is! int) {
      throw const FormatException('Invalid bufferView.byteOffset.');
    }
    final offset = (rawOffset as int?) ?? 0;
    final length = bv['byteLength'] as int;
    if (offset < 0 ||
        length <= 0 ||
        offset > buf0ByteLength ||
        length > buf0ByteLength - offset) {
      throw FormatException(
        'bufferView out of bounds: offset=$offset length=$length buf=$buf0ByteLength.',
      );
    }
  }

  List<double> identityMat4() => <double>[
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0,
  ];

  List<double> mulMat4(List<double> a, List<double> b) {
    final c = List<double>.filled(16, 0.0);
    for (var col = 0; col < 4; col++) {
      final b0 = b[col * 4];
      final b1 = b[col * 4 + 1];
      final b2 = b[col * 4 + 2];
      final b3 = b[col * 4 + 3];
      for (var row = 0; row < 4; row++) {
        c[col * 4 + row] =
            a[row] * b0 +
            a[4 + row] * b1 +
            a[8 + row] * b2 +
            a[12 + row] * b3;
      }
    }
    return c;
  }

  List<double> readVec(Object? raw, int len, List<double> fallback, String name) {
    if (raw == null) return fallback;
    if (raw is! List || raw.length != len) {
      throw FormatException('Invalid glTF node $name.');
    }
    final out = <double>[];
    for (final v in raw) {
      if (v is! num || !v.toDouble().isFinite) {
        throw FormatException('Non-finite glTF node $name component.');
      }
      out.add(v.toDouble());
    }
    return out;
  }

  List<double> nodeLocalMat4(Map<dynamic, dynamic> node) {
    final rawMat = node['matrix'];
    if (rawMat != null) {
      return readVec(rawMat, 16, identityMat4(), 'matrix');
    }
    final t = readVec(
      node['translation'],
      3,
      const <double>[0.0, 0.0, 0.0],
      'translation',
    );
    final rRaw = readVec(
      node['rotation'],
      4,
      const <double>[0.0, 0.0, 0.0, 1.0],
      'rotation',
    );
    final qNorm = math.sqrt(
      rRaw[0] * rRaw[0] +
          rRaw[1] * rRaw[1] +
          rRaw[2] * rRaw[2] +
          rRaw[3] * rRaw[3],
    );
    if (qNorm <= 1e-12) {
      throw const FormatException('Zero-length quaternion in glTF node.');
    }
    final qx = rRaw[0] / qNorm;
    final qy = rRaw[1] / qNorm;
    final qz = rRaw[2] / qNorm;
    final qw = rRaw[3] / qNorm;
    final s = readVec(
      node['scale'],
      3,
      const <double>[1.0, 1.0, 1.0],
      'scale',
    );

    final xx = qx * qx;
    final yy = qy * qy;
    final zz = qz * qz;
    final xy = qx * qy;
    final xz = qx * qz;
    final yz = qy * qz;
    final wx = qw * qx;
    final wy = qw * qy;
    final wz = qw * qz;

    final r00 = 1.0 - 2.0 * (yy + zz);
    final r10 = 2.0 * (xy + wz);
    final r20 = 2.0 * (xz - wy);

    final r01 = 2.0 * (xy - wz);
    final r11 = 1.0 - 2.0 * (xx + zz);
    final r21 = 2.0 * (yz + wx);

    final r02 = 2.0 * (xz + wy);
    final r12 = 2.0 * (yz - wx);
    final r22 = 1.0 - 2.0 * (xx + yy);

    return <double>[
      r00 * s[0],
      r10 * s[0],
      r20 * s[0],
      0.0,
      r01 * s[1],
      r11 * s[1],
      r21 * s[1],
      0.0,
      r02 * s[2],
      r12 * s[2],
      r22 * s[2],
      0.0,
      t[0],
      t[1],
      t[2],
      1.0,
    ];
  }

  const contractEps = 1e-4;
  void assertWithinContractBox(double x, double y, double z, String context) {
    if (!x.isFinite || !y.isFinite || !z.isFinite) {
      throw FormatException('Non-finite $context coordinate in GLB.');
    }
    if (x < -0.425 - contractEps ||
        x > 0.425 + contractEps ||
        y < 0.0 - contractEps ||
        y > 1.20 + contractEps ||
        z < -0.425 - contractEps ||
        z > 0.425 + contractEps) {
      throw FormatException(
        '$context ($x, $y, $z) violates BLENDER_ASSET_CONTRACT bounding box.',
      );
    }
  }

  final nodeNames = <String>[];
  final referencedChildren = <int>{};
  for (final node in nodes) {
    if (node is! Map) {
      throw const FormatException('Invalid glTF node entry.');
    }
    final nodeName = node['name'];
    if (nodeName is String && nodeName.isNotEmpty) {
      nodeNames.add(nodeName);
    }
    final rawChildren = node['children'];
    if (rawChildren != null) {
      if (rawChildren is! List) {
        throw const FormatException('Invalid glTF node children.');
      }
      for (final c in rawChildren) {
        if (c is! int || c < 0 || c >= nodes.length) {
          throw FormatException('Invalid child node index: $c.');
        }
        referencedChildren.add(c);
      }
    }
  }

  final rootNodeIndices = <int>[];
  final scenes = decoded['scenes'];
  final rawSceneIdx = decoded['scene'];
  if (scenes != null) {
    if (scenes is! List || scenes.isEmpty) {
      throw const FormatException('Invalid glTF scenes array.');
    }
    final sIdx = (rawSceneIdx is int) ? rawSceneIdx : 0;
    if (sIdx < 0 || sIdx >= scenes.length || scenes[sIdx] is! Map) {
      throw FormatException('Invalid glTF scene index: $sIdx.');
    }
    final sceneObj = scenes[sIdx] as Map;
    final sceneNodes = sceneObj['nodes'];
    if (sceneNodes != null) {
      if (sceneNodes is! List) {
        throw const FormatException('Invalid glTF scene.nodes array.');
      }
      for (final n in sceneNodes) {
        if (n is! int || n < 0 || n >= nodes.length) {
          throw FormatException('Invalid scene root node index: $n.');
        }
        rootNodeIndices.add(n);
      }
    }
  } else {
    for (var i = 0; i < nodes.length; i++) {
      if (!referencedChildren.contains(i)) {
        rootNodeIndices.add(i);
      }
    }
  }

  if (rootNodeIndices.isEmpty) {
    throw const FormatException('glTF scene has no root nodes.');
  }

  final meshInstances = <(int, List<double>)>[];
  final socketNodeWorldPositions = <String, List<double>>{};

  void visitNode(int nodeIdx, List<double> parentWorld, Set<int> visiting) {
    if (!visiting.add(nodeIdx)) {
      throw FormatException('Cycle detected in glTF node hierarchy at $nodeIdx.');
    }
    final node = nodes[nodeIdx] as Map;
    final world = mulMat4(parentWorld, nodeLocalMat4(node));

    final nodeName = node['name'];
    if (nodeName is String && nodeName.startsWith('socket_passenger_')) {
      assertWithinContractBox(
        world[12],
        world[13],
        world[14],
        'Socket "$nodeName"',
      );
      socketNodeWorldPositions[nodeName] = <double>[
        world[12],
        world[13],
        world[14],
      ];
    }

    final rawMesh = node['mesh'];
    if (rawMesh != null) {
      if (rawMesh is! int || rawMesh < 0 || rawMesh >= meshes.length) {
        throw FormatException('Invalid node mesh index: $rawMesh.');
      }
      meshInstances.add((rawMesh, world));
    }

    final rawChildren = node['children'];
    if (rawChildren is List) {
      for (final child in rawChildren) {
        visitNode(child as int, world, visiting);
      }
    }
    visiting.remove(nodeIdx);
  }

  for (final rootIdx in rootNodeIndices) {
    visitNode(rootIdx, identityMat4(), <int>{});
  }

  if (meshInstances.isEmpty) {
    throw const FormatException('glTF scene has no mesh instances.');
  }

  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  var minZ = double.infinity;
  var maxZ = double.negativeInfinity;
  var totalVertices = 0;

  var geomHash = 0xcbf29ce484222325;
  int fnvMixInt(int hash, int value) {
    var h = hash;
    for (var b = 0; b < 4; b++) {
      h ^= (value >> (b * 8)) & 0xFF;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h;
  }

  void includeInBounds(double x, double y, double z) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
    if (z < minZ) minZ = z;
    if (z > maxZ) maxZ = z;
  }

  for (final (mIdx, world) in meshInstances) {
    final mesh = meshes[mIdx];
    if (mesh is! Map || mesh['primitives'] is! List) {
      throw const FormatException('Invalid mesh entry in glTF JSON.');
    }
    final prims = mesh['primitives'] as List;
    if (prims.isEmpty) {
      throw const FormatException('Mesh contains zero primitives.');
    }

    for (final prim in prims) {
      if (prim is! Map || prim['attributes'] is! Map) {
        throw const FormatException('Invalid mesh primitive.');
      }
      final attrs = prim['attributes'] as Map;
      final posAccessorIdx = attrs['POSITION'];
      if (posAccessorIdx is! int ||
          posAccessorIdx < 0 ||
          posAccessorIdx >= accessors.length) {
        throw const FormatException('Primitive missing valid POSITION accessor.');
      }
      final posAcc = accessors[posAccessorIdx];
      if (posAcc is! Map ||
          posAcc['componentType'] != 5126 ||
          posAcc['type'] != 'VEC3') {
        throw const FormatException('POSITION accessor must be FLOAT VEC3.');
      }
      final count = posAcc['count'];
      final bvIdx = posAcc['bufferView'];
      if (count is! int ||
          count <= 0 ||
          bvIdx is! int ||
          bvIdx < 0 ||
          bvIdx >= bufferViews.length) {
        throw const FormatException('Invalid POSITION accessor count/bufferView.');
      }
      final rawAccOffset = posAcc['byteOffset'];
      if (rawAccOffset != null && rawAccOffset is! int) {
        throw const FormatException('Invalid POSITION accessor byteOffset.');
      }
      final accOffset = (rawAccOffset as int?) ?? 0;
      if (accOffset < 0) {
        throw FormatException(
          'Negative POSITION accessor byteOffset: $accOffset.',
        );
      }

      final bv = bufferViews[bvIdx] as Map;
      final bvOffset = (bv['byteOffset'] as int?) ?? 0;
      final bvLength = bv['byteLength'] as int;
      final bvEnd = bvOffset + bvLength;
      final rawStride = bv['byteStride'];
      if (rawStride != null && rawStride is! int) {
        throw const FormatException('Invalid POSITION stride.');
      }
      final stride = (rawStride as int?) ?? 12;
      if (stride < 12) {
        throw FormatException('Invalid POSITION stride: $stride.');
      }
      if (bvLength < 12 ||
          accOffset > bvLength - 12 ||
          (count - 1) > (bvLength - accOffset - 12) ~/ stride ||
          accOffset + (count - 1) * stride + 12 > binBytes.length - bvOffset) {
        throw const FormatException(
          'POSITION accessor exceeds bufferView bounds.',
        );
      }

      final txList = List<double>.filled(count, 0.0);
      final tyList = List<double>.filled(count, 0.0);
      final tzList = List<double>.filled(count, 0.0);

      for (var i = 0; i < count; i++) {
        final base = bvOffset + accOffset + i * stride;
        if (base < bvOffset || base + 12 > bvEnd || base + 12 > binBytes.length) {
          throw const FormatException(
            'POSITION vertex read out of bufferView bounds.',
          );
        }
        final rx = binView.getFloat32(base, Endian.little);
        final ry = binView.getFloat32(base + 4, Endian.little);
        final rz = binView.getFloat32(base + 8, Endian.little);
        final x = world[0] * rx + world[4] * ry + world[8] * rz + world[12];
        final y = world[1] * rx + world[5] * ry + world[9] * rz + world[13];
        final z = world[2] * rx + world[6] * ry + world[10] * rz + world[14];

        assertWithinContractBox(x, y, z, 'Vertex');
        txList[i] = x;
        tyList[i] = y;
        tzList[i] = z;
        totalVertices++;

        geomHash = fnvMixInt(geomHash, binView.getUint32(base, Endian.little));
        geomHash = fnvMixInt(
          geomHash,
          binView.getUint32(base + 4, Endian.little),
        );
        geomHash = fnvMixInt(
          geomHash,
          binView.getUint32(base + 8, Endian.little),
        );
      }

      final indicesIdx = prim['indices'];
      if (indicesIdx == null) {
        for (var i = 0; i < count; i++) {
          includeInBounds(txList[i], tyList[i], tzList[i]);
        }
      } else {
        if (indicesIdx is! int ||
            indicesIdx < 0 ||
            indicesIdx >= accessors.length) {
          throw const FormatException('Invalid primitive indices accessor.');
        }
        final idxAcc = accessors[indicesIdx];
        if (idxAcc is! Map) {
          throw const FormatException('Invalid indices accessor entry.');
        }
        final idxCompType = idxAcc['componentType'];
        final idxCount = idxAcc['count'];
        final idxBvIdx = idxAcc['bufferView'];
        if (idxCount is! int ||
            idxCount <= 0 ||
            idxBvIdx is! int ||
            idxBvIdx < 0 ||
            idxBvIdx >= bufferViews.length) {
          throw const FormatException('Invalid indices accessor layout.');
        }
        final rawIdxAccOffset = idxAcc['byteOffset'];
        if (rawIdxAccOffset != null && rawIdxAccOffset is! int) {
          throw const FormatException('Invalid indices accessor byteOffset.');
        }
        final idxAccOffset = (rawIdxAccOffset as int?) ?? 0;
        if (idxAccOffset < 0) {
          throw FormatException(
            'Negative indices accessor byteOffset: $idxAccOffset.',
          );
        }

        final idxBv = bufferViews[idxBvIdx] as Map;
        final idxBvOffset = (idxBv['byteOffset'] as int?) ?? 0;
        final idxBvLength = idxBv['byteLength'] as int;
        final idxBvEnd = idxBvOffset + idxBvLength;
        final elemSize = switch (idxCompType) {
          5121 => 1,
          5123 => 2,
          5125 => 4,
          _ => throw FormatException(
            'Unsupported index componentType: $idxCompType.',
          ),
        };
        if (idxAccOffset > idxBvLength ||
            idxCount > (idxBvLength - idxAccOffset) ~/ elemSize) {
          throw const FormatException('Index read out of bufferView bounds.');
        }
        final idxBase = idxBvOffset + idxAccOffset;
        if (idxBase < idxBvOffset ||
            idxBase + idxCount * elemSize > idxBvEnd ||
            idxBase + idxCount * elemSize > binBytes.length) {
          throw const FormatException('Index read out of bufferView bounds.');
        }

        var primRefMinX = double.infinity;
        var primRefMaxX = double.negativeInfinity;
        var primRefMinY = double.infinity;
        var primRefMaxY = double.negativeInfinity;
        var primRefMinZ = double.infinity;
        var primRefMaxZ = double.negativeInfinity;

        for (var k = 0; k < idxCount; k++) {
          final off = idxBase + k * elemSize;
          final idxVal = switch (idxCompType) {
            5121 => binView.getUint8(off),
            5123 => binView.getUint16(off, Endian.little),
            5125 => binView.getUint32(off, Endian.little),
            _ => 0,
          };
          if (idxVal < 0 || idxVal >= count) {
            throw FormatException(
              'Index $idxVal out of range for $count vertices.',
            );
          }
          geomHash = fnvMixInt(geomHash, idxVal);

          final vx = txList[idxVal];
          final vy = tyList[idxVal];
          final vz = tzList[idxVal];
          includeInBounds(vx, vy, vz);
          if (vx < primRefMinX) primRefMinX = vx;
          if (vx > primRefMaxX) primRefMaxX = vx;
          if (vy < primRefMinY) primRefMinY = vy;
          if (vy > primRefMaxY) primRefMaxY = vy;
          if (vz < primRefMinZ) primRefMinZ = vz;
          if (vz > primRefMaxZ) primRefMaxZ = vz;
        }

        if ((primRefMaxX - primRefMinX) <= 1e-6 &&
            (primRefMaxY - primRefMinY) <= 1e-6 &&
            (primRefMaxZ - primRefMinZ) <= 1e-6) {
          throw const FormatException(
            'Indexed primitive has zero-extent referenced triangles.',
          );
        }
      }
    }
  }

  if (totalVertices <= 0) {
    throw const FormatException('GLB contains zero vertices.');
  }
  if ((maxX - minX) <= 1e-5 ||
      (maxY - minY) <= 1e-5 ||
      (maxZ - minZ) <= 1e-5) {
    throw const FormatException(
      'GLB referenced geometry has degenerate zero-extent bounding box.',
    );
  }

  final matBytes = utf8.encode(jsonEncode(materials));
  var matHash = 0xcbf29ce484222325;
  for (final b in matBytes) {
    matHash ^= b;
    matHash = (matHash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }

  var rawHash = 0xcbf29ce484222325;
  for (final b in bytes) {
    rawHash ^= b;
    rawHash = (rawHash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }

  return GlbParsedData(
    totalLength: bytes.length,
    gltfJson: decoded,
    binBytes: binBytes,
    nodeNames: List<String>.unmodifiable(nodeNames),
    socketNodeWorldPositions: Map<String, List<double>>.unmodifiable(
      socketNodeWorldPositions,
    ),
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
    minZ: minZ,
    maxZ: maxZ,
    vertexCount: totalVertices,
    geometryHash: geomHash,
    materialHash: matHash,
    rawFileHash: rawHash,
  );
}

/// Decodes `assets/models/asset_manifest.json` from disk.
Map<String, dynamic> loadAssetManifestJson() {
  final file = File('assets/models/asset_manifest.json');
  expect(
    file.existsSync(),
    isTrue,
    reason: 'assets/models/asset_manifest.json must exist.',
  );
  final raw = file.readAsStringSync();
  final decoded = jsonDecode(raw);
  expect(decoded, isA<Map<String, dynamic>>());
  return decoded as Map<String, dynamic>;
}

/// Normalizes a faction identifier string to match `kFactionManifestAliases`.
String? normalizeFactionKey(String raw) {
  final compact = raw.trim().toLowerCase().replaceAll('_', '').replaceAll(' ', '');
  for (final entry in kFactionManifestAliases.entries) {
    for (final alias in entry.value) {
      if (alias.replaceAll('_', '') == compact) {
        return entry.key;
      }
    }
  }
  return null;
}

/// Extracts all `(factionDisplayName, PieceType) -> glbPath` entries from the
/// additive faction section of `asset_manifest.json`, supporting Map or List
/// encodings while rejecting duplicates or empty paths.
Map<(String, PieceType), String> extractFactionMeshPaths(
  Map<String, dynamic> manifestJson,
) {
  final rawSection =
      manifestJson['factionMeshes'] ??
      manifestJson['faction_meshes'] ??
      manifestJson['factionPieces'] ??
      manifestJson['faction_pieces'];
  expect(
    rawSection,
    isNotNull,
    reason:
        'asset_manifest.json must declare additive factionMeshes covering 11×11 models.',
  );

  final result = <(String, PieceType), String>{};

  void addEntry(String factionRaw, String pieceRaw, String glbPath) {
    final faction = normalizeFactionKey(factionRaw);
    expect(
      faction,
      isNotNull,
      reason: 'Unrecognized faction key "$factionRaw" in manifest.',
    );
    final pieceType = PieceType.tryFromJsonValue(pieceRaw);
    expect(
      pieceType,
      isNotNull,
      reason: 'Unrecognized piece type "$pieceRaw" in manifest.',
    );
    expect(
      glbPath.trim().isNotEmpty,
      isTrue,
      reason: 'Empty glbPath for ($faction, $pieceRaw).',
    );
    final key = (faction!, pieceType!);
    expect(
      result.containsKey(key),
      isFalse,
      reason: 'Duplicate faction mesh entry for $key.',
    );
    result[key] = glbPath;
  }

  if (rawSection is List) {
    for (final item in rawSection) {
      expect(item, isA<Map>());
      final map = Map<String, dynamic>.from(item as Map);
      final factionRaw = (map['faction'] ?? map['factionId'] ?? '').toString();
      final pieceRaw =
          (map['pieceType'] ?? map['type'] ?? map['piece_type'] ?? '')
              .toString();
      final glbPath = (map['glbPath'] ?? map['path'] ?? '').toString();
      addEntry(factionRaw, pieceRaw, glbPath);
    }
  } else if (rawSection is Map) {
    final map = Map<String, dynamic>.from(rawSection);
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is String) {
        // Flat map: "<faction>_<piece_type>" -> "<path>"
        final keyStr = entry.key;
        PieceType? matchedType;
        String? matchedFaction;
        for (final pt in PieceType.values) {
          final suffixSnake = '_${pt.snakeCaseName}';
          final suffixCamel = '_${pt.name}';
          if (keyStr.endsWith(suffixSnake)) {
            matchedType = pt;
            matchedFaction = keyStr.substring(
              0,
              keyStr.length - suffixSnake.length,
            );
            break;
          }
          if (keyStr.endsWith(suffixCamel)) {
            matchedType = pt;
            matchedFaction = keyStr.substring(
              0,
              keyStr.length - suffixCamel.length,
            );
            break;
          }
        }
        expect(
          matchedType,
          isNotNull,
          reason: 'Could not parse flat factionMeshes key "$keyStr".',
        );
        addEntry(matchedFaction!, matchedType!.snakeCaseName, value);
      } else if (value is Map) {
        final subMap = Map<String, dynamic>.from(value);
        if (subMap.containsKey('glbPath') &&
            (subMap.containsKey('faction') ||
                subMap.containsKey('pieceType') ||
                subMap.containsKey('type'))) {
          final factionRaw = (subMap['faction'] ?? '').toString();
          final pieceRaw =
              (subMap['pieceType'] ?? subMap['type'] ?? '').toString();
          final glbPath = (subMap['glbPath'] ?? '').toString();
          addEntry(factionRaw, pieceRaw, glbPath);
        } else {
          // Nested map: faction -> { pieceType -> path or {glbPath: ...} }
          for (final subEntry in subMap.entries) {
            final pVal = subEntry.value;
            final glbPath = pVal is String
                ? pVal
                : (pVal is Map ? (pVal['glbPath'] ?? '').toString() : '');
            addEntry(entry.key, subEntry.key, glbPath);
          }
        }
      }
    }
  } else {
    fail('Unsupported factionMeshes JSON type: ${rawSection.runtimeType}.');
  }

  return result;
}
