import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/gateway_settings.dart';
import 'settings_api.dart';

abstract interface class SettingsRepository {
  Future<UiLanguage> fetchPreferences({RequestCancellation? cancellation});

  Future<UiLanguage> savePreferences(
    UiLanguage language, {
    RequestCancellation? cancellation,
  });

  Future<SystemInfo> fetchSystemInfo({RequestCancellation? cancellation});

  Future<GatewayUpdate> checkUpdate({RequestCancellation? cancellation});

  Future<GatewayUpdateApply> applyUpdate({RequestCancellation? cancellation});

  Future<NotificationSettings> fetchNotifications({
    RequestCancellation? cancellation,
  });

  Future<NotificationSettings> saveNotifications(
    NotificationSettings notifications, {
    RequestCancellation? cancellation,
  });

  Future<void> testNotification(
    NotifyChannel channel,
    NotifyChannelSettings settings, {
    RequestCancellation? cancellation,
  });

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    RequestCancellation? cancellation,
  });

  Future<AccessPolicy> fetchSecurity({RequestCancellation? cancellation});

  Future<AccessPolicy> saveSecurity(
    AccessPolicy policy, {
    RequestCancellation? cancellation,
  });

  Future<HttpsSettings?> fetchHttps({RequestCancellation? cancellation});

  Future<HttpsSettings> saveHttps(
    bool enabled, {
    RequestCancellation? cancellation,
  });

  Future<HttpsSettings> uploadCustomCertificate({
    required String certificate,
    required String privateKey,
    RequestCancellation? cancellation,
  });

  Future<HttpsSettings> deleteCustomCertificate({
    RequestCancellation? cancellation,
  });

  Future<HttpsSettings> reissueCertificate({
    RequestCancellation? cancellation,
  });

  Future<DeveloperQuota?> fetchDeveloper({RequestCancellation? cancellation});

  Future<SmsModemSettings> fetchSmsModemSettings({
    RequestCancellation? cancellation,
  });

  Future<SmsModemSettings> saveSmsModemSettings(
    bool autoClearModemStorage, {
    RequestCancellation? cancellation,
  });

  Future<VowifiMtuSettings> fetchVowifiSettings({
    RequestCancellation? cancellation,
  });

  Future<VowifiMtuSettings> saveVowifiSettings(
    bool mtuCompatibility, {
    RequestCancellation? cancellation,
  });

  Future<GatewayLicenseStatus?> fetchGatewayLicense({
    RequestCancellation? cancellation,
  });

  Future<DeveloperQuota> saveDeveloper({
    int? deviceLimit,
    int? smsHourlyLimit,
    RequestCancellation? cancellation,
  });
}

final class DefaultSettingsRepository implements SettingsRepository {
  const DefaultSettingsRepository(this._api);
  final SettingsApi _api;

  @override
  Future<UiLanguage> fetchPreferences({RequestCancellation? cancellation}) {
    return guardShape(
      'local-settings-response',
      () => _api.fetchPreferences(cancellation: cancellation),
    );
  }

  @override
  Future<UiLanguage> savePreferences(
    UiLanguage language, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.savePreferences(language, cancellation: cancellation),
    );
  }

  @override
  Future<SystemInfo> fetchSystemInfo({RequestCancellation? cancellation}) {
    return guardShape(
      'local-settings-response',
      () => _api.fetchSystemInfo(cancellation: cancellation),
    );
  }

  @override
  Future<GatewayUpdate> checkUpdate({RequestCancellation? cancellation}) {
    return guardShape(
      'local-settings-response',
      () => _api.checkUpdate(cancellation: cancellation),
    );
  }

  @override
  Future<GatewayUpdateApply> applyUpdate({RequestCancellation? cancellation}) {
    return guardShape(
      'local-settings-response',
      () => _api.applyUpdate(cancellation: cancellation),
    );
  }

  @override
  Future<NotificationSettings> fetchNotifications({
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.fetchNotifications(cancellation: cancellation),
    );
  }

  @override
  Future<NotificationSettings> saveNotifications(
    NotificationSettings notifications, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.saveNotifications(notifications, cancellation: cancellation),
    );
  }

  @override
  Future<void> testNotification(
    NotifyChannel channel,
    NotifyChannelSettings settings, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () =>
          _api.testNotification(channel, settings, cancellation: cancellation),
    );
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<AccessPolicy> fetchSecurity({RequestCancellation? cancellation}) {
    return guardShape(
      'local-settings-response',
      () => _api.fetchSecurity(cancellation: cancellation),
    );
  }

  @override
  Future<AccessPolicy> saveSecurity(
    AccessPolicy policy, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.saveSecurity(policy, cancellation: cancellation),
    );
  }

  @override
  Future<HttpsSettings?> fetchHttps({RequestCancellation? cancellation}) {
    return _optionalDeveloper(
      () => _api.fetchHttps(cancellation: cancellation),
    );
  }

  @override
  Future<HttpsSettings> saveHttps(
    bool enabled, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.saveHttps(enabled, cancellation: cancellation),
    );
  }

  @override
  Future<HttpsSettings> uploadCustomCertificate({
    required String certificate,
    required String privateKey,
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.uploadCustomCertificate(
        certificate: certificate,
        privateKey: privateKey,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<HttpsSettings> deleteCustomCertificate({
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.deleteCustomCertificate(cancellation: cancellation),
    );
  }

  @override
  Future<HttpsSettings> reissueCertificate({
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.reissueCertificate(cancellation: cancellation),
    );
  }

  @override
  Future<DeveloperQuota?> fetchDeveloper({RequestCancellation? cancellation}) {
    return _optionalDeveloper(
      () => _api.fetchDeveloper(cancellation: cancellation),
    );
  }

  @override
  Future<DeveloperQuota> saveDeveloper({
    int? deviceLimit,
    int? smsHourlyLimit,
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.saveDeveloper(
        deviceLimit: deviceLimit,
        smsHourlyLimit: smsHourlyLimit,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<SmsModemSettings> fetchSmsModemSettings({
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.fetchSmsModemSettings(cancellation: cancellation),
    );
  }

  @override
  Future<SmsModemSettings> saveSmsModemSettings(
    bool autoClearModemStorage, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.saveSmsModemSettings(
        autoClearModemStorage,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<VowifiMtuSettings> fetchVowifiSettings({
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.fetchVowifiSettings(cancellation: cancellation),
    );
  }

  @override
  Future<VowifiMtuSettings> saveVowifiSettings(
    bool mtuCompatibility, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () =>
          _api.saveVowifiSettings(mtuCompatibility, cancellation: cancellation),
    );
  }

  @override
  Future<GatewayLicenseStatus?> fetchGatewayLicense({
    RequestCancellation? cancellation,
  }) {
    return _optionalDeveloper(
      () => _api.fetchGatewayLicense(cancellation: cancellation),
    );
  }

  Future<T?> _optionalDeveloper<T>(Future<T> Function() body) async {
    try {
      return await guardShape('local-settings-response', body);
    } on ApiFailure catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }
}
