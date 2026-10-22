import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/gateway_settings.dart';

part 'settings_dto.dart';

final class SettingsApi {
  const SettingsApi(this._transport);
  final HttpTransport _transport;

  Future<UiLanguage> fetchPreferences({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.settingsPreferences,
      cancellation: cancellation,
    );
    return _parseLanguage(_shape.map(data)['language']);
  }

  Future<UiLanguage> savePreferences(
    UiLanguage language, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.settingsPreferences,
      body: <String, String>{
        'language': language == UiLanguage.en ? 'en' : 'zh',
      },
      cancellation: cancellation,
    );
    return _parseLanguage(_shape.map(data)['language']);
  }

  Future<SystemInfo> fetchSystemInfo({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.systemInfo,
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return SystemInfo(
      version: _optString(map['version'], 'OneWIFI'),
      buildTime: _shape.optionalString(map['build_time']),
      developer: map['developer'] == true,
    );
  }

  Future<GatewayUpdate> checkUpdate({RequestCancellation? cancellation}) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.systemUpdateCheck,
      timeout: const Duration(seconds: 20),
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return GatewayUpdate(
      available: _shape.boolean(map['available']),
      version: _shape.optionalString(map['version']),
      currentVersion: _shape.optionalString(map['current_version']),
      message: _shape.optionalString(map['message']),
      repository: _shape.optionalString(map['repository']),
    );
  }

  Future<GatewayUpdateApply> applyUpdate({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.systemUpdateApply,
      body: const <String, Object?>{},
      timeout: const Duration(minutes: 2),
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return GatewayUpdateApply(
      applied: _shape.boolean(map['applied']),
      version: _shape.optionalString(map['version']),
      message: _shape.optionalString(map['message']),
      reauthenticationRequired: map['reauthentication_required'] == true,
    );
  }

  Future<NotificationSettings> fetchNotifications({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.settingsNotifications,
      cancellation: cancellation,
    );
    return _parseNotifications(data);
  }

  Future<NotificationSettings> saveNotifications(
    NotificationSettings notifications, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.settingsNotifications,
      body: _encodeNotifications(notifications),
      cancellation: cancellation,
    );
    return _parseNotifications(data);
  }

  Future<void> testNotification(
    NotifyChannel channel,
    NotifyChannelSettings settings, {
    RequestCancellation? cancellation,
  }) async {
    if (!channel.canTest) {
      throw const SettingsDtoException();
    }
    await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.settingsNotificationsTest,
      pathParameters: <String, String>{'channel': channel.apiName},
      body: _encodeTestBody(channel, settings),
      timeout: const Duration(seconds: 30),
      cancellation: cancellation,
    );
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.settingsPassword,
      body: <String, String>{
        'old_password': oldPassword,
        'new_password': newPassword,
        'confirm_password': confirmPassword,
      },
      expireSessionOnUnauthorized: false,
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    if (map['changed'] != true) throw const SettingsDtoException();
  }

  Future<AccessPolicy> fetchSecurity({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.settingsSecurity,
      cancellation: cancellation,
    );
    return _parseSecurity(data);
  }

  Future<AccessPolicy> saveSecurity(
    AccessPolicy policy, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.settingsSecurity,
      body: <String, Object?>{
        'mode': policy.mode == AccessMode.public ? 'public' : 'internal',
        'allowed_cidrs': policy.allowedCidrs,
        'trust_proxy_headers': policy.trustProxyHeaders,
        'trusted_proxy_cidrs': policy.trustedProxyCidrs,
      },
      cancellation: cancellation,
    );
    return _parseSecurity(data);
  }

  Future<HttpsSettings> fetchHttps({RequestCancellation? cancellation}) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.settingsHttps,
      cancellation: cancellation,
    );
    return _parseHttps(data);
  }

  Future<HttpsSettings> saveHttps(
    bool enabled, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.settingsHttps,
      body: <String, Object?>{'enabled': enabled},
      cancellation: cancellation,
    );
    return _parseHttps(data);
  }

  Future<HttpsSettings> uploadCustomCertificate({
    required String certificate,
    required String privateKey,
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.settingsHttpsCustom,
      body: <String, String>{
        'certificate': certificate,
        'private_key': privateKey,
      },
      cancellation: cancellation,
    );
    return _parseHttps(data);
  }

  Future<HttpsSettings> deleteCustomCertificate({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'DELETE',
      routeTemplate: GatewayApi.settingsHttpsCustom,
      cancellation: cancellation,
    );
    return _parseHttps(data);
  }

  Future<HttpsSettings> reissueCertificate({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.settingsHttpsReissue,
      cancellation: cancellation,
    );
    return _parseHttps(data);
  }

  Future<DeveloperQuota> fetchDeveloper({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.settingsDeveloper,
      cancellation: cancellation,
    );
    return _parseQuota(data);
  }

  Future<DeveloperQuota> saveDeveloper({
    int? deviceLimit,
    int? smsHourlyLimit,
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.settingsDeveloper,
      body: <String, Object?>{
        'device_limit': ?deviceLimit,
        'sms_hourly_limit': ?smsHourlyLimit,
      },
      cancellation: cancellation,
    );
    return _parseQuota(data);
  }

  Future<SmsModemSettings> fetchSmsModemSettings({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.settingsSms,
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return SmsModemSettings(
      autoClearModemStorage: map['auto_clear_modem_storage'] != false,
    );
  }

  Future<SmsModemSettings> saveSmsModemSettings(
    bool autoClearModemStorage, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.settingsSms,
      body: <String, Object?>{
        'auto_clear_modem_storage': autoClearModemStorage,
      },
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return SmsModemSettings(
      autoClearModemStorage: map['auto_clear_modem_storage'] != false,
    );
  }

  Future<VowifiMtuSettings> fetchVowifiSettings({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.settingsVowifi,
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return VowifiMtuSettings(
      mtuCompatibility: map['mtu_compatibility'] == true,
    );
  }

  Future<VowifiMtuSettings> saveVowifiSettings(
    bool mtuCompatibility, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.settingsVowifi,
      body: <String, Object?>{'mtu_compatibility': mtuCompatibility},
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return VowifiMtuSettings(
      mtuCompatibility: map['mtu_compatibility'] == true,
    );
  }

  /// Router/gateway seat only. Mobile product seat stays in [ProductLicenseStore].
  Future<GatewayLicenseStatus> fetchGatewayLicense({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.license,
      cancellation: cancellation,
    );
    return _parseGatewayLicense(data);
  }

  /// WEB `POST /api/license` — gateway/router seat activation.
  Future<GatewayLicenseStatus> activateGatewayLicense(
    String code, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.license,
      body: <String, String>{'code': code},
      cancellation: cancellation,
    );
    return _parseGatewayLicense(data);
  }

  /// WEB `DELETE /api/license` — clear gateway/router seat on the box.
  Future<GatewayLicenseStatus> clearGatewayLicense({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'DELETE',
      routeTemplate: GatewayApi.license,
      cancellation: cancellation,
    );
    return _parseGatewayLicense(data);
  }

  GatewayLicenseStatus _parseGatewayLicense(Object? data) {
    final map = _shape.map(data);
    return GatewayLicenseStatus(
      activated: map['activated'] == true,
      code: _shape.optionalString(map['code']),
      edition: _shape.optionalString(map['edition']),
      clientKind: _shape.optionalString(map['client_kind']),
    );
  }
}
