import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/settings/data/product_license_store.dart';
import 'package:onewifi_android/features/settings/data/settings_repository.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';
import 'package:onewifi_android/features/settings/state/settings_controller.dart';

void main() {
  test('launcher background uses the family charcoal', () {
    final xml = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();
    expect(xml, contains('#1C1C1E'));
    final fg = File(
      'android/app/src/main/res/drawable/ic_launcher_fg.xml',
    ).readAsStringSync();
    expect(fg, contains('#FFFFFFFF'));
    expect(fg, isNot(contains('#9B58DC')));
  });

  test('createProductLicenseStore does not throw without a prefs plugin', () {
    expect(createProductLicenseStore, returnsNormally);
  });

  test(
    'load assembles snapshot and language save stays on the gateway',
    () async {
      final repository = _Repo();
      final controller = SettingsController(
        repository: repository,
        licenseStore: MemoryProductLicenseStore(),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.snapshot.status, QueryStatus.data);
      expect(controller.data.info.version, 'v9');
      expect(controller.data.language, UiLanguage.zh);
      expect(controller.data.https, isNotNull);

      await controller.setLanguage(UiLanguage.en);
      expect(repository.savedLanguage, UiLanguage.en);
      expect(controller.data.language, UiLanguage.en);
      expect(controller.notice, 'Language saved');
    },
  );

  test('password shorter than 10 never hits the API', () async {
    final repository = _Repo();
    final controller = SettingsController(
      repository: repository,
      licenseStore: MemoryProductLicenseStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.changePassword(
      currentPassword: 'old',
      newPassword: 'short',
      confirmPassword: 'short',
    );
    expect(repository.passwordCalls, 0);
    expect(controller.notice, contains('10'));
    expect(controller.passwordChanged, isFalse);
  });

  test(
    'pushplus test stays local; telegram test hits the repository',
    () async {
      final repository = _Repo();
      final controller = SettingsController(
        repository: repository,
        licenseStore: MemoryProductLicenseStore(),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.testChannel(NotifyChannel.pushplus);
      expect(repository.testCalls, isEmpty);
      await controller.testChannel(NotifyChannel.telegram);
      expect(repository.testCalls, <NotifyChannel>[NotifyChannel.telegram]);
      expect(controller.testAction.status, ActionStatus.succeeded);
    },
  );

  test(
    'activateLicense writes the local store without a gateway round-trip',
    () async {
      final license = MemoryProductLicenseStore();
      final controller = SettingsController(
        repository: _Repo(),
        licenseStore: license,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);
      await controller.activateLicense('  KEY-1  ');
      expect((await license.read()).isActive, isTrue);
      expect(controller.data.license.key, 'KEY-1');
    },
  );

  test('mismatched passwords never hit the API', () async {
    final repository = _Repo();
    final controller = SettingsController(
      repository: repository,
      licenseStore: MemoryProductLicenseStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.changePassword(
      currentPassword: 'old-password',
      newPassword: 'new-password-1',
      confirmPassword: 'new-password-2',
    );
    expect(repository.passwordCalls, 0);
    expect(controller.notice, '两次密码不一致');
    expect(controller.passwordChanged, isFalse);
  });

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

  UiLanguage? savedLanguage;
  int passwordCalls = 0;
  final List<NotifyChannel> testCalls = <NotifyChannel>[];
  GatewayUpdateApply applyResult = const GatewayUpdateApply(applied: false);
  GatewayUpdate update = const GatewayUpdate(
    available: false,
    message: '当前已是最新',
  );

  @override
  Future<GatewayUpdateApply> applyUpdate({
    RequestCancellation? cancellation,
  }) async => applyResult;
  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    RequestCancellation? cancellation,
  }) async {
    passwordCalls += 1;
  }

  @override
  Future<GatewayUpdate> checkUpdate({RequestCancellation? cancellation}) async {
    return update;
  }

  @override
  Future<DeveloperQuota?> fetchDeveloper({
    RequestCancellation? cancellation,
  }) async {
    return const DeveloperQuota(
      deviceLimit: 4,
      maxDeviceLimit: 10,
      smsHourlyLimit: 20,
      maxSmsHourlyLimit: 20,
    );
  }

  @override
  Future<HttpsSettings?> fetchHttps({RequestCancellation? cancellation}) async {
    return const HttpsSettings(enabled: false, httpUrl: 'http://gw');
  }

  @override
  Future<NotificationSettings> fetchNotifications({
    RequestCancellation? cancellation,
  }) async => const NotificationSettings();

  @override
  Future<UiLanguage> fetchPreferences({
    RequestCancellation? cancellation,
  }) async => UiLanguage.zh;

  @override
  Future<AccessPolicy> fetchSecurity({
    RequestCancellation? cancellation,
  }) async => const AccessPolicy();

  @override
  Future<SystemInfo> fetchSystemInfo({
    RequestCancellation? cancellation,
  }) async => const SystemInfo(version: 'v9', developer: true);

  @override
  Future<DeveloperQuota> saveDeveloper({
    int? deviceLimit,
    int? smsHourlyLimit,
    RequestCancellation? cancellation,
  }) async {
    return DeveloperQuota(
      deviceLimit: deviceLimit ?? 4,
      maxDeviceLimit: 10,
      smsHourlyLimit: smsHourlyLimit ?? 20,
      maxSmsHourlyLimit: 20,
    );
  }

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
  Future<NotificationSettings> saveNotifications(
    NotificationSettings notifications, {
    RequestCancellation? cancellation,
  }) async => notifications;

  @override
  Future<UiLanguage> savePreferences(
    UiLanguage language, {
    RequestCancellation? cancellation,
  }) async {
    savedLanguage = language;
    return language;
  }

  @override
  Future<AccessPolicy> saveSecurity(
    AccessPolicy policy, {
    RequestCancellation? cancellation,
  }) async => policy;

  @override
  Future<void> testNotification(
    NotifyChannel channel,
    NotifyChannelSettings settings, {
    RequestCancellation? cancellation,
  }) async {
    testCalls.add(channel);
  }
}
