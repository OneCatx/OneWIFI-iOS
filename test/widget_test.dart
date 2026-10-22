import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app package smoke mounts a MaterialApp shell', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('OneWIFI'))),
      ),
    );

    expect(find.text('OneWIFI'), findsOneWidget);
  });
}
