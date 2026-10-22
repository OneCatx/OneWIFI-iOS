import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/app/appearance_controller.dart';

void main() {
  group('AppearanceController after dispose()', () {
    test('setMode to another mode returns normally and keeps the mode', () {
      final controller = AppearanceController();
      var notifications = 0;
      controller.addListener(() => notifications += 1);
      controller.dispose();

      expect(() => controller.setMode(ThemeMode.dark), returnsNormally);

      expect(controller.mode, ThemeMode.system);
      expect(notifications, 0);
    });

    test('setMode to the current mode returns normally', () {
      final controller = AppearanceController();
      var notifications = 0;
      controller.addListener(() => notifications += 1);
      controller.dispose();

      expect(() => controller.setMode(ThemeMode.system), returnsNormally);

      expect(controller.mode, ThemeMode.system);
      expect(notifications, 0);
    });
  });

  group('AppearanceController dispose() twice', () {
    test('second dispose() returns normally without a notification', () {
      final controller = AppearanceController();
      var notifications = 0;
      controller.addListener(() => notifications += 1);
      controller.dispose();

      expect(controller.dispose, returnsNormally);

      expect(notifications, 0);
    });
  });
}
