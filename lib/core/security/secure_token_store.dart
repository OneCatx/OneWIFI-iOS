import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/base_url_policy.dart';

abstract interface class TokenStore {
  Future<String?> read(Uri origin);

  Future<void> write(Uri origin, String token);

  Future<void> clear(Uri origin);

  Future<void> clearAll();
}

final class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenKeyPrefix = 'bearer_token.';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(Uri origin) {
    return _storage.read(key: _keyFor(origin));
  }

  @override
  Future<void> write(Uri origin, String token) {
    return _storage.write(key: _keyFor(origin), value: token);
  }

  @override
  Future<void> clear(Uri origin) {
    return _storage.delete(key: _keyFor(origin));
  }

  @override
  Future<void> clearAll() async {
    final values = await _storage.readAll();
    for (final key
        in values.keys
            .where((key) => key.startsWith(_tokenKeyPrefix))
            .toList()) {
      await _storage.delete(key: key);
    }
  }

  static String _keyFor(Uri origin) {
    final normalized = BaseUrlPolicy.parseAndValidate(origin.toString());
    final encodedOrigin = base64Url
        .encode(utf8.encode(normalized.toString()))
        .replaceAll('=', '');
    return '$_tokenKeyPrefix$encodedOrigin';
  }
}

/// 进程内缓存，避免每个 HTTP 请求都打一遍安全存储。
final class CachedTokenStore implements TokenStore {
  CachedTokenStore(this._inner);

  final TokenStore _inner;
  final Map<String, String?> _cached = <String, String?>{};

  @override
  Future<String?> read(Uri origin) async {
    final key = _cacheKey(origin);
    if (_cached.containsKey(key)) return _cached[key];
    final value = await _inner.read(origin);
    _cached[key] = value;
    return value;
  }

  @override
  Future<void> write(Uri origin, String token) async {
    await _inner.write(origin, token);
    _cached[_cacheKey(origin)] = token;
  }

  @override
  Future<void> clear(Uri origin) async {
    await _inner.clear(origin);
    _cached[_cacheKey(origin)] = null;
  }

  @override
  Future<void> clearAll() async {
    await _inner.clearAll();
    _cached.clear();
  }

  static String _cacheKey(Uri origin) =>
      BaseUrlPolicy.parseAndValidate(origin.toString()).toString();
}
