import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/remote_otp_pairing.dart';

abstract interface class RemoteOtpPairingStore {
  Future<RemoteOtpEndpoint?> read();
  Future<void> write(RemoteOtpEndpoint endpoint);
  Future<void> clear();
  Future<int> readLastEventId();
  Future<void> writeLastEventId(int eventId);
  Future<int> readLastAcknowledgedPushId();
  Future<void> writeLastAcknowledgedPushId(int smsId);
}

final class SecureRemoteOtpPairingStore implements RemoteOtpPairingStore {
  factory SecureRemoteOtpPairingStore({
    FlutterSecureStorage? secureStorage,
    SharedPreferencesAsync? preferences,
  }) => SecureRemoteOtpPairingStore._(
    secureStorage ?? const FlutterSecureStorage(),
    preferences,
  );

  SecureRemoteOtpPairingStore._(this._secureStorage, this._preferences);

  static const String _baseUrlKey = 'remote_otp.base_url';
  static const String _tokenKey = 'remote_otp.token';
  static const String _lastEventIdKey = 'remote_otp.last_event_id';
  static const String _lastAcknowledgedPushIdKey =
      'remote_otp.last_acknowledged_push_id';

  final FlutterSecureStorage _secureStorage;
  SharedPreferencesAsync? _preferences;

  /// 平台实例只在真正读写时才解析：装配依赖（以及测试）不该被迫先注册
  /// SharedPreferences 的平台实现。
  SharedPreferencesAsync get _platform =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<RemoteOtpEndpoint?> read() async {
    final baseUrl = await _platform.getString(_baseUrlKey);
    final token = await _secureStorage.read(key: _tokenKey);
    if (baseUrl == null || token == null || token.trim().isEmpty) return null;
    try {
      return RemoteOtpEndpoint(
        baseUrl: RemoteOtpPairing.normalizeBaseUrl(baseUrl),
        token: token.trim(),
      );
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(RemoteOtpEndpoint endpoint) async {
    await _secureStorage.write(key: _tokenKey, value: endpoint.token);
    await _platform.setString(_baseUrlKey, endpoint.baseUrl.toString());
    await _platform.remove(_lastEventIdKey);
    await _platform.remove(_lastAcknowledgedPushIdKey);
  }

  @override
  Future<void> clear() async {
    await _secureStorage.delete(key: _tokenKey);
    await _platform.remove(_baseUrlKey);
    await _platform.remove(_lastEventIdKey);
    await _platform.remove(_lastAcknowledgedPushIdKey);
  }

  @override
  Future<int> readLastEventId() async =>
      (await _platform.getInt(_lastEventIdKey) ?? 0).clamp(0, 1 << 53);

  @override
  Future<void> writeLastEventId(int eventId) async {
    if (eventId <= 0) return;
    final current = await readLastEventId();
    if (eventId > current) await _platform.setInt(_lastEventIdKey, eventId);
  }

  @override
  Future<int> readLastAcknowledgedPushId() async =>
      (await _platform.getInt(_lastAcknowledgedPushIdKey) ?? 0).clamp(
        0,
        1 << 53,
      );

  @override
  Future<void> writeLastAcknowledgedPushId(int smsId) async {
    if (smsId <= 0) return;
    final current = await readLastAcknowledgedPushId();
    if (smsId > current) {
      await _platform.setInt(_lastAcknowledgedPushIdKey, smsId);
    }
  }
}