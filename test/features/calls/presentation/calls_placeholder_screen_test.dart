import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/features/calls/presentation/calls_placeholder_screen.dart';

void main() {
  testWidgets('shows a calls placeholder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: const Scaffold(body: CallsPlaceholderScreen()),
      ),
    );

    expect(find.byKey(CallsPlaceholderScreen.rootKey), findsOneWidget);
    expect(find.text('通话'), findsOneWidget);
    expect(find.text('通话还没接上'), findsOneWidget);
  });
}
