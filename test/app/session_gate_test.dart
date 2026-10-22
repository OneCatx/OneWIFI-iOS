import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/app/android_oneims_shell.dart';
import 'package:onewifi_android/app/appearance_controller.dart';
import 'package:onewifi_android/app/session_gate.dart';
import 'package:onewifi_android/core/config/base_url_store.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/security/secure_token_store.dart';
import 'package:onewifi_android/core/state/session_state.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/glass_dock.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import 'package:onewifi_android/features/auth/domain/session_user.dart';
import 'package:onewifi_android/features/auth/presentation/login_screen.dart';
import 'package:onewifi_android/features/auth/state/session_controller.dart';
import 'package:onewifi_android/features/calls/data/call_handset.dart';
import 'package:onewifi_android/features/calls/data/calls_repository.dart';
import 'package:onewifi_android/features/calls/domain/call.dart';
import 'package:onewifi_android/features/calls/state/calls_controller.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';
import 'package:onewifi_android/features/devices/domain/device.dart'
    hide DeviceRuntimePhase;
import 'package:onewifi_android/features/devices/state/device_detail_controller.dart';
import 'package:onewifi_android/features/devices/state/device_list_controller.dart';
import 'package:onewifi_android/features/esim/data/esim_repository.dart';
import 'package:onewifi_android/features/esim/domain/card_policy.dart';
import 'package:onewifi_android/features/esim/domain/esim.dart';
import 'package:onewifi_android/features/esim/state/esim_controller.dart';
import 'package:onewifi_android/features/overview/data/overview_repository.dart';
import 'package:onewifi_android/features/overview/domain/overview.dart';
import 'package:onewifi_android/features/overview/state/overview_controller.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_backend_store.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_client.dart';
import 'package:onewifi_android/features/proxy/data/proxy_repository.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_call_connection.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_call_group.dart';
import 'package:onewifi_android/features/proxy/state/mihomo_connection_controller.dart';
import 'package:onewifi_android/features/proxy/state/proxy_controller.dart';
import 'package:onewifi_android/features/sms/data/sms_repository.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/state/sms_controller.dart';
import '../support/fakes.dart';

