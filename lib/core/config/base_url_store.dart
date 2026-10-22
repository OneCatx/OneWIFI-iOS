import 'package:shared_preferences/shared_preferences.dart';

import 'base_url_policy.dart';

abstract interface class BaseUrlStore {
  Future<Uri> read();

  Future<void> write(Uri origin);
}

final class SharedPreferencesBaseUrlStore implements BaseUrlStore {
  SharedPreferencesBaseUrlStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _originKey = 'service_origin';

  final SharedPreferencesAsync _preferences;

  @override
  Future<Uri> read() async {
    final stored = await _preferences.getString(_originKey);
    if (stored == null) {
      return BaseUrlPolicy.defaultOrigin;
    }
    return BaseUrlPolicy.parseAndValidate(stored);
  }

  @override
  Future<void> write(Uri origin) async {
    final normalized = BaseUrlPolicy.parseAndValidate(origin.toString());
    await _preferences.setString(_originKey, normalized.toString());
  }
}

/// 进程内缓存，避免每个 HTTP 请求都打一遍 SharedPreferences。
final class CachedBaseUrlStore implements BaseUrlStore {
  CachedBaseUrlStore(this._inner);

  final BaseUrlStore _inner;
  Uri? _cached;

  @override
  Future<Uri> read() async => _cached ??= await _inner.read();

  @override
  Future<void> write(Uri origin) async {
    final normalized = BaseUrlPolicy.parseAndValidate(origin.toString());
    await _inner.write(normalized);
    _cached = normalized;
  }
}
