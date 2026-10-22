import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/design/widgets/one_mark.dart';

void main() {
  testWidgets('OneMark paints without error and keeps square layout',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: OneMark(size: 52))),
      ),
    );
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(OneMark));
    expect(size.width, 52);
    expect(size.height, 52);
  });
}
