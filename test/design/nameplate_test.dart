import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/nameplate.dart';
import 'package:onewifi_android/design/widgets/ow_accent.dart';

void main() {
  testWidgets('lifted nameplate uses an opaque fill and a drop shadow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.dark(),
        home: const Scaffold(
          body: Nameplate(label: '80ms', tone: PlateTone.green, lifted: true),
        ),
      ),
    );

    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(Nameplate),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, isNotNull);
    expect(decoration.color!.a, greaterThan(0.80));
    expect(decoration.boxShadow, isNotEmpty);
    expect(find.text('80ms'), findsOneWidget);
  });
}
