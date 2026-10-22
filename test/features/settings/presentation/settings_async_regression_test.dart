import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/app/appearance_controller.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import 'package:onewifi_android/features/auth/state/session_controller.dart';
import 'package:onewifi_android/features/settings/data/product_license_store.dart';
import 'package:onewifi_android/features/settings/data/settings_repository.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';
import 'package:onewifi_android/features/settings/presentation/settings_screen.dart';
import 'package:onewifi_android/features/settings/state/settings_controller.dart';

import '../../../support/fakes.dart';

SettingsController _create(_Repo repo) => SettingsController(
  repository: repo,
  licenseStore: MemoryProductLicenseStore(),
  requestRegistry: RequestRegistry(),
);

void main() {
  test(
    'control: sequential save and reload preserve the saved value',
    () async {
      final repo = _Repo();
      final controller = _create(repo);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.setSmsAutoClear(false);
      await controller.load();
      expect(repo.stored, isFalse);
      expect(controller.data.smsModem.autoClearModemStorage, isFalse);
    },
  );

  test(
    'SETTINGS-STALE: pending read must not roll back a completed save',
    () async {
      final repo = _Repo();
      final controller = _create(repo);
      addTearDown(controller.dispose);
      await controller.load();
      final oldRead = Completer<SmsModemSettings>();
      repo.readGate = oldRead;
      final pending = controller.load();
      await controller.setSmsAutoClear(false);
      expect(repo.stored, isFalse);
      expect(controller.data.smsModem.autoClearModemStorage, isFalse);
      oldRead.complete(const SmsModemSettings(autoClearModemStorage: true));
      await pending;
      expect(repo.stored, isFalse);
      expect(controller.data.smsModem.autoClearModemStorage, isFalse);
    },
  );

  testWidgets(
    'SETTINGS-DRAFT: unrelated saved setting must not erase license input',
    (tester) async {
      final controller = _create(_Repo());
      final appearance = AppearanceController();
      final session = SessionController(
        repository: _Auth(),
        tokenStore: MemoryTokenStore(),
        baseUrlStore: MemoryBaseUrlStore(Uri.parse('https://example.test')),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);
      addTearDown(appearance.dispose);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(
              sessionController: session,
              appearance: appearance,
              settingsController: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(const Key('settings-license-key')),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, 'UNSAVED-TEST-CODE');
      expect(
        tester.widget<TextField>(field).controller!.text,
        'UNSAVED-TEST-CODE',
      );
      await controller.setSmsAutoClear(false);
      await tester.pump();
      final draft = tester.widget<TextField>(field).controller!.text;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(draft, 'UNSAVED-TEST-CODE');
    },
  );
}

class _Auth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo implements SettingsRepository {
  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<DeveloperQuota?> fetchDeveloper({
    RequestCancellation? cancellation,
  }) async => null;

  @override
  Future<HttpsSettings?> fetchHttps({
    RequestCancellation? cancellation,
  }) async => null;

  @override
  Future<DeveloperQuota> saveDeveloper({
    int? deviceLimit,
    int? smsHourlyLimit,
    RequestCancellation? cancellation,
  }) async => DeveloperQuota(
    deviceLimit: deviceLimit ?? 4,
    maxDeviceLimit: 10,
    smsHourlyLimit: smsHourlyLimit ?? 20,
    maxSmsHourlyLimit: 20,
  );


  @override
  Future<VowifiMtuSettings> fetchVowifiSettings({
    RequestCancellation? cancellation,
  }) async => const VowifiMtuSettings();

  @override
  Future<VowifiMtuSettings> saveVowifiSettings(
    bool mtuCompatibility, {
    RequestCancellation? cancellation,
  }) async => VowifiMtuSettings(mtuCompatibility: mtuCompatibility);

  bool stored = true;
  Completer<SmsModemSettings>? readGate;

  @override
  Future<SmsModemSettings> fetchSmsModemSettings({
    RequestCancellation? cancellation,
  }) =>
      readGate?.future ??
      Future.value(SmsModemSettings(autoClearModemStorage: stored));
  @override
  Future<SmsModemSettings> saveSmsModemSettings(
    bool enabled, {
    RequestCancellation? cancellation,
  }) async {
    stored = enabled;
    return SmsModemSettings(autoClearModemStorage: stored);
  }

  @override
  Future<UiLanguage> fetchPreferences({
    RequestCancellation? cancellation,
  }) async => UiLanguage.zh;
  @override
  Future<SystemInfo> fetchSystemInfo({
    RequestCancellation? cancellation,
  }) async => const SystemInfo();
  @override
  Future<NotificationSettings> fetchNotifications({
    RequestCancellation? cancellation,
  }) async => const NotificationSettings();
  @override
  Future<AccessPolicy> fetchSecurity({
    RequestCancellation? cancellation,
  }) async => const AccessPolicy();
  @override
  Future<GatewayLicenseStatus?> fetchGatewayLicense({
    RequestCancellation? cancellation,
  }) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
