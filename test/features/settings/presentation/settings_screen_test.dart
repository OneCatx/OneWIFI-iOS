import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/app/appearance_controller.dart';
import 'package:onewifi_android/core/config/base_url_store.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/security/secure_token_store.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/one_status_hero.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import 'package:onewifi_android/features/auth/domain/session_user.dart';
import 'package:onewifi_android/features/auth/state/session_controller.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_backend_store.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_client.dart';
import 'package:onewifi_android/features/proxy/state/mihomo_connection_controller.dart';
import 'package:onewifi_android/features/settings/data/product_license_store.dart';
import 'package:onewifi_android/features/settings/data/settings_repository.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';
import 'package:onewifi_android/features/settings/presentation/settings_screen.dart';
import 'package:onewifi_android/features/settings/presentation/widgets/settings_mihomo_form.dart';
import 'package:onewifi_android/features/settings/state/settings_controller.dart';
import 'package:onewifi_android/features/sms/data/sms_otp_sink.dart';
import 'package:onewifi_android/features/sms/data/sms_repository.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/presentation/widgets/remote_otp_pairing_tile.dart';
import 'package:onewifi_android/features/sms/state/sms_controller.dart';

import '../../../support/fakes.dart';

void main() {
  for (final fails in <bool>[false, true]) {
    testWidgets(
      'local-only settings hide the legacy activity action (host fails: $fails)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const channel = MethodChannel('com.oneims.onewifi/otp');
        final calls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'showActivity' && fails) {
            throw PlatformException(
              code: 'activity_failed',
              message: '实时活动未开启',
            );
          }
          return true;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final appearance = AppearanceController();
        addTearDown(appearance.dispose);
        final session = SessionController(
          repository: _AuthRepository(),
          tokenStore: _TokenStore(),
          baseUrlStore: _BaseUrlStore(),
          requestRegistry: RequestRegistry(),
        );
        addTearDown(session.dispose);
        final sms = SmsController(
          repository: _UnusedSmsRepository(),
          requestRegistry: RequestRegistry(),
          otpSink: NativeSmsOtpSink(channel: channel),
        );
        addTearDown(sms.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: OneTheme.light(),
            home: Scaffold(
              body: SettingsScreen(
                sessionController: session,
                appearance: appearance,
                smsController: sms,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(RemoteOtpPairingTile.cardKey), findsOneWidget);
        // An unpaired local notifier cannot create a synthetic OTP activity.
        expect(find.byKey(RemoteOtpPairingTile.activityTestKey), findsNothing);
        expect(calls, isEmpty);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('settings shows OneWIFI nameplates and local appearance chips', (
    tester,
  ) async {
    final appearance = AppearanceController();
    addTearDown(appearance.dispose);
    final session = SessionController(
      repository: _AuthRepository(),
      tokenStore: _TokenStore(),
      baseUrlStore: _BaseUrlStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: Scaffold(
          body: SettingsScreen(
            sessionController: session,
            appearance: appearance,
          ),
        ),
      ),
    );

    expect(find.text('系统设置'), findsOneWidget);
    expect(find.text('授权'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);

    await tester.ensureVisible(find.text('深色'));
    await tester.tap(find.text('深色'));
    await tester.pump();
    expect(appearance.mode, ThemeMode.dark);
    expect(find.text('通知'), findsNothing);
    expect(find.text('登录与访问'), findsNothing);
    expect(find.text('更多'), findsNothing);
    expect(find.text('设备配额 / 短信限额'), findsNothing);
  });

  testWidgets(
    'appearance options share one bar without icon-on-label overlap',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appearance = AppearanceController();
      addTearDown(appearance.dispose);
      final session = SessionController(
        repository: _AuthRepository(),
        tokenStore: _TokenStore(),
        baseUrlStore: _BaseUrlStore(),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.dark(),
          home: Scaffold(
            body: SettingsScreen(
              sessionController: session,
              appearance: appearance,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.light_mode_outlined), findsNothing);
      expect(find.byIcon(Icons.dark_mode_outlined), findsNothing);
      expect(find.byIcon(Icons.brightness_auto_outlined), findsNothing);

      final light = tester.getRect(find.text('浅色'));
      final dark = tester.getRect(find.text('深色'));
      final system = tester.getRect(find.text('跟随系统'));
      expect((light.center.dy - dark.center.dy).abs(), lessThan(1));
      expect((dark.center.dy - system.center.dy).abs(), lessThan(1));
      expect(light.right, lessThanOrEqualTo(dark.left + 1));
      expect(dark.right, lessThanOrEqualTo(system.left + 1));
    },
  );

  testWidgets(
    'gateway settings show version cards, language and the Mihomo box',
    (tester) async {
      final appearance = AppearanceController();
      addTearDown(appearance.dispose);
      final session = SessionController(
        repository: _AuthRepository(),
        tokenStore: _TokenStore(),
        baseUrlStore: _BaseUrlStore(),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(session.dispose);
      final settings = SettingsController(
        repository: _SettingsRepository(),
        licenseStore: MemoryProductLicenseStore(),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(settings.dispose);
      final mihomo = _mihomoController();
      addTearDown(mihomo.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          home: Scaffold(
            body: SettingsScreen(
              sessionController: session,
              appearance: appearance,
              settingsController: settings,
              mihomo: mihomo,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Mihomo'), findsOneWidget);
      expect(find.text('连接'), findsOneWidget);
      expect(find.text('未连接'), findsOneWidget);
      expect(find.text('Telegram'), findsNothing);
      expect(find.text('当前密码'), findsNothing);
      expect(find.text('问题日志'), findsNothing);
      expect(find.text('中文'), findsOneWidget);
      await tester.ensureVisible(find.byKey(SettingsScreen.languageEnKey));
      await tester.tap(find.byKey(SettingsScreen.languageEnKey));
      await tester.pump();
      await tester.pump();
      expect(settings.data.language, UiLanguage.en);
      expect(find.byType(OneStatusHero), findsNothing);
      expect(find.byKey(const Key('sms-auto-clear-off')), findsOneWidget);
      expect(find.text('处理中'), findsNothing);
      expect(find.text('Language saved'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(SettingsScreen)),
      ).hideCurrentSnackBar();
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('settings-license-key')));
      final licenseField = find.descendant(
        of: find.byKey(const Key('settings-license-key')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(licenseField).obscureText, isTrue);
      await tester.tap(find.byTooltip('显示激活码'));
      await tester.pump();
      expect(tester.widget<TextField>(licenseField).obscureText, isFalse);
    },
  );

  testWidgets('active license hides the key field and can be deactivated', (
    tester,
  ) async {
    final appearance = AppearanceController();
    addTearDown(appearance.dispose);
    final session = SessionController(
      repository: _AuthRepository(),
      tokenStore: _TokenStore(),
      baseUrlStore: _BaseUrlStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(session.dispose);
    final licenseStore = MemoryProductLicenseStore(
      ProductLicense(key: 'AB12-CD34-EF56-GH78', activated: true),
    );
    final settings = SettingsController(
      repository: _SettingsRepository(),
      licenseStore: licenseStore,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(settings.dispose);
    final mihomo = _mihomoController();
    addTearDown(mihomo.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: Scaffold(
          body: SettingsScreen(
            sessionController: session,
            appearance: appearance,
            settingsController: settings,
            mihomo: mihomo,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('settings-license-key')), findsNothing);
    expect(
      find.byKey(const Key('settings-license-deactivate')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('settings-license-deactivate')),
    );
    await tester.tap(find.byKey(const Key('settings-license-deactivate')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('settings-license-key')), findsOneWidget);
    expect((await licenseStore.read()).isActive, isFalse);
    expect(find.text('已解除本机激活'), findsOneWidget);
  });

  testWidgets('shows VoWiFi MTU compatibility tiles above SMS auto-clear', (
    tester,
  ) async {
    final appearance = AppearanceController();
    addTearDown(appearance.dispose);
    final session = SessionController(
      repository: _AuthRepository(),
      tokenStore: _TokenStore(),
      baseUrlStore: _BaseUrlStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(session.dispose);
    final settings = SettingsController(
      repository: _SettingsRepository(),
      licenseStore: MemoryProductLicenseStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(settings.dispose);
    await settings.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: Scaffold(
          body: SettingsScreen(
            sessionController: session,
            appearance: appearance,
            settingsController: settings,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('VoWiFi MTU 兼容模式'));
    expect(find.text('VoWiFi MTU 兼容模式'), findsOneWidget);
    expect(find.byKey(const Key('vowifi-mtu-on')), findsOneWidget);
    expect(find.byKey(const Key('vowifi-mtu-off')), findsOneWidget);
    expect(find.text('自动清理模组短信存储'), findsOneWidget);
  });

  testWidgets('Mihomo connect probe marks the box connected', (tester) async {
    final appearance = AppearanceController();
    addTearDown(appearance.dispose);
    final session = SessionController(
      repository: _AuthRepository(),
      tokenStore: _TokenStore(),
      baseUrlStore: _BaseUrlStore(),
      requestRegistry: RequestRegistry(),
    );
    addTearDown(session.dispose);
    final mihomo = _mihomoController();
    addTearDown(mihomo.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: Scaffold(
          body: SettingsScreen(
            sessionController: session,
            appearance: appearance,
            mihomo: mihomo,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('未连接'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(SettingsMihomoForm.hostFieldKey))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(SettingsMihomoForm.portFieldKey))
          .controller!
          .text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(SettingsMihomoForm.hostFieldKey),
      '192.168.1.99',
    );
    await tester.enterText(find.byKey(SettingsMihomoForm.portFieldKey), '9090');
    await tester.ensureVisible(find.byKey(SettingsMihomoForm.connectTargetKey));
    await tester.tap(find.byKey(SettingsMihomoForm.connectTargetKey));
    await tester.pump();
    await tester.pump();

    expect(mihomo.connected, isTrue);
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('已连上'), findsOneWidget);
  });
}

// Opening settings must not fetch the SMS inbox or send messages.
final class _UnusedSmsRepository implements SmsRepository {
  @override
  Future<List<SmsContact>> fetchContacts({
    RequestCancellation? cancellation,
  }) async => throw StateError('Settings must not fetch SMS contacts');

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) async => throw StateError('Settings must not fetch SMS threads');

  @override
  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) async => throw StateError('Settings must not send SMS');

  @override
  Future<int> deleteThread(
    SmsContactTarget target, {
    RequestCancellation? cancellation,
  }) async => throw StateError('Settings must not delete SMS');

  @override
  Future<bool> deleteMessage(
    int messageId, {
    RequestCancellation? cancellation,
  }) async => throw StateError('Settings must not delete SMS');
}

MihomoConnectionController _mihomoController() {
  return MihomoConnectionController(
    store: MemoryMihomoBackendStore(),
    client: MihomoClient(
      client: FakeClient((request) async {
        return http.StreamedResponse(
          Stream<List<int>>.value(
            utf8.encode(
              jsonEncode(<String, Object?>{'proxies': <String, Object?>{}}),
            ),
          ),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
      originProvider: () async => Uri.parse('http://unused.test:9090'),
    ),
    requestRegistry: RequestRegistry(),
  );
}

final class _BaseUrlStore implements BaseUrlStore {
  @override
  Future<Uri> read() async => Uri.parse('https://api.example.test');

  @override
  Future<void> write(Uri origin) async {}
}

final class _TokenStore implements TokenStore {
  @override
  Future<void> clear(Uri origin) async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<String?> read(Uri origin) async => 'token';

  @override
  Future<void> write(Uri origin, String token) async {}
}

final class _AuthRepository implements AuthRepository {
  @override
  Future<SessionUser> login(String username, String password) async =>
      SessionUser(username);

  @override
  Future<void> logout() async {}

  @override
  Future<SessionUser> restore({RequestCancellation? cancellation}) async =>
      SessionUser('admin');
}

final class _SettingsRepository implements SettingsRepository {
  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    RequestCancellation? cancellation,
  }) async {}

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
  Future<GatewayUpdateApply> applyUpdate({
    RequestCancellation? cancellation,
  }) async => const GatewayUpdateApply(applied: false);

  @override
  Future<GatewayUpdate> checkUpdate({RequestCancellation? cancellation}) async {
    return const GatewayUpdate(
      available: false,
      message: '当前已是最新',
      repository: 'owner/onewifi',
    );
  }

  @override
  Future<DeveloperQuota?> fetchDeveloper({
    RequestCancellation? cancellation,
  }) async => null;

  @override
  Future<HttpsSettings?> fetchHttps({
    RequestCancellation? cancellation,
  }) async => null;

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
  }) async => const SystemInfo(version: 'v-test');

  @override
  Future<DeveloperQuota> saveDeveloper({
    int? deviceLimit,
    int? smsHourlyLimit,
    RequestCancellation? cancellation,
  }) async {
    return const DeveloperQuota(
      deviceLimit: 1,
      maxDeviceLimit: 10,
      smsHourlyLimit: 20,
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
  }) async => language;

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
  }) async {}
}
