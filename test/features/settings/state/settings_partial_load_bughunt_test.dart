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

// B1-01：`SettingsController.load()` 用 `_ignore` 把五路读取的失败逐个吞掉，
// 只要不是 preferences / systemInfo / notifications 三路同时失败，就一律落
// `QueryState.data`，且 `notice` 为空——被吞掉的那一节用默认值顶上。
//
// 期望来源：
// - `QueryState.failedAfter` 文档：「读取失败……让 UI 提示『可能不是最新』」。
// - 对照路径：`OverviewController._request` 任一路失败都落 `QueryState.failed`。
// - `PUT /api/settings/notifications` 为整体替换，默认值一旦被当成真数据保存
//   就会覆盖网关上其它通道的配置。
void main() {
  test('补读期间的编辑随本次提交，PUT期间的新编辑保留到下一次', () async {
    final repo = _Repo()..notificationsFailure = StateError('unavailable');
    final controller = SettingsController(
      repository: repo,
      licenseStore: _LicenseStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    repo.notificationsFailure = null;
    final reading = Completer<void>();
    final writing = Completer<void>();
    repo.readGate = reading;
    repo.writeGate = writing;
    controller.patchNotify(
      NotifyChannel.telegram,
      const NotifyChannelSettings(url: 'before GET'),
    );
    final saving = controller.saveNotifications();
    controller.patchNotify(
      NotifyChannel.telegram,
      const NotifyChannelSettings(url: 'during GET'),
    );
    reading.complete();
    await pumpEventQueue();
    expect(repo.savedNotifications!.telegram.url, 'during GET');
    controller.patchNotify(
      NotifyChannel.telegram,
      const NotifyChannelSettings(url: 'during PUT'),
    );
    writing.complete();
    await saving;
    expect(controller.data.notifications.telegram.url, 'during PUT');
    expect(controller.notice, contains('未保存'));
    await controller.load();
    expect(controller.data.notifications.telegram.url, 'during PUT');
    await controller.saveNotifications();
    expect(repo.savedNotifications!.telegram.url, 'during PUT');
    expect(controller.notice, '通知设置已保存');
  });
  test('仅 fetchNotifications 失败时，load() 不得把默认通知设置当作已加载数据静默展示', () async {
    final repo = _Repo()
      ..notificationsFailure = const ApiFailure(
        ApiFailureKind.http,
        requestId: 'notify-503',
        statusCode: 503,
      );
    final controller = SettingsController(
      repository: repo,
      licenseStore: _LicenseStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();

    final snapshot = controller.snapshot;
    final surfaced =
        snapshot.status == QueryStatus.failed ||
        snapshot.failure != null ||
        controller.notice.isNotEmpty;
    expect(
      surfaced,
      isTrue,
      reason:
          '通知设置读取失败（503）后：status=${snapshot.status.name}、'
          'failure=${snapshot.failure?.kind.name}、notice="${controller.notice}"；'
          '用户看到的是全部通道关闭的默认值，没有任何失败标记',
    );
  });

  test('部分读取失败时，提示必须报出坏掉的是哪几节', () async {
    final repo = _Repo()
      ..notificationsFailure = StateError('unavailable')
      ..vowifiFailure = StateError('unavailable');
    final controller = SettingsController(
      repository: repo,
      licenseStore: _LicenseStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.noticeError, isTrue);
    expect(controller.notice, '部分设置读取失败：通知设置、VoWiFi 兼容');
  });

  test('通知设置读取失败后保存别的通道，不得把网关上未读到的通道配置覆盖成默认值', () async {
    final repo = _Repo()
      ..gatewayNotifications = const NotificationSettings(
        bark: NotifyChannelSettings(enabled: true, url: 'https://bark.example'),
      )
      ..notificationsFailure = const ApiFailure(
        ApiFailureKind.http,
        requestId: 'notify-503',
        statusCode: 503,
      );
    final controller = SettingsController(
      repository: repo,
      licenseStore: _LicenseStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    controller.patchNotify(
      NotifyChannel.telegram,
      const NotifyChannelSettings(enabled: true, botToken: 't', chatId: 'c'),
    );
    repo.notificationsFailure = null;
    await controller.saveNotifications();

    expect(controller.notifyAction.status, ActionStatus.succeeded);
    final sent = repo.savedNotifications;
    expect(sent, isNotNull, reason: '保存请求应当发出');
    expect(
      sent!.bark.enabled,
      isTrue,
      reason: 'bark 从未成功读到，却以 enabled=false / url="" 的默认值被 PUT 回网关',
    );
    expect(sent.bark.url, 'https://bark.example');
  });
}

final class _LicenseStore implements ProductLicenseStore {
  @override
  Future<ProductLicense> read() async => const ProductLicense();

  @override
  Future<void> write(ProductLicense license) async {}

  @override
  Future<ProductLicense> activate(String key) async =>
      ProductLicense(key: key.trim(), activated: true);

  @override
  Future<ProductLicense> deactivate() async => const ProductLicense();
}

final class _Repo implements SettingsRepository {
  @override
  Future<NotificationSettings> fetchNotifications({
    RequestCancellation? cancellation,
  }) async {
    final failure = notificationsFailure;
    if (failure != null) throw failure;
    if (readGate != null) await readGate!.future;
    return gatewayNotifications;
  }

  @override
  Future<VowifiMtuSettings> fetchVowifiSettings({
    RequestCancellation? cancellation,
  }) async {
    final failure = vowifiFailure;
    if (failure != null) throw failure;
    return const VowifiMtuSettings();
  }

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

  Object? notificationsFailure;
  Object? vowifiFailure;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  NotificationSettings gatewayNotifications = const NotificationSettings();
  NotificationSettings? savedNotifications;

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
  Future<NotificationSettings> saveNotifications(
    NotificationSettings notifications, {
    RequestCancellation? cancellation,
  }) async {
    savedNotifications = notifications;
    if (writeGate != null) await writeGate!.future;
    gatewayNotifications = notifications;
    return notifications;
  }

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
  }) async => DeveloperQuota(
    deviceLimit: deviceLimit ?? 4,
    maxDeviceLimit: 10,
    smsHourlyLimit: smsHourlyLimit ?? 20,
    maxSmsHourlyLimit: 20,
  );
}
