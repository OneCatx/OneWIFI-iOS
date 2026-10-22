import 'package:flutter/material.dart';

final class AppearanceController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  bool _disposed = false;

  ThemeMode get mode => _mode;

  void setMode(ThemeMode mode) {
    if (_disposed) return;
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
