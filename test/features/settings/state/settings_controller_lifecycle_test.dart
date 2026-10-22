import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/settings/data/product_license_store.dart';
import 'package:onewifi_android/features/settings/data/settings_repository.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';
import 'package:onewifi_android/features/settings/state/settings_controller.dart';

typedef _Notification = (String, bool);

void main() {
  group('after dispose()', () {
    const seeded = ('新密码至少 10 位', true);

    Future<_Harness> disposed() async {
      final h = _Harness();
      await h.controller.changePassword(
        currentPassword: 'old-password',
        newPassword: 'short',
        confirmPassword: 'short',
      );
      expect(h.log, <_Notification>[seeded]);
      h.controller.dispose();
      return h;
    }

    void expectSilent(_Harness h) {
      expect(h.log, <_Notification>[seeded]);
      expect(h.controller.notice, seeded.$1);
      expect(h.controller.noticeError, seeded.$2);
      expect(h.repo.calls, isEmpty);
      expect(h.license.writes, 0);
    }

    test('activateLicense with an empty key completes silently', () async {
      final h = await disposed();
      await expectLater(h.controller.activateLicense(''), completes);
      expectSilent(h);
      expect(h.controller.licenseAction.status, ActionStatus.idle);
    });

    test('activateLicense with a blank key completes silently', () async {
      final h = await disposed();
      await expectLater(h.controller.activateLicense('  '), completes);
      expectSilent(h);
      expect(h.controller.licenseAction.status, ActionStatus.idle);
    });

    test('testChannel(pushplus) completes silently', () async {
      final h = await disposed();
      await expectLater(
        h.controller.testChannel(NotifyChannel.pushplus),
        completes,
      );
      expectSilent(h);
      expect(h.controller.testAction.status, ActionStatus.idle);
      expect(h.controller.testingChannel, isNull);
    });

    test('load completes silently', () async {
      final h = await disposed();
      await expectLater(h.controller.load(), completes);
      expectSilent(h);
      expect(h.license.reads, 0);
      expect(h.controller.snapshot.status, QueryStatus.initial);
    });

    test('setLanguage(en) completes silently', () async {
      final h = await disposed();
      await expectLater(h.controller.setLanguage(UiLanguage.en), completes);
      expectSilent(h);
      expect(h.controller.languageAction.status, ActionStatus.idle);
      expect(h.controller.data.language, UiLanguage.zh);
    });

    test('patchNotify returns normally without a notification', () async {
      final h = await disposed();
      expect(
        () => h.controller.patchNotify(
          NotifyChannel.telegram,
          const NotifyChannelSettings(enabled: true),
        ),
        returnsNormally,
      );
      expectSilent(h);
      expect(h.controller.data.notifications.telegram.enabled, isFalse);
    });

    test('saveNotifications completes silently', () async {
      final h = await disposed();
      await expectLater(h.controller.saveNotifications(), completes);
      expectSilent(h);
      expect(h.controller.notifyAction.status, ActionStatus.idle);
    });

    test('testChannel(telegram) completes silently', () async {
      final h = await disposed();
      await expectLater(
        h.controller.testChannel(NotifyChannel.telegram),
        completes,
      );
      expectSilent(h);
      expect(h.controller.testAction.status, ActionStatus.idle);
      expect(h.controller.testingChannel, isNull);
    });

    test('changePassword with a valid password completes silently', () async {
      final h = await disposed();
      await expectLater(
        h.controller.changePassword(
          currentPassword: 'old-password',
          newPassword: 'new-password-1',
          confirmPassword: 'new-password-1',
        ),
        completes,
      );
      expectSilent(h);
      expect(h.controller.passwordAction.status, ActionStatus.idle);
      expect(h.controller.passwordChanged, isFalse);
    });

    test('saveSecurity completes silently', () async {
      final h = await disposed();
      await expectLater(
        h.controller.saveSecurity(
          mode: AccessMode.public,
          allowedCidrsText: '10.0.0.0/8',
          trustProxyHeaders: false,
          trustedProxyCidrsText: '',
        ),
        completes,
      );
      expectSilent(h);
      expect(h.controller.securityAction.status, ActionStatus.idle);
      expect(h.controller.data.security.mode, AccessMode.internal);
    });

    test('setHttps(true) completes silently', () async {
      final h = await disposed();
      await expectLater(h.controller.setHttps(true), completes);
      expectSilent(h);
      expect(h.controller.httpsAction.status, ActionStatus.idle);
      expect(h.controller.data.https, isNull);
    });

    test('saveQuota completes silently', () async {
      final h = await disposed();
      await expectLater(h.controller.saveQuota(deviceLimit: 6), completes);
      expectSilent(h);
      expect(h.controller.quotaAction.status, ActionStatus.idle);
      expect(h.controller.data.quota, isNull);
    });

    test('activateLicense with a real key completes silently', () async {
      final h = await disposed();
      await expectLater(h.controller.activateLicense('KEY-1'), completes);
      expectSilent(h);
      expect(h.controller.licenseAction.status, ActionStatus.idle);
      expect(h.controller.data.license.key, '');
    });
  });

  group('disposed while a request is in flight', () {
    const submitting = <_Notification>[('', false)];

    Future<void> expectLateIgnored(
      _Harness h,
      Future<void> Function() start,
      List<_Notification> started, {
      bool fail = false,
    }) async {
      h.hold();
      final pending = start();
      final issued = List<String>.of(h.repo.calls);
      expect(issued, isNotEmpty);
      expect(h.log, started);
      h.controller.dispose();
      if (fail) h.fail();
      h.release();
      await expectLater(pending, completes);
      expect(h.log, started);
      expect(h.repo.calls, issued);
      expect(h.controller.notice, '');
      expect(h.controller.noticeError, isFalse);
    }

    test('setLanguage: late success completes silently', () async {
      final h = _Harness();
      await expectLateIgnored(
        h,
        () => h.controller.setLanguage(UiLanguage.en),
        submitting,
      );
      expect(h.controller.data.language, UiLanguage.zh);
    });

    test('setLanguage: late failure completes silently', () async {
      final h = _Harness();
      await expectLateIgnored(
        h,
        () => h.controller.setLanguage(UiLanguage.en),
        submitting,
        fail: true,
      );
      expect(h.controller.data.language, UiLanguage.zh);
    });

    test('saveNotifications: late success completes silently', () async {
      final h = _Harness();
      await expectLateIgnored(h, h.controller.saveNotifications, submitting);
      expect(h.controller.notifyAction.status, ActionStatus.submitting);
    });

    test('saveNotifications: late failure completes silently', () async {
      final h = _Harness();
      await expectLateIgnored(
        h,
        h.controller.saveNotifications,
        submitting,
        fail: true,
      );
      expect(h.controller.notifyAction.status, ActionStatus.submitting);
    });

    test('load: late success completes silently', () async {
      final h = _Harness();
      await expectLateIgnored(h, h.controller.load, submitting);
      expect(h.controller.snapshot.status, QueryStatus.loading);
    });

    test('load: late failure completes silently', () async {
      final h = _Harness();
      await expectLateIgnored(h, h.controller.load, submitting, fail: true);
      expect(h.controller.snapshot.status, QueryStatus.loading);
    });

  });

  group('dispose() twice', () {
    test('second dispose() returns normally without a notification', () {
      final h = _Harness();
      h.controller.dispose();
      expect(h.controller.dispose, returnsNormally);
      expect(h.log, isEmpty);
    });
  });
}