void main() {
  testWidgets('booting never shows a business dock', (tester) async {
    final semantics = tester.ensureSemantics();
    final originRead = Completer<Uri>();
    final harness = _Harness(
      baseUrlStore: _BaseUrlStore(read: originRead.future),
    );

    await tester.pumpWidget(harness.widget());

    expect(harness.session.state.status, SessionStatus.booting);
    expect(find.byKey(SessionGate.bootingKey), findsOneWidget);
    expect(find.byType(GlassDock), findsNothing);
    expect(find.bySemanticsLabel('正在恢复 OneWIFI 会话'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('signedOut never shows a business dock', (tester) async {
    final harness = _Harness();

    await tester.pumpWidget(harness.widget());
    await tester.pump();

    expect(harness.session.state.status, SessionStatus.signedOut);
    expect(find.byKey(LoginScreen.rootKey), findsOneWidget);
    expect(find.byType(GlassDock), findsNothing);
  });

  testWidgets('signingIn keeps the login shell and has no business dock', (
    tester,
  ) async {
    final loginResult = Completer<SessionUser>();
    final harness = _Harness(
      authRepository: _AuthRepository(login: loginResult.future),
    );
    await tester.pumpWidget(harness.widget());
    await tester.pump();
    await tester.enterText(find.byKey(LoginScreen.usernameFieldKey), 'admin');
    await tester.enterText(
      find.byKey(LoginScreen.passwordFieldKey),
      _runtimeSecret(31, 3),
    );

    await tester.tap(find.byKey(LoginScreen.signInTargetKey));
    await tester.pump();

    expect(harness.session.state.status, SessionStatus.signingIn);
    expect(find.byKey(LoginScreen.rootKey), findsOneWidget);
    expect(find.text('正在登录…'), findsOneWidget);
    expect(find.byType(GlassDock), findsNothing);
  });

  testWidgets('invalid login submit focuses the first invalid field', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.widget());
    await tester.pump();

    await tester.tap(find.byKey(LoginScreen.signInTargetKey));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(LoginScreen.usernameFieldKey),
              matching: find.byType(TextField),
            ),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );

    await tester.enterText(find.byKey(LoginScreen.usernameFieldKey), 'admin');
    await tester.tap(find.byKey(LoginScreen.signInTargetKey));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(LoginScreen.passwordFieldKey),
              matching: find.byType(TextField),
            ),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
  });

  testWidgets('expired and failed branches expose recovery without a dock', (
    tester,
  ) async {
    final pendingToken = Completer<String?>();
    final expired = _Harness(
      tokenStore: _TokenStore(read: pendingToken.future),
    );
    await tester.pumpWidget(expired.widget());
    await expired.session.expireIfCurrent(0);
    await tester.pump();

    expect(expired.session.state.status, SessionStatus.expired);
    expect(find.text('登录已过期，请重新登录'), findsOneWidget);
    expect(find.byKey(LoginScreen.signInTargetKey), findsOneWidget);
    expect(find.byType(GlassDock), findsNothing);

    final failed = _Harness(
      baseUrlStore: _BaseUrlStore(
        readFailure: StateError('storage unavailable'),
      ),
    );
    await tester.pumpWidget(failed.widget());
    await tester.pump();

    expect(failed.session.state.status, SessionStatus.failed);
    expect(find.text('出了点问题。'), findsOneWidget);
    expect(find.byKey(LoginScreen.retryTargetKey), findsOneWidget);
    expect(find.byType(GlassDock), findsNothing);
  });

  testWidgets(
    'signedIn shows the real overview, devices, SMS, proxy, calls, and settings destinations',
    (tester) async {
      final harness = _Harness.signedIn();

      await tester.pumpWidget(harness.widget());
      await tester.pumpAndSettle();

      expect(harness.session.state.status, SessionStatus.signedIn);
      expect(find.byKey(AndroidOneImsShell.rootKey), findsOneWidget);
      expect(find.byType(GlassDock), findsOneWidget);
      expect(
        tester
            .widget<GlassDock>(find.byType(GlassDock))
            .destinations
            .map((destination) => destination.label),
        <String>['仪表盘', '设备', '短信', '代理', '通话', '设置'],
      );
      expect(find.text('刷新'), findsNothing);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.text('主机'), findsOneWidget);
      expect(find.byKey(LoginScreen.rootKey), findsNothing);

      await tester.tap(find.byKey(GlassDock.targetKey(2)));
      await tester.pumpAndSettle();
      expect(find.text('短信检测'), findsOneWidget);
      expect(find.text('没有短信联系人'), findsOneWidget);

      await tester.tap(find.byKey(GlassDock.targetKey(3)));
      await tester.pumpAndSettle();
      expect(find.text('还没连 Mihomo'), findsOneWidget);

      await tester.tap(find.byKey(GlassDock.targetKey(4)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calls-screen')), findsOneWidget);

      await tester.tap(find.byKey(AndroidOneImsShell.settingsTargetKey));
      await tester.pumpAndSettle();
      expect(find.text('系统设置'), findsOneWidget);
      expect(find.text('Mihomo'), findsOneWidget);
      expect(find.text('通知'), findsNothing);
      expect(find.text('登录与访问'), findsNothing);
      await tester.ensureVisible(find.text('浅色'));
      expect(find.text('浅色'), findsOneWidget);
    },
  );

  testWidgets(
    'device list belongs to one signed-in epoch and is disposed on exit',
    (tester) async {
      final repository = _BlockingDeviceRepository();
      final harness = _Harness.signedIn(deviceRepository: repository);

      await tester.pumpWidget(harness.widget());
      await tester.pumpAndSettle();
      expect(harness.deviceLists, hasLength(1));

      await tester.tap(find.byKey(GlassDock.targetKey(1)));
      await tester.pump();
      expect(repository.listCancellation, isNotNull);

      await harness.session.signOut();
      await tester.pump();
      expect(repository.listCancellation!.isCancelled, isTrue);
      expect(
        () => harness.deviceLists.single.addListener(() {}),
        throwsFlutterError,
      );
      expect(find.byType(GlassDock), findsNothing);
    },
  );

  testWidgets('dependency replacement disposes old signed-in owners', (
    tester,
  ) async {
    final oldRepository = _BlockingDeviceRepository();
    final oldHarness = _Harness.signedIn(deviceRepository: oldRepository);
    await tester.pumpWidget(oldHarness.widget());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GlassDock.targetKey(1)));
    await tester.pump();
    expect(oldRepository.listCancellation, isNotNull);

    final replacement = _Harness.signedIn();
    await tester.pumpWidget(replacement.widget());
    await tester.pumpAndSettle();

    expect(oldRepository.listCancellation!.isCancelled, isTrue);
    expect(
      () => oldHarness.deviceLists.single.addListener(() {}),
      throwsFlutterError,
    );
    expect(replacement.deviceLists, hasLength(1));
    expect(find.byType(GlassDock), findsOneWidget);
  });

  testWidgets('the current Overview dock target refreshes the real overview', (
    tester,
  ) async {
    final repository = _OverviewRepository();
    final harness = _Harness.signedIn(overviewRepository: repository);

    await tester.pumpWidget(harness.widget());
    await tester.pumpAndSettle();
    expect(repository.hostFetches, 1);
    expect(repository.deviceFetches, 1);

    await tester.tap(find.byKey(GlassDock.overviewTargetKey));
    await tester.pumpAndSettle();

    expect(repository.hostFetches, 2);
    expect(repository.deviceFetches, 2);
  });

  testWidgets('leaving a signed-in session cancels overview reads', (
    tester,
  ) async {
    final repository = _BlockingOverviewRepository();
    final harness = _Harness.signedIn(overviewRepository: repository);

    await tester.pumpWidget(harness.widget());
    await tester.pump();
    expect(repository.hostCancellation, isNotNull);
    expect(repository.devicesCancellation, isNotNull);

    await harness.session.signOut();
    await tester.pump();

    expect(repository.hostCancellation!.isCancelled, isTrue);
    expect(repository.devicesCancellation!.isCancelled, isTrue);
    expect(find.byKey(LoginScreen.rootKey), findsOneWidget);

    repository.host.complete(_host());
    repository.devices.complete(<DeviceOverview>[_device()]);
    await tester.pump();
    expect(find.byKey(LoginScreen.rootKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'current-epoch expiry cancels pending reads and late responses stay out of the next session',
    (tester) async {
      final repository = _EpochBlockingOverviewRepository();
      final harness = _Harness.signedIn(overviewRepository: repository);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      expect(repository.hostCancellations, hasLength(1));
      expect(repository.devicesCancellations, hasLength(1));
      await harness.session.expireIfCurrent(harness.session.sessionEpoch);
      await tester.pump();

      expect(harness.session.state.status, SessionStatus.expired);
      expect(repository.hostCancellations.single!.isCancelled, isTrue);
      expect(repository.devicesCancellations.single!.isCancelled, isTrue);
      expect(find.byKey(LoginScreen.rootKey), findsOneWidget);

      await harness.session.signIn('admin', _runtimeSecret(29, 11));
      await tester.pump();
      await tester.pump();
      expect(harness.session.state.status, SessionStatus.signedIn);
      expect(repository.hostCancellations, hasLength(2));
      expect(repository.devicesCancellations, hasLength(2));

      repository.hostResults.first.complete(_host());
      repository.devicesResults.first.complete(<DeviceOverview>[_device()]);
      await tester.pump();
      expect(find.text('正在加载概览'), findsOneWidget);
      expect(find.text('主机'), findsNothing);

      repository.hostResults[1].complete(_host());
      repository.devicesResults[1].complete(<DeviceOverview>[_device()]);
      await tester.pumpAndSettle();
      expect(find.byKey(AndroidOneImsShell.rootKey), findsOneWidget);
      expect(find.text('主机'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('signed-in shell fits a real 320dp surface at text scale 2', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() {
      FlutterError.onError = originalOnError;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final harness = _Harness.signedIn(
        overviewRepository: _OverviewRepository(
          devices: <DeviceOverview>[
            _device(
              name: 'Long safe device label for narrow text scaling coverage',
            ),
            _device(
              name: 'Second safe device with an equally descriptive label',
            ),
          ],
        ),
      );
      await tester.pumpWidget(harness.widget(brightness: brightness));
      await tester.pumpAndSettle();

      expect(find.byKey(AndroidOneImsShell.rootKey), findsOneWidget);
      expect(find.byType(GlassDock), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    FlutterError.onError = originalOnError;
    expect(
      errors.where(
        (details) => details.exceptionAsString().contains('overflowed'),
      ),
      isEmpty,
    );
  });
}

final class _Harness {
  _Harness({
    BaseUrlStore? baseUrlStore,
    AuthRepository? authRepository,
    TokenStore? tokenStore,
    OverviewRepository? overviewRepository,
    DeviceRepository? deviceRepository,
  }) : registry = RequestRegistry(),
       appearance = AppearanceController(),
       baseUrlStore = baseUrlStore ?? _BaseUrlStore(),
       tokenStore = tokenStore ?? _TokenStore(),
       authRepository = authRepository ?? _AuthRepository(),
       overviewRepository = overviewRepository ?? _OverviewRepository(),
       deviceRepository = deviceRepository ?? _DeviceRepository() {
    session = SessionController(
      repository: this.authRepository,
      tokenStore: this.tokenStore,
      baseUrlStore: this.baseUrlStore,
      requestRegistry: registry,
    );
  }

  factory _Harness.signedIn({
    OverviewRepository? overviewRepository,
    DeviceRepository? deviceRepository,
  }) {
    return _Harness(
      tokenStore: _TokenStore(token: _runtimeSecret(53, 7)),
      authRepository: _AuthRepository(
        restore: Future<SessionUser>.value(SessionUser('admin')),
      ),
      overviewRepository: overviewRepository,
      deviceRepository: deviceRepository,
    );
  }

  final RequestRegistry registry;
  final AppearanceController appearance;
  final BaseUrlStore baseUrlStore;
  final TokenStore tokenStore;
  final AuthRepository authRepository;
  final OverviewRepository overviewRepository;
  final DeviceRepository deviceRepository;
  final List<DeviceListController> deviceLists = <DeviceListController>[];
  late final SessionController session;

  Widget widget({
    Brightness brightness = Brightness.light,
    MediaQueryData? media,
  }) {
    final gate = SessionGate(
      sessionController: session,
      overviewControllerFactory: () => OverviewController(
        repository: overviewRepository,
        requestRegistry: registry,
      ),
      deviceListControllerFactory: () {
        final controller = DeviceListController(
          repository: deviceRepository,
          requestRegistry: registry,
        );
        deviceLists.add(controller);
        return controller;
      },
      deviceDetailControllerFactory: (deviceId) => DeviceDetailController(
        deviceId: deviceId,
        repository: deviceRepository,
        requestRegistry: registry,
      ),
      esimControllerFactory: (deviceId) => EsimController(
        deviceId: deviceId,
        repository: const _EsimRepository(),
        requestRegistry: registry,
      ),
      callsControllerFactory: () => CallsController(
        repository: const _CallsRepository(),
        originProvider: () async => Uri.parse('http://127.0.0.1:6688'),
        tokenProvider: (_) async => null,
        requestRegistry: registry,
        handset: SilentCallHandset(),
      ),
      smsControllerFactory: () => SmsController(
        repository: const _SmsRepository(),
        requestRegistry: registry,
      ),
      proxyControllerFactory: () => ProxyController(
        repository: const _ProxyRepository(),
        requestRegistry: registry,
        backendStore: MemoryMihomoBackendStore(),
      ),
      mihomoConnectionControllerFactory: () => MihomoConnectionController(
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
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }),
          originProvider: () async => Uri.parse('http://unused.test:9090'),
        ),
        requestRegistry: registry,
      ),
      appearance: appearance,
    );
    return MaterialApp(
      theme: OneTheme.light(),
      darkTheme: OneTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: media == null ? gate : MediaQuery(data: media, child: gate),
    );
  }
}

final class _DeviceRepository implements DeviceRepository {
  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) async {
    return DeviceFleet(deviceLimit: 4, devices: const <DeviceSnapshot>[]);
  }

  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) => throw StateError('No device is selected in this harness.');

  @override
  Future<void> setCapability({
    required String deviceId,
    required DeviceCapability capability,
    required bool enabled,
    RequestCancellation? cancellation,
  }) => throw StateError('No device write expected.');

  @override
  Future<void> reconnectVowifi(
    String deviceId, {
    RequestCancellation? cancellation,
  }) => throw StateError('No device write expected.');

  @override
  Future<void> reboot(String deviceId, {RequestCancellation? cancellation}) =>
      throw StateError('No device write expected.');
  @override
  Future<List<DiscoveredDevice>> fetchDiscoveredDevices({
    RequestCancellation? cancellation,
  }) async => const <DiscoveredDevice>[];

  @override
  Future<DeviceRescanResult> rescanDevices({
    RequestCancellation? cancellation,
  }) async => const DeviceRescanResult(status: 'ok', devicesCount: 0);

  @override
  Future<void> registerDevice({
    required String deviceId,
    required String discoveryKey,
    required String deviceType,
    String? name,
    String? simPin,
    Map<String, Object?>? additionalConfig,
    RequestCancellation? cancellation,
  }) async {}
}

final class _EsimRepository implements EsimRepository {
  const _EsimRepository();

  @override
  Future<EsimInventory> fetchProfiles(
    String deviceId, {
    required bool refresh,
    RequestCancellation? cancellation,
  }) async => EsimInventory(
    hint: EsimInventoryHint.none,
    profiles: const <EsimProfile>[],
  );

  @override
  Future<EsimSwitchResult> switchProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) => throw StateError('No eSIM switch expected.');

  @override
  Future<CardPolicy> fetchPolicy(
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async => const CardPolicy(apn: '', ipVersion: CardIpVersion.ipv4v6);

  @override
  Future<CardPolicy> savePolicy(
    EsimSwitchTarget target, {
    required String apn,
    required CardIpVersion ipVersion,
    bool? networkEnabled,
    bool? vowifiEnabled,
    bool? airplaneEnabled,
    String? mbnProfile,
    CardVoicePath? voicePath,
    RequestCancellation? cancellation,
  }) => throw StateError('No card policy write expected.');

  @override
  Future<void> downloadProfile(
    String deviceId, {
    required String smdp,
    String matchingId = '',
    String confirmationCode = '',
    String aidHex = '',
    void Function(EsimDownloadProgress progress)? onProgress,
    RequestCancellation? cancellation,
  }) => throw StateError('No eSIM download expected.');

  @override
  Future<void> renameProfile(
    String deviceId,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  }) => throw StateError('No eSIM rename expected.');

  @override
  Future<void> disableProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) => throw StateError('No eSIM disable expected.');

  @override
  Future<void> deleteProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) => throw StateError('No eSIM delete expected.');

  @override
  String aidHexOf(EsimSwitchTarget target) => '';
}

