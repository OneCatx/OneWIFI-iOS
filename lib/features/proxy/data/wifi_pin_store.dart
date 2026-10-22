import 'package:shared_preferences/shared_preferences.dart';

import '../domain/wifi_selector_catalog.dart';

/// 代理一级菜单上要摆哪些国家。默认香港 / 美国 / 英国 / 德国 / 新西兰。
final class WifiPinStore {
  WifiPinStore({this._preferences});

  static const String storageKey = 'proxy.pinnedCountries';

  final SharedPreferencesAsync? _preferences;

  Future<List<String>> read() async {
    try {
      final raw = await _store.getString(storageKey);
      final codes = _parse(raw);
      if (codes.isEmpty) {
        return List<String>.of(WifiSelectorCatalog.pinnedCountryOrder);
      }
      return codes;
    } catch (_) {
      return List<String>.of(WifiSelectorCatalog.pinnedCountryOrder);
    }
  }

  Future<void> write(List<String> codes) async {
    try {
      await _store.setString(storageKey, codes.join(','));
    } catch (_) {}
  }

  SharedPreferencesAsync get _store => _preferences ?? SharedPreferencesAsync();

  static List<String> _parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    final seen = <String>{};
    final codes = <String>[];
    for (final part in raw.split(',')) {
      final code = part.trim().toUpperCase();
      if (code.isEmpty || !seen.add(code == 'UK' ? 'GB' : code)) continue;
      codes.add(code == 'UK' ? 'GB' : code);
    }
    return codes;
  }
}
