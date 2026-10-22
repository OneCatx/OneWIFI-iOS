import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/design/one/dot_matrix_face.dart';
import 'package:onewifi_android/design/one/one_status_hero.dart';

void main() {
  testWidgets('dot-matrix face exposes the status as a semantic image', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DotMatrixFace(
            mood: DotMatrixMood.smile,
            color: Colors.white,
            semanticLabel: 'Ready',
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Ready'), findsOneWidget);
  });

  testWidgets('status hero smiles when ready and frowns while activating', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OneStatusHero(
            state: OneChannelState.ready,
            title: 'OneWIFI',
            pill: 'Ready',
            stageLabels: ['Off', 'Working', 'Ready'],
            subtitle: 'Ready',
            detail: 'Ready to use',
          ),
        ),
      ),
    );
    expect(find.byType(DotMatrixFace), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(
      tester.widget<DotMatrixFace>(find.byType(DotMatrixFace)).mood,
      DotMatrixMood.smile,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OneStatusHero(
            state: OneChannelState.activating,
            title: 'Loading overview',
            pill: 'Working',
            stageLabels: ['Off', 'Working', 'Ready'],
            subtitle: 'Working',
            detail: 'Please wait',
          ),
        ),
      ),
    );
    expect(
      tester.widget<DotMatrixFace>(find.byType(DotMatrixFace)).mood,
      DotMatrixMood.frown,
    );
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });
}