final class _ProxyRepository implements ProxyRepository {
  const _ProxyRepository();

  @override
  Future<List<WifiCallGroup>> fetchWifiCallGroups({
    RequestCancellation? cancellation,
  }) async => const <WifiCallGroup>[];

  @override
  Future<List<WifiCallConnection>> fetchConnections({
    RequestCancellation? cancellation,
    List<WifiCallConnection>? previous,
    DateTime? previousAt,
    DateTime? now,
  }) async => const <WifiCallConnection>[];

  @override
  Future<void> selectNode({
    required String group,
    required String name,
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<WifiDelay> probeDelay({
    required String name,
    String? altName,
    RequestCancellation? cancellation,
  }) async => const WifiDelay.unknown();

  @override
  Future<Map<String, WifiDelay>?> probeGroupDelay({
    required String name,
    RequestCancellation? cancellation,
  }) async => null;
}

final class _CallsRepository implements CallsRepository {
  const _CallsRepository();

  @override
  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async => const <VoiceCall>[];

  @override
  Future<VoiceCall> dial(
    String deviceId,
    String number, {
    RequestCancellation? cancellation,
  }) async => VoiceCall(
    id: '1',
    deviceId: deviceId,
    number: number,
    direction: CallDirection.outgoing,
    state: CallLifecycle.dialing,
  );

  @override
  Future<VoiceCall> answer(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async => VoiceCall(
    id: callId,
    deviceId: deviceId,
    number: '',
    direction: CallDirection.incoming,
    state: CallLifecycle.active,
  );

  @override
  Future<void> hangup(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<CallMediaMeta> fetchMediaMeta(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async => CallMediaMeta(
    id: callId,
    codec: '',
    format: 'pcm_s16le_8000_mono',
    stream: '',
  );

  
  @override
  Future<void> sendDtmf(
    String deviceId,
    String callId, {
    String? digit,
    String? digits,
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<CallMediaTicket> createMediaTicket(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async => const CallMediaTicket(ticket: 't', expiresInSeconds: 60);

  @override
  Future<List<CallHistoryEntry>> fetchHistory(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async => const <CallHistoryEntry>[];

  @override
  Future<CallMediaCapabilities> fetchMediaCapabilities({
    RequestCancellation? cancellation,
  }) async => const CallMediaCapabilities(
        preferred: 'auto',
        webrtcEnabled: false,
        websocketEnabled: true,
      );
  @override
  Future<WebSocket> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  }) async {
    throw UnsupportedError('no media in test');
  }
}

class _SmsRepository implements SmsRepository {
  const _SmsRepository();

  @override
  Future<List<SmsContact>> fetchContacts({
    RequestCancellation? cancellation,
  }) async => const <SmsContact>[];

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) async => SmsThreadPage(messages: const <SmsMessage>[], hasMore: false);

  @override
  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) async => const SmsSendResult(
    outcome: SmsSendOutcome.delivered,
    partsTotal: 1,
    partsAccepted: 1,
    retrySafe: false,
  );

  @override
  Future<int> deleteThread(
    SmsContactTarget target, {
    RequestCancellation? cancellation,
  }) async => 0;

  @override
  Future<bool> deleteMessage(
    int messageId, {
    RequestCancellation? cancellation,
  }) async => true;
}

final class _BlockingDeviceRepository implements DeviceRepository {
  final Completer<DeviceFleet> list = Completer<DeviceFleet>();
  RequestCancellation? listCancellation;

  @override
  Future<DeviceFleet> fetchDevices({RequestCancellation? cancellation}) {
    listCancellation = cancellation;
    return list.future;
  }

  @override
  Future<DeviceDetail> fetchDeviceOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) => throw StateError('No device detail expected.');

  @override
  Future<void> setCapability({
    required String deviceId,
    required DeviceCapability capability,
    required bool enabled,
    RequestCancellation? cancellation,
  }) => throw StateError('No device write expected.');

  @override
  Future<void> reconnectVowifi(
    String deviceId, {
    RequestCancellation? cancellation,
  }) => throw StateError('No device write expected.');

  @override
  Future<void> reboot(String deviceId, {RequestCancellation? cancellation}) =>
      throw StateError('No device write expected.');
  @override
  Future<List<DiscoveredDevice>> fetchDiscoveredDevices({
    RequestCancellation? cancellation,
  }) async => const <DiscoveredDevice>[];

  @override
  Future<DeviceRescanResult> rescanDevices({
    RequestCancellation? cancellation,
  }) async => const DeviceRescanResult(status: 'ok', devicesCount: 0);

  @override
  Future<void> registerDevice({
    required String deviceId,
    required String discoveryKey,
    required String deviceType,
    String? name,
    String? simPin,
    Map<String, Object?>? additionalConfig,
    RequestCancellation? cancellation,
  }) async {}
}

final class _BaseUrlStore implements BaseUrlStore {
  factory _BaseUrlStore({Future<Uri>? read, Object? readFailure}) {
    return _BaseUrlStore._(
      read ?? Future<Uri>.value(Uri.parse('https://api.example.test')),
      readFailure,
    );
  }

  _BaseUrlStore._(this._read, this.readFailure);

  final Future<Uri> _read;
  final Object? readFailure;

  @override
  Future<Uri> read() {
    final failure = readFailure;
    return failure == null ? _read : Future<Uri>.error(failure);
  }

  @override
  Future<void> write(Uri origin) async {}
}

final class _TokenStore implements TokenStore {
  factory _TokenStore({String? token, Future<String?>? read}) {
    return _TokenStore._(token, read);
  }

  _TokenStore._(this.token, this._read);

  final String? token;
  final Future<String?>? _read;

  @override
  Future<void> clear(Uri origin) async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<String?> read(Uri origin) => _read ?? Future<String?>.value(token);

  @override
  Future<void> write(Uri origin, String token) async {}
}

final class _AuthRepository implements AuthRepository {
  factory _AuthRepository({
    Future<SessionUser>? login,
    Future<SessionUser>? restore,
  }) => _AuthRepository._(login, restore);

  _AuthRepository._(this._login, this._restore);

  final Future<SessionUser>? _login;
  final Future<SessionUser>? _restore;

  @override
  Future<SessionUser> login(String username, String password) {
    return _login ?? Future<SessionUser>.value(SessionUser(username));
  }

  @override
  Future<void> logout() async {}

  @override
  Future<SessionUser> restore({RequestCancellation? cancellation}) {
    return _restore ?? Future<SessionUser>.value(SessionUser('admin'));
  }
}

final class _OverviewRepository implements OverviewRepository {
  _OverviewRepository({List<DeviceOverview>? devices})
    : _devices = devices ?? <DeviceOverview>[_device()];

  final List<DeviceOverview> _devices;
  int hostFetches = 0;
  int deviceFetches = 0;

  @override
  Future<List<DeviceOverview>> fetchDevices({
    RequestCancellation? cancellation,
  }) async {
    deviceFetches += 1;
    return _devices;
  }

  @override
  Future<HostOverview> fetchHost({RequestCancellation? cancellation}) async {
    hostFetches += 1;
    return _host();
  }
}

final class _BlockingOverviewRepository implements OverviewRepository {
  final Completer<HostOverview> host = Completer<HostOverview>();
  final Completer<List<DeviceOverview>> devices =
      Completer<List<DeviceOverview>>();
  RequestCancellation? hostCancellation;
  RequestCancellation? devicesCancellation;

  @override
  Future<List<DeviceOverview>> fetchDevices({
    RequestCancellation? cancellation,
  }) {
    devicesCancellation = cancellation;
    return devices.future;
  }

  @override
  Future<HostOverview> fetchHost({RequestCancellation? cancellation}) {
    hostCancellation = cancellation;
    return host.future;
  }
}

final class _EpochBlockingOverviewRepository implements OverviewRepository {
  final List<Completer<HostOverview>> hostResults = <Completer<HostOverview>>[
    Completer<HostOverview>(),
    Completer<HostOverview>(),
  ];
  final List<Completer<List<DeviceOverview>>> devicesResults =
      <Completer<List<DeviceOverview>>>[
        Completer<List<DeviceOverview>>(),
        Completer<List<DeviceOverview>>(),
      ];
  final List<RequestCancellation?> hostCancellations = <RequestCancellation?>[];
  final List<RequestCancellation?> devicesCancellations =
      <RequestCancellation?>[];

  @override
  Future<List<DeviceOverview>> fetchDevices({
    RequestCancellation? cancellation,
  }) {
    devicesCancellations.add(cancellation);
    return devicesResults[devicesCancellations.length - 1].future;
  }

  @override
  Future<HostOverview> fetchHost({RequestCancellation? cancellation}) {
    hostCancellations.add(cancellation);
    return hostResults[hostCancellations.length - 1].future;
  }
}

HostOverview _host() => const HostOverview(
  cpuModel: 'Qualcomm X75',
  boardModel: 'One Board',
  cpuPercent: 12.5,
  memoryPercent: 31.25,
  memoryUsedBytes: 4294967296,
  memoryTotalBytes: 8589934592,
  diskPercent: 42.75,
  diskUsedBytes: 12884901888,
  diskTotalBytes: 34359738368,
  netRxBps: 1024.5,
  netTxBps: 512.25,
);

DeviceOverview _device({String name = 'Demo modem'}) => DeviceOverview(
  id: name == 'Demo modem' ? 'demo-modem' : 'safe-modem',
  name: name,
  model: 'EC25',
  type: 'pcie_ec20_ec25',
  healthy: true,
  operatorName: 'One Carrier',
  signalDbm: -73,
  networkMode: 'LTE',
  vowifiActive: true,
  networkConnected: true,
  runtime: DeviceRuntimeOverview(
    phase: DeviceRuntimePhase.imsReady,
    simReady: true,
    accessReady: true,
    tunnelReady: true,
    imsReady: true,
    smsReady: false,
  ),
);

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}
