import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/console_layout.dart';
import 'package:onewifi_android/features/settings/data/product_license_store.dart';
import 'package:onewifi_android/features/settings/data/settings_repository.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';
import 'package:onewifi_android/features/settings/presentation/settings_notify_sheet.dart';
import 'package:onewifi_android/features/settings/state/settings_controller.dart';

const Key _testKey = Key('settings-notify-test');
const Key _saveKey = Key('settings-notify-save');

void main() {
  testWidgets(
    'telegram renders five fields pre-filled from the snapshot and offers 测试',
    (tester) async {
      await _tall(tester);
      final controller = await _loaded(_Repo());
      await tester.pumpWidget(_app(controller, NotifyChannel.telegram));

      expect(find.text('Telegram'), findsOneWidget);
      expect(find.byTooltip('关闭'), findsOneWidget);
      expect(_switch(tester, '启用').value, isTrue);
      expect(_labels(tester), <String>[
        'Bot token',
        'Chat ID',
        'Admin ID',
        'Base URL',
        '代理',
      ]);
      expect(_field(tester, 'Bot token').controller!.text, 'bot:token');
      expect(_field(tester, 'Bot token').obscureText, isTrue);
      expect(_field(tester, 'Chat ID').controller!.text, '100');
      expect(_field(tester, 'Chat ID').obscureText, isFalse);
      expect(_field(tester, 'Admin ID').controller!.text, '7');
      expect(_field(tester, 'Base URL').controller!.text, 'https://tg.example');
      expect(_field(tester, 'Base URL').decoration!.hintText, '可空');
      expect(_field(tester, '代理').controller!.text, 'socks5://proxy');
      expect(_field(tester, '代理').decoration!.hintText, '可空');
      expect(_field(tester, 'Chat ID').decoration!.hintText, isNull);

      expect(find.byKey(_testKey), findsOneWidget);
      expect(find.text('测试'), findsOneWidget);
      expect(find.byKey(_saveKey), findsOneWidget);
      expect(find.text('保存通知设置'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('此通道不支持连通测试。'), findsNothing);
      expect(find.text('SSL'), findsNothing);
      expect(_glass(tester, _testKey).onPressed, isNotNull);
      expect(_glass(tester, _saveKey).onPressed, isNotNull);
    },
  );

  testWidgets('email renders SMTP fields, a numeric 端口 and the SSL switch', (
    tester,
  ) async {
    await _tall(tester);
    final controller = await _loaded(_Repo());
    await tester.pumpWidget(_app(controller, NotifyChannel.email));

    expect(find.text('Email'), findsOneWidget);
    expect(_switch(tester, '启用').value, isFalse);
    expect(_labels(tester), <String>[
      'SMTP 主机',
      '端口',
      '用户名',
      '密码',
      '发件人',
      '收件人（逗号分隔）',
    ]);
    expect(_field(tester, 'SMTP 主机').controller!.text, 'smtp.example');
    expect(_field(tester, '端口').controller!.text, '587');
    expect(_field(tester, '端口').keyboardType, TextInputType.number);
    expect(
      _field(tester, '端口').inputFormatters,
      contains(FilteringTextInputFormatter.digitsOnly),
    );
    expect(_field(tester, '用户名').controller!.text, 'mailer');
    expect(_field(tester, '密码').controller!.text, 'mail-secret');
    expect(_field(tester, '密码').obscureText, isTrue);
    expect(_field(tester, '发件人').controller!.text, 'alerts@example.com');
    expect(
      _field(tester, '收件人（逗号分隔）').controller!.text,
      'ops@example.com,noc@example.com',
    );
    expect(_switch(tester, 'SSL').value, isFalse);
    expect(find.byKey(_testKey), findsOneWidget);
    expect(find.text('此通道不支持连通测试。'), findsNothing);
  });

  testWidgets('webhook renders URL and an obscured Secret', (tester) async {
    await _tall(tester);
    final controller = await _loaded(_Repo());
    await tester.pumpWidget(_app(controller, NotifyChannel.webhook));

    expect(find.text('Webhook'), findsOneWidget);
    expect(_switch(tester, '启用').value, isFalse);
    expect(_labels(tester), <String>['URL', 'Secret']);
    expect(_field(tester, 'URL').controller!.text, 'https://hook.example/n');
    expect(_field(tester, 'URL').obscureText, isFalse);
    expect(_field(tester, 'Secret').controller!.text, 'hook-secret');
    expect(_field(tester, 'Secret').obscureText, isTrue);
    expect(find.text('SSL'), findsNothing);
    expect(find.byKey(_testKey), findsOneWidget);
  });

  testWidgets(
    'typing alone does not patch; the 启用 toggle and 保存 commit the drafts',
    (tester) async {
      await _tall(tester);
      final repository = _Repo();
      final controller = await _loaded(repository);
      await tester.pumpWidget(_app(controller, NotifyChannel.telegram));

      await tester.enterText(_fieldFinder('Chat ID'), '200');
      await tester.pump();
      expect(
        controller.data.notifications.of(NotifyChannel.telegram).chatId,
        '100',
      );
      expect(repository.saved, isEmpty);

      await tester.tap(find.widgetWithText(SwitchListTile, '启用'));
      await tester.pump();
      final toggled = controller.data.notifications.of(NotifyChannel.telegram);
      expect(toggled.enabled, isFalse);
      expect(toggled.chatId, '200');
      expect(toggled.botToken, 'bot:token');
      expect(_switch(tester, '启用').value, isFalse);
      expect(repository.saved, isEmpty);
      expect(controller.notifyAction.status, ActionStatus.idle);

      await tester.enterText(_fieldFinder('Admin ID'), '9');
      await tester.tap(find.byKey(_saveKey));
      await tester.pumpAndSettle();
      expect(repository.saved, hasLength(1));
      final sent = repository.saved.single;
      expect(sent.telegram.enabled, isFalse);
      expect(sent.telegram.chatId, '200');
      expect(sent.telegram.adminId, '9');
      expect(sent.telegram.botToken, 'bot:token');
      expect(sent.telegram.baseUrl, 'https://tg.example');
      expect(sent.telegram.proxy, 'socks5://proxy');
      expect(sent.email.smtpHost, 'smtp.example');
      expect(sent.webhook.url, 'https://hook.example/n');
      expect(
        controller.data.notifications.of(NotifyChannel.telegram).adminId,
        '9',
      );
      expect(controller.notifyAction.status, ActionStatus.succeeded);
      expect(controller.notice, '通知设置已保存');
      expect(controller.noticeError, isFalse);
      expect(find.text('保存通知设置'), findsOneWidget);
    },
  );

  testWidgets('保存 shows 保存中… and locks 测试 until the repository answers', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repo()..saveGate = Completer<NotificationSettings>();
    final controller = await _loaded(repository);
    await tester.pumpWidget(_app(controller, NotifyChannel.telegram));

    await tester.tap(find.byKey(_saveKey));
    await tester.pump();
    expect(repository.saved, hasLength(1));
    expect(controller.notifyAction.status, ActionStatus.submitting);
    expect(find.text('保存中…'), findsOneWidget);
    expect(find.text('保存通知设置'), findsNothing);
    expect(_glass(tester, _saveKey).busy, isTrue);
    expect(_glass(tester, _saveKey).onPressed, isNull);
    expect(_glass(tester, _testKey).busy, isFalse);
    expect(_glass(tester, _testKey).onPressed, isNull);
    expect(find.text('测试'), findsOneWidget);

    repository.saveGate!.complete(repository.saved.single);
    await tester.pumpAndSettle();
    expect(controller.notifyAction.status, ActionStatus.succeeded);
    expect(find.text('保存中…'), findsNothing);
    expect(find.text('保存通知设置'), findsOneWidget);
    expect(_glass(tester, _saveKey).busy, isFalse);
    expect(_glass(tester, _saveKey).onPressed, isNotNull);
    expect(_glass(tester, _testKey).onPressed, isNotNull);
  });

  testWidgets(
    'pushplus has no 测试 button and says so; telegram 测试 sends the committed draft',
    (tester) async {
      await _tall(tester);
      final repository = _Repo();
      final controller = await _loaded(repository);

      await tester.pumpWidget(_app(controller, NotifyChannel.pushplus));
      expect(find.text('PushPlus'), findsOneWidget);
      expect(_labels(tester), <String>['Token', 'Topic', 'Channel']);
      expect(_field(tester, 'Token').controller!.text, 'pp-token');
      expect(_field(tester, 'Token').obscureText, isTrue);
      expect(_field(tester, 'Topic').controller!.text, 'ops');
      expect(_field(tester, 'Channel').controller!.text, 'wechat');
      expect(find.byKey(_testKey), findsNothing);
      expect(find.text('测试'), findsNothing);
      expect(find.text('此通道不支持连通测试。'), findsOneWidget);
      expect(find.byKey(_saveKey), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);

      await tester.pumpWidget(_app(controller, NotifyChannel.telegram));
      await tester.enterText(_fieldFinder('Chat ID'), '300');
      await tester.tap(find.byKey(_testKey));
      await tester.pumpAndSettle();
      expect(repository.testCalls, hasLength(1));
      expect(repository.testCalls.single.channel, NotifyChannel.telegram);
      expect(repository.testCalls.single.settings.chatId, '300');
      expect(repository.testCalls.single.settings.botToken, 'bot:token');
      expect(
        controller.data.notifications.of(NotifyChannel.telegram).chatId,
        '300',
      );
      expect(controller.testAction.status, ActionStatus.succeeded);
      expect(controller.notice, '测试已发送');
      expect(controller.noticeError, isFalse);
      expect(repository.saved, isEmpty);
    },
  );

  testWidgets(
    'a non-numeric 端口 rejects submit, keeps the previous port and shows 端口必须是数字',
    (tester) async {
      await _tall(tester);
      final repository = _Repo();
      final controller = await _loaded(repository);
      await tester.pumpWidget(_app(controller, NotifyChannel.email));

      await tester.enterText(_fieldFinder('端口'), 'abc');
      await tester.tap(find.byKey(_saveKey));
      await tester.pumpAndSettle();
      expect(repository.saved, isEmpty);
      expect(
        controller.data.notifications.of(NotifyChannel.email).smtpPort,
        587,
      );
      expect(_field(tester, '端口').controller!.text, isEmpty);
      expect(_field(tester, '端口').decoration!.errorText, '端口必须是数字');

      await tester.enterText(_fieldFinder('端口'), '0');
      await tester.tap(find.byKey(_saveKey));
      await tester.pumpAndSettle();
      expect(repository.saved, isEmpty);
      expect(
        controller.data.notifications.of(NotifyChannel.email).smtpPort,
        587,
      );
      expect(_field(tester, '端口').controller!.text, '0');
      expect(_field(tester, '端口').decoration!.errorText, '端口必须是数字');

      await tester.enterText(_fieldFinder('端口'), ' 2525 ');
      await tester.tap(find.byKey(_saveKey));
      await tester.pumpAndSettle();
      expect(repository.saved, hasLength(1));
      expect(repository.saved.last.email.smtpPort, 2525);
      expect(_field(tester, '端口').decoration!.errorText, isNull);

      await tester.tap(find.widgetWithText(SwitchListTile, 'SSL'));
      await tester.pump();
      expect(
        controller.data.notifications.of(NotifyChannel.email).useSsl,
        isTrue,
      );
      expect(_switch(tester, 'SSL').value, isTrue);
      expect(repository.saved, hasLength(1));
    },
  );

  testWidgets('SSL does not patch while 端口 is non-numeric', (tester) async {
    await _tall(tester);
    final controller = await _loaded(_Repo());
    await tester.pumpWidget(_app(controller, NotifyChannel.email));

    await tester.enterText(_fieldFinder('端口'), 'abc');
    await tester.tap(find.widgetWithText(SwitchListTile, 'SSL'));
    await tester.pump();
    expect(
      controller.data.notifications.of(NotifyChannel.email).useSsl,
      isFalse,
    );
    expect(_switch(tester, 'SSL').value, isFalse);
    expect(_field(tester, '端口').decoration!.errorText, '端口必须是数字');
  });

  testWidgets('完成 with a non-numeric 端口 stays open and does not patch', (
    tester,
  ) async {
    await _tall(tester);
    final repository = _Repo();
    final controller = await _loaded(repository);
    await tester.pumpWidget(_modalApp(controller, NotifyChannel.email));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(_fieldFinder('端口'), 'abc');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.byType(NotifyChannelSheet), findsOneWidget);
    expect(controller.data.notifications.of(NotifyChannel.email).smtpPort, 587);
    expect(repository.saved, isEmpty);
    expect(_field(tester, '端口').decoration!.errorText, '端口必须是数字');
  });

  testWidgets(
    'showNotifyChannelSheet opens the modal; 关闭 and 完成 both dismiss',
    (tester) async {
      final controller = await _loaded(_Repo());
      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          darkTheme: OneTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showNotifyChannelSheet(
                  context: context,
                  controller: controller,
                  channel: NotifyChannel.webhook,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(NotifyChannelSheet), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(NotifyChannelSheet), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Webhook'), findsOneWidget);
      expect(_field(tester, 'URL').controller!.text, 'https://hook.example/n');
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(NotifyChannelSheet), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(NotifyChannelSheet), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byType(NotifyChannelSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sheet scrolls at 320dp and 200 percent text in both themes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final controller = await _loaded(_Repo());
      await tester.pumpWidget(
        MaterialApp(
          theme: OneTheme.light(),
          darkTheme: OneTheme.dark(),
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: NotifyChannelSheet(
                key: ObjectKey(controller),
                controller: controller,
                channel: NotifyChannel.email,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Email'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('完成'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('保存通知设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    '完成 commits the typed draft to the controller without saving, then dismisses',
    (tester) async {
      await _tall(tester);
      final repository = _Repo();
      final controller = await _loaded(repository);
      await tester.pumpWidget(_modalApp(controller, NotifyChannel.telegram));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(NotifyChannelSheet), findsOneWidget);
      expect(_field(tester, 'Bot token').controller!.text, 'bot:token');

      await tester.enterText(_fieldFinder('Bot token'), 'new-token');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byType(NotifyChannelSheet), findsNothing);
      expect(
        controller.data.notifications.of(NotifyChannel.telegram).botToken,
        'new-token',
      );
      expect(repository.saved, isEmpty);
      expect(controller.notifyAction.status, ActionStatus.idle);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('关闭 discards the typed draft and dismisses', (tester) async {
    await _tall(tester);
    final repository = _Repo();
    final controller = await _loaded(repository);
    await tester.pumpWidget(_modalApp(controller, NotifyChannel.telegram));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(NotifyChannelSheet), findsOneWidget);

    await tester.enterText(_fieldFinder('Bot token'), 'new-token');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(NotifyChannelSheet), findsNothing);
    expect(
      controller.data.notifications.of(NotifyChannel.telegram).botToken,
      'bot:token',
    );
    expect(repository.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Widget _modalApp(SettingsController controller, NotifyChannel channel) =>
    MaterialApp(
      theme: OneTheme.light(),
      darkTheme: OneTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showNotifyChannelSheet(
              context: context,
              controller: controller,
              channel: channel,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

Widget _app(SettingsController controller, NotifyChannel channel) =>
    MaterialApp(
      theme: OneTheme.light(),
      darkTheme: OneTheme.dark(),
      home: Scaffold(
        body: NotifyChannelSheet(
          // 同一用例里换通道再 pump 时必须换 State，草稿只在 initState 回填一次。
          key: ValueKey<NotifyChannel>(channel),
          controller: controller,
          channel: channel,
        ),
      ),
    );

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(const Size(600, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<SettingsController> _loaded(SettingsRepository repository) async {
  final controller = SettingsController(
    repository: repository,
    licenseStore: MemoryProductLicenseStore(),
    requestRegistry: RequestRegistry(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  return controller;
}

Finder _fieldFinder(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

TextField _field(WidgetTester tester, String label) =>
    tester.widget<TextField>(_fieldFinder(label));

List<String?> _labels(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .map((field) => field.decoration?.labelText)
    .toList(growable: false);

SwitchListTile _switch(WidgetTester tester, String title) =>
    tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title));

GlassActionButton _glass(WidgetTester tester, Key key) =>
    tester.widget<GlassActionButton>(find.byKey(key));

const NotificationSettings _seed = NotificationSettings(
  telegram: NotifyChannelSettings(
    enabled: true,
    botToken: 'bot:token',
    chatId: '100',
    adminId: '7',
    baseUrl: 'https://tg.example',
    proxy: 'socks5://proxy',
  ),
  email: NotifyChannelSettings(
    smtpHost: 'smtp.example',
    smtpPort: 587,
    useSsl: false,
    username: 'mailer',
    password: 'mail-secret',
    fromAddress: 'alerts@example.com',
    toAddresses: 'ops@example.com,noc@example.com',
  ),
  pushplus: NotifyChannelSettings(
    token: 'pp-token',
    topic: 'ops',
    pushChannel: 'wechat',
  ),
  webhook: NotifyChannelSettings(
    url: 'https://hook.example/n',
    secret: 'hook-secret',
  ),
);

final class _TestCall {
  const _TestCall(this.channel, this.settings);
  final NotifyChannel channel;
  final NotifyChannelSettings settings;
}

final class _Repo implements SettingsRepository {
  @override
  Future<GatewayUpdateApply> applyUpdate({
    RequestCancellation? cancellation,
  }) async => const GatewayUpdateApply(applied: false);

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<GatewayUpdate> checkUpdate({RequestCancellation? cancellation}) async {
    return const GatewayUpdate(available: false);
  }


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

  final List<NotificationSettings> saved = <NotificationSettings>[];
  final List<_TestCall> testCalls = <_TestCall>[];
  Completer<NotificationSettings>? saveGate;


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
  }) async => _seed;

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
  }) async => const SystemInfo(version: 'v9');

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
  }) {
    saved.add(notifications);
    final gate = saveGate;
    if (gate != null) return gate.future;
    return Future<NotificationSettings>.value(notifications);
  }

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
  }) async {
    testCalls.add(_TestCall(channel, settings));
  }
}
