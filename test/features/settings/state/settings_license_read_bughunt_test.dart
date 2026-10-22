import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/features/settings/data/activation_channel.dart';
import 'package:onewifi_android/features/settings/data/product_license_store.dart';
import 'package:onewifi_android/features/settings/data/settings_repository.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';
import 'package:onewifi_android/features/settings/state/settings_controller.dart';

void main() {
  test('second load keeps last-good license when native read fails', () async {
    final license = _FlakyLicenseStore(
      ProductLicense(
        key: 'AB12-CD34-EF56-GH78',
        activated: true,
        membershipBadge: 'Ultra',
      ),
    );
    final controller = SettingsController(
      repository: _Repo(),
      licenseStore: license,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.data.license.isActive, isTrue);
    expect(controller.noticeError, isFalse);

    license.failNext = true;
    await controller.load();

    expect(controller.data.license.isActive, isTrue);
    expect(controller.data.license.key, 'AB12-CD34-EF56-GH78');
    expect(controller.noticeError, isTrue);
    expect(controller.notice, isNotEmpty);
  });
}

final class _FlakyLicenseStore implements ProductLicenseStore {
  _FlakyLicenseStore(this._license);

  ProductLicense _license;
  bool failNext = false;

  @override
  Future<ProductLicense> read() async {
    if (failNext) {
      throw LicenseReadException('无法读取激活库');
    }
    return _license;
  }

  @override
  Future<void> write(ProductLicense license) async {
    _license = license;
  }

  @override
  Future<ProductLicense> activate(String key) async {
    _license = ProductLicense(key: key.trim(), activated: true);
    return _license;
  }

  @override
  Future<ProductLicense> deactivate() async {
    _license = const ProductLicense();
    return _license;
  }
}

final class _Repo implements SettingsRepository {
  @override
  Future<VowifiMtuSettings> fetchVowifiSettings({
    RequestCancellation? cancellation,
  }) async => const VowifiMtuSettings();

  @override
  Future<VowifiMtuSettings> saveVowifiSettings(
    bool mtuCompatibility, {
    RequestCancellation? cancellation,
  }) async => VowifiMtuSettings(mtuCompatibility: mtuCompatibility);

  @override
  Future<SmsModemSettings> fetchSmsModemSettings({
    RequestCancellation? cancellation,
  }) async => const SmsModemSettings();

  @override
  Future<SmsModemSettings> saveSmsModemSettings(
    bool autoClearModemStorage, {
    RequestCancellation? cancellation,
  }) async => SmsModemSettings(autoClearModemStorage: autoClearModemStorage);

  @override
  Future<GatewayLicenseStatus?> fetchGatewayLicense({
    RequestCancellation? cancellation,
  }) async => null;

  @override
  Future<UiLanguage> fetchPreferences({
    RequestCancellation? cancellation,
  }) async => UiLanguage.zh;

  @override
  Future<UiLanguage> savePreferences(
    UiLanguage language, {
    RequestCancellation? cancellation,
  }) async => language;

  @override
  Future<SystemInfo> fetchSystemInfo({
    RequestCancellation? cancellation,
  }) async => const SystemInfo();

  @override
  Future<GatewayUpdate> checkUpdate({
    RequestCancellation? cancellation,
  }) async => const GatewayUpdate(available: false);

  @override
  Future<GatewayUpdateApply> applyUpdate({
    RequestCancellation? cancellation,
  }) async => const GatewayUpdateApply(applied: false);

  @override
  Future<NotificationSettings> fetchNotifications({
    RequestCancellation? cancellation,
  }) async => const NotificationSettings();

  @override
  Future<NotificationSettings> saveNotifications(
    NotificationSettings notifications, {
    RequestCancellation? cancellation,
  }) async => notifications;

  @override
  Future<void> testNotification(
    NotifyChannel channel,
    NotifyChannelSettings settings, {
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<AccessPolicy> fetchSecurity({
    RequestCancellation? cancellation,
  }) async => const AccessPolicy();

  @override
  Future<AccessPolicy> saveSecurity(
    AccessPolicy policy, {
    RequestCancellation? cancellation,
  }) async => policy;

  @override
  Future<HttpsSettings?> fetchHttps({
    RequestCancellation? cancellation,
  }) async => null;

  @override
  Future<HttpsSettings> saveHttps(
    bool enabled, {
    RequestCancellation? cancellation,
  }) async => HttpsSettings(enabled: enabled);

  @override
  Future<HttpsSettings> uploadCustomCertificate({
    required String certificate,
    required String privateKey,
    RequestCancellation? cancellation,
  }) async => const HttpsSettings(enabled: false);

  @override
  Future<HttpsSettings> deleteCustomCertificate({
    RequestCancellation? cancellation,
  }) async => const HttpsSettings(enabled: false);

  @override
  Future<HttpsSettings> reissueCertificate({
    RequestCancellation? cancellation,
  }) async => const HttpsSettings(enabled: false);

  @override
  Future<DeveloperQuota?> fetchDeveloper({
    RequestCancellation? cancellation,
  }) async => null;

  @override
  Future<DeveloperQuota> saveDeveloper({
    int? deviceLimit,
    int? smsHourlyLimit,
    RequestCancellation? cancellation,
  }) async => const DeveloperQuota(
    deviceLimit: 4,
    maxDeviceLimit: 10,
    smsHourlyLimit: 20,
    maxSmsHourlyLimit: 20,
  );
}
