import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void expectCenteredPopup(WidgetTester tester, Finder finder) {
  expect(find.byType(BottomSheet), findsNothing);
  final rect = tester.getRect(finder);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.center.dx, closeTo(screen.width / 2, 20));
  expect(rect.center.dy, closeTo(screen.height / 2, 48));
}
