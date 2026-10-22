import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/design/one/dot_matrix_face.dart';
import 'package:onewifi_android/design/one/glass.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/tokens/one_tokens.dart';
import 'package:onewifi_android/design/widgets/one_status_hero.dart';

void main() {
  test('spacing and radius aliases mirror the Glass scale', () {
    expect(OneSpacing.nano, Glass.space2);
    expect(OneSpacing.tight, Glass.space6);
    expect(OneSpacing.hairline, Glass.strokeWidth);
    expect(OneSpacing.micro, Glass.space4);
    expect(OneSpacing.small, Glass.space8);
    expect(OneSpacing.item, Glass.space12);
    expect(OneSpacing.page, Glass.pageMargin);
    expect(OneRadii.control, Glass.radiusTile);
  });

  test('OneTheme.isDark follows the theme brightness', () {
    expect(OneTheme.isDark(OneTheme.dark()), isTrue);
    expect(OneTheme.isDark(OneTheme.light()), isFalse);
  });

  testWidgets('status hero renders the three stage labels by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: const Scaffold(
          body: OneStatusHero(
            tone: OneStatusTone.attention,
            title: 'Needs attention',
            message: 'Something to fix',
          ),
        ),
      ),
    );

    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('处理中'), findsOneWidget);
    expect(find.text('就绪'), findsOneWidget);
    expect(find.text('注意'), findsOneWidget);
    expect(
      tester.widget<DotMatrixFace>(find.byType(DotMatrixFace)).semanticLabel,
      '关闭',
    );
  });

  testWidgets('showStages false hides the stage row and labels the face '
      'with the pill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: const Scaffold(
          body: OneStatusHero(
            tone: OneStatusTone.attention,
            title: 'Needs attention',
            message: 'Something to fix',
            showStages: false,
          ),
        ),
      ),
    );

    expect(find.text('关闭'), findsNothing);
    expect(find.text('处理中'), findsNothing);
    expect(find.text('就绪'), findsNothing);
    expect(find.text('注意'), findsOneWidget);
    expect(
      tester.widget<DotMatrixFace>(find.byType(DotMatrixFace)).semanticLabel,
      '注意',
    );
  });

  testWidgets('detail is rendered while the status is not settled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: const Scaffold(
          body: OneStatusHero(
            tone: OneStatusTone.attention,
            title: 'Needs attention',
            message: 'Something to fix',
            detail: 'Pull to refresh',
            showStages: false,
          ),
        ),
      ),
    );

    expect(find.text('Something to fix'), findsOneWidget);
    expect(find.text('Pull to refresh'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: const Scaffold(
          body: OneStatusHero(
            tone: OneStatusTone.healthy,
            title: 'All good',
            message: 'Something to fix',
            detail: 'Pull to refresh',
            showStages: false,
          ),
        ),
      ),
    );

    expect(find.text('Something to fix'), findsNothing);
    expect(find.text('Pull to refresh'), findsNothing);
  });

  testWidgets('message may be null for a const settled hero', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: const Scaffold(
          body: OneStatusHero(
            tone: OneStatusTone.healthy,
            title: 'OneWIFI',
            message: null,
            showStages: false,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('OneWIFI'), findsOneWidget);
    expect(find.text('就绪'), findsOneWidget);
    expect(
      tester.widget<DotMatrixFace>(find.byType(DotMatrixFace)).mood,
      DotMatrixMood.smile,
    );
  });
}
