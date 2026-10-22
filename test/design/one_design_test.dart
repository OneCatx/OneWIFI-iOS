import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/design/one/dot_matrix_face.dart';
import 'package:onewifi_android/design/one/glass.dart' as one;
import 'package:onewifi_android/design/one/liquid_glass.dart';
import 'package:onewifi_android/design/one/one_palette.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/tokens/one_tokens.dart';
import 'package:onewifi_android/design/widgets/glass_backdrop.dart';
import 'package:onewifi_android/design/widgets/glass_dialog.dart';
import 'package:onewifi_android/design/widgets/glass_dock.dart';
import 'package:onewifi_android/design/widgets/glass_panel.dart';
import 'package:onewifi_android/design/widgets/one_status_hero.dart';
import '../support/centered_popup.dart';

void main() {
  test('One themes use Ultra black-white schemes and Montserrat', () {
    final light = OneTheme.light();
    final dark = OneTheme.dark();

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.primary, oneInk);
    expect(dark.colorScheme.primary, Colors.white);
    expect(light.colorScheme.surface, const Color(0xFFF9F9FF));
    expect(dark.colorScheme.surface, const Color(0xFF111318));
    expect(light.scaffoldBackgroundColor, Colors.transparent);
    expect(dark.scaffoldBackgroundColor, Colors.transparent);
    expect(light.textTheme.bodyMedium?.fontFamily, 'Montserrat');
    expect(dark.textTheme.bodyMedium?.fontFamily, 'Montserrat');
    expect(OneSpacing.page, greaterThan(OneSpacing.item));
    expect(OneRadii.panel, greaterThan(OneRadii.control));
  });

  test('Dock tokens stay compact while preserving the inner glass inset', () {
    expect(one.Glass.dockHeight, 56);
    expect(one.Glass.dockIndicatorHeight, 48);
    expect(
      one.Glass.dockHeight - one.Glass.dockTabInset * 2,
      greaterThanOrEqualTo(one.Glass.dockIndicatorHeight),
    );
  });

  test('One themes expose transparent Android system bars', () {
    final light = OneTheme.systemOverlayStyle(Brightness.light);
    final dark = OneTheme.systemOverlayStyle(Brightness.dark);

    expect(light.statusBarColor, Colors.transparent);
    expect(light.systemNavigationBarColor, Colors.transparent);
    expect(light.statusBarIconBrightness, Brightness.dark);
    expect(light.systemNavigationBarIconBrightness, Brightness.dark);
    expect(dark.statusBarColor, Colors.transparent);
    expect(dark.systemNavigationBarColor, Colors.transparent);
    expect(dark.statusBarIconBrightness, Brightness.light);
    expect(dark.systemNavigationBarIconBrightness, Brightness.light);
  });

  test('declared light and dark glass compositions meet WCAG contrast', () {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final scheme = brightness == Brightness.light
          ? oneBlackWhiteLight
          : oneBlackWhiteDark;
      final background = scheme.surface;
      final ink = scheme.onSurface;
      final muted = scheme.onSurfaceVariant;
      final onPrimary = scheme.onPrimary;
      final surface = _composite(OneColors.glass(brightness), background);
      final focus = OneColors.focus(brightness);

      expect(_contrast(ink, surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(muted, surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(ink, background), greaterThanOrEqualTo(4.5));
      expect(_contrast(onPrimary, ink), greaterThanOrEqualTo(4.5));
      expect(_contrast(focus, surface), greaterThanOrEqualTo(3));
    }
  });

  testWidgets('focus treatment is token-backed in both themes', (tester) async {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final fieldFocus = FocusNode();
      final buttonFocus = FocusNode();
      addTearDown(fieldFocus.dispose);
      addTearDown(buttonFocus.dispose);
      final theme = brightness == Brightness.light
          ? OneTheme.light()
          : OneTheme.dark();
      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          darkTheme: OneTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: Theme(
            data: theme,
            child: Scaffold(
              body: Column(
                children: <Widget>[
                  TextFormField(focusNode: fieldFocus),
                  FilledButton(
                    focusNode: buttonFocus,
                    onPressed: () {},
                    child: const Text('Continue'),
                  ),
                  GlassDock(
                    destinations: _dockDestinations,
                    selectedIndex: 0,
                    onDestinationSelected: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      fieldFocus.requestFocus();
      await tester.pump();
      expect(fieldFocus.hasFocus, isTrue);
      buttonFocus.requestFocus();
      await tester.pump();
      expect(buttonFocus.hasFocus, isTrue);

      final expected = OneColors.focus(brightness);
      final inputBorder =
          theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
      expect(inputBorder.borderSide.color, expected);
      expect(inputBorder.borderSide.width, OneFocus.width);
      expect(
        theme.filledButtonTheme.style!.side!.resolve(<WidgetState>{
          WidgetState.focused,
        }),
        BorderSide(color: expected, width: OneFocus.width),
      );
    }
  });

  testWidgets('status progress honors reduced motion with the same label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final disabled in <bool>[false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disabled),
            child: const Scaffold(
              body: OneStatusProgress(
                label: 'Refreshing overview',
                kind: OneProgressKind.linear,
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Refreshing overview'), findsOneWidget);
      expect(
        find.byType(LinearProgressIndicator),
        disabled ? findsNothing : findsOneWidget,
      );
      expect(
        find.byIcon(Icons.more_horiz),
        disabled ? findsOneWidget : findsNothing,
      );
    }
    semantics.dispose();
  });

  testWidgets('backdrop and panel expose useful semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: const GlassBackdrop(
          child: Center(
            child: GlassPanel(
              semanticLabel: 'Host health summary',
              child: Text('Host online'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(GlassBackdrop), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Host health summary')),
      findsOneWidget,
    );
    expect(find.text('Host online'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);
    semantics.dispose();
  });

  testWidgets('status hero and dock use Ultra chrome', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.dark(),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const OneStatusHero(
                tone: OneStatusTone.healthy,
                title: 'OneWIFI is ready',
                message: 'Host online · 1 device healthy',
              ),
              const Spacer(),
              GlassDock(
                destinations: _dockDestinations,
                selectedIndex: 0,
                onDestinationSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('OneWIFI is ready'), findsOneWidget);
    expect(find.text('就绪'), findsWidgets);
    expect(find.byType(DotMatrixFace), findsOneWidget);
    expect(
      tester.widget<DotMatrixFace>(find.byType(DotMatrixFace)).mood,
      DotMatrixMood.smile,
    );
    expect(find.text('Overview'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(LiquidGlass), findsNothing);
    final backdrop = tester.widget<BackdropFilter>(
      find.descendant(
        of: find.byType(GlassDock),
        matching: find.byType(BackdropFilter),
      ),
    );
    final desc = backdrop.filter.toString();
    expect(desc, contains('blur(12.0, 12.0'));
    expect(desc, isNot(contains('matrix')));
    expect(desc, isNot(contains('compose')));
    final fillDecoration =
        tester
                .widgetList<DecoratedBox>(
                  find.descendant(
                    of: find.byWidget(backdrop),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .first
                .decoration
            as BoxDecoration;
    expect(
      fillDecoration.color,
      one.Glass.liquidDockFill(OneTheme.dark().colorScheme, true),
    );
    expect(fillDecoration.gradient, isNull);
    expect(find.byKey(kGlassDockRimKey), findsOneWidget);
    expect(find.byKey(kGlassDockIndicatorKey), findsOneWidget);
    expect(tester.getSize(find.byKey(GlassDock.overviewTargetKey)).height, 20);
    expect(
      tester.getSize(find.byType(NavigationBar)).height,
      one.Glass.dockHeight,
    );
    semantics.dispose();
  });

  testWidgets('typed dock exposes Overview and Devices selection', (
    tester,
  ) async {
    final selected = <int>[];
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;

    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          darkTheme: OneTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: GlassDock(
                destinations: _dockDestinations,
                selectedIndex: 0,
                onDestinationSelected: selected.add,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
      await tester.tap(find.byKey(GlassDock.targetKey(1)));
      await tester.pump();
      expect(selected.last, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    }
  });

  testWidgets('glass confirmation actions meet the minimum target', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showOneGlassDialog(
              context: context,
              title: 'Sign out?',
              message: 'Your local session will be cleared.',
              confirmLabel: 'Sign out',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(OneGlassDialog.cancelTargetKey)).height,
      greaterThanOrEqualTo(OneSizes.minimumTarget),
    );
    expect(
      tester.getSize(find.byKey(OneGlassDialog.confirmTargetKey)).height,
      greaterThanOrEqualTo(OneSizes.minimumTarget),
    );
  });

  testWidgets('secondary popup sits in the center of the screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showOneGlassPopup<void>(
              context: context,
              builder: (context) =>
                  const SizedBox(key: Key('popup-body'), child: Text('menu')),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('menu'), findsOneWidget);
    expectCenteredPopup(tester, find.byKey(const Key('popup-body')));
  });

  test('secondary menus call showOneGlassPopup instead of bottom sheets', () {
    const files = <String>[
      'lib/features/proxy/presentation/wifi_connection_sheet.dart',
      'lib/features/proxy/presentation/wifi_country_sheet.dart',
      'lib/features/proxy/presentation/wifi_node_sheet.dart',
      'lib/features/esim/presentation/esim_edit_sheet.dart',
      'lib/features/settings/presentation/settings_notify_sheet.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, contains('showOneGlassPopup'), reason: path);
      expect(source, isNot(contains('showModalBottomSheet')), reason: path);
    }
  });

  testWidgets(
    'dock target supplies a semantic tap action that selects its index',
    (tester) async {
      final selected = <int>[];
      final semanticsHandle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          home: Scaffold(
            body: GlassDock(
              destinations: _dockDestinations,
              selectedIndex: 0,
              onDestinationSelected: selected.add,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Devices'));
      await tester.pump();
      expect(selected, <int>[1]);
      semanticsHandle.dispose();
    },
  );

  test('dock tab edges lead on the destination side', () {
    final rest = glassDockTabEdges(from: 0, to: 0, t: 0, count: 5);
    expect(rest.left, 0);
    expect(rest.right, 1);
    final mid = glassDockTabEdges(from: 0, to: 1, t: 0.5, count: 5);
    expect(mid.right - mid.left, greaterThan(1));
  });

  test('design and app sources have no OneIms runtime dependency', () {
    final roots = <Directory>[
      Directory('lib/design'),
      Directory('lib/app'),
      Directory('lib/features/overview/presentation'),
      Directory('lib/features/auth/presentation'),
    ];
    final files = roots
        .where((directory) => directory.existsSync())
        .expand(
          (directory) => directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')),
        )
        .toList();
    final source = files.map((file) => file.readAsStringSync()).join('\n');

    expect(source.contains('package:oneims_flutter'), isFalse);
    // The self-owned iOS switch adapter is the only design-layer native bridge.
    final outsideAdapter = files
        .where(
          (file) => !file.path
              .replaceAll('\\', '/')
              .endsWith('lib/design/widgets/system_controls.dart'),
        )
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(outsideAdapter.contains('MethodChannel'), isFalse);
    final nativeChannels = RegExp(
      r'''MethodChannel\(\s*['"]([^'"]+)''',
    ).allMatches(source).map((match) => match.group(1)).toList();
    expect(nativeChannels, [r'com.oneims.onewifi/system_switch/$id']);
    expect(source.contains('EventChannel'), isFalse);
    for (final disallowed in <String>['Shizuku', 'activation', 'membership']) {
      expect(source.contains(disallowed), isFalse);
    }
  });
}

const _dockDestinations = <OneDockDestination>[
  OneDockDestination(icon: Icons.dashboard_outlined, label: 'Overview'),
  OneDockDestination(icon: Icons.devices_other_outlined, label: 'Devices'),
];

Color _composite(Color foreground, Color background) {
  final alpha = foreground.a;
  return Color.from(
    alpha: 1,
    red: foreground.r * alpha + background.r * (1 - alpha),
    green: foreground.g * alpha + background.g * (1 - alpha),
    blue: foreground.b * alpha + background.b * (1 - alpha),
  );
}

double _contrast(Color first, Color second) {
  final firstLuminance = _luminance(first);
  final secondLuminance = _luminance(second);
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) {
  double linear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : pow((channel + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}