final class _Harness {
  _Harness() {
    controller = SettingsController(
      repository: repo,
      licenseStore: license,
      requestRegistry: RequestRegistry(),
    );
    controller.addListener(() {
      log.add((controller.notice, controller.noticeError));
    });
    addTearDown(controller.dispose);
  }

  final _Repo repo = _Repo();
  final _LicenseStore license = _LicenseStore();
  final List<_Notification> log = <_Notification>[];
  late final SettingsController controller;
  Completer<void>? _gate;

  void hold() {
    final gate = Completer<void>();
    _gate = gate;
    repo.gate = gate;
  }

  void release() => _gate?.complete();

  void fail() => repo.failure = StateError('boom');
}

final class _LicenseStore implements ProductLicenseStore {
  int reads = 0;
  int writes = 0;
  ProductLicense stored = const ProductLicense();

  @override
  Future<ProductLicense> read() async {
    reads += 1;
    return stored;
  }

  @override
  Future<void> write(ProductLicense license) async {
    writes += 1;
    stored = license;
  }

  @override
  Future<ProductLicense> activate(String key) async {
    final next = ProductLicense(key: key.trim(), activated: true);
    await write(next);
    return next;
  }

  @override
  Future<ProductLicense> deactivate() async {
    const next = ProductLicense();
    await write(next);
    return next;
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

  Completer<void>? gate;
  Object? failure;
  final List<String> calls = <String>[];

  Future<T> _respond<T>(String name, T Function() result) async {
    calls.add(name);
    final pending = gate;
    if (pending != null) await pending.future;
    final error = failure;
    if (error != null) throw error;
    return result();
  }

  @override
  Future<GatewayUpdateApply> applyUpdate({RequestCancellation? cancellation}) =>
      _respond<GatewayUpdateApply>(
        'applyUpdate',
        () => const GatewayUpdateApply(applied: false),
      );

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    RequestCancellation? cancellation,
  }) => _respond<void>('changePassword', () {});

  @override
  Future<GatewayUpdate> checkUpdate({RequestCancellation? cancellation}) =>
      _respond<GatewayUpdate>(
        'checkUpdate',
        () => const GatewayUpdate(available: false),
      );

  @override
  Future<DeveloperQuota?> fetchDeveloper({RequestCancellation? cancellation}) =>
      _respond<DeveloperQuota?>('fetchDeveloper', () => null);

  @override
  Future<HttpsSettings?> fetchHttps({RequestCancellation? cancellation}) =>
      _respond<HttpsSettings?>('fetchHttps', () => null);

  @override
  Future<NotificationSettings> fetchNotifications({
    RequestCancellation? cancellation,
  }) => _respond<NotificationSettings>(
    'fetchNotifications',
    () => const NotificationSettings(),
  );

  @override
  Future<UiLanguage> fetchPreferences({RequestCancellation? cancellation}) =>
      _respond<UiLanguage>('fetchPreferences', () => UiLanguage.zh);

  @override
  Future<AccessPolicy> fetchSecurity({RequestCancellation? cancellation}) =>
      _respond<AccessPolicy>('fetchSecurity', () => const AccessPolicy());

  @override
  Future<SystemInfo> fetchSystemInfo({RequestCancellation? cancellation}) =>
      _respond<SystemInfo>('fetchSystemInfo', () => const SystemInfo());

  @override
  Future<DeveloperQuota> saveDeveloper({
    int? deviceLimit,
    int? smsHourlyLimit,
    RequestCancellation? cancellation,
  }) => _respond<DeveloperQuota>(
    'saveDeveloper',
    () => DeveloperQuota(
      deviceLimit: deviceLimit ?? 4,
      maxDeviceLimit: 10,
      smsHourlyLimit: smsHourlyLimit ?? 20,
      maxSmsHourlyLimit: 20,
    ),
  );

  @override
  Future<HttpsSettings> saveHttps(
    bool enabled, {
    RequestCancellation? cancellation,
  }) => _respond<HttpsSettings>(
    'saveHttps',
    () => HttpsSettings(enabled: enabled),
  );

  @override
  Future<HttpsSettings> uploadCustomCertificate({
    required String certificate,
    required String privateKey,
    RequestCancellation? cancellation,
  }) => _respond<HttpsSettings>(
    'uploadCustomCertificate',
    () => const HttpsSettings(enabled: false),
  );

  @override
  Future<HttpsSettings> deleteCustomCertificate({
    RequestCancellation? cancellation,
  }) => _respond<HttpsSettings>(
    'deleteCustomCertificate',
    () => const HttpsSettings(enabled: false),
  );

  @override
  Future<HttpsSettings> reissueCertificate({
    RequestCancellation? cancellation,
  }) => _respond<HttpsSettings>(
    'reissueCertificate',
    () => const HttpsSettings(enabled: false),
  );

  @override
  Future<NotificationSettings> saveNotifications(
    NotificationSettings notifications, {
    RequestCancellation? cancellation,
  }) =>
      _respond<NotificationSettings>('saveNotifications', () => notifications);

  @override
  Future<UiLanguage> savePreferences(
    UiLanguage language, {
    RequestCancellation? cancellation,
  }) => _respond<UiLanguage>('savePreferences', () => language);

  @override
  Future<AccessPolicy> saveSecurity(
    AccessPolicy policy, {
    RequestCancellation? cancellation,
  }) => _respond<AccessPolicy>('saveSecurity', () => policy);

  @override
  Future<void> testNotification(
    NotifyChannel channel,
    NotifyChannelSettings settings, {
    RequestCancellation? cancellation,
  }) => _respond<void>('testNotification', () {});
}
