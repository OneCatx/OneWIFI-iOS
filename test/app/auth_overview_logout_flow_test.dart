import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/app/android_oneims_shell.dart';
import 'package:onewifi_android/app/app.dart';
import 'package:onewifi_android/app/app_dependencies.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/session_state.dart';
import 'package:onewifi_android/design/widgets/glass_dialog.dart';
import 'package:onewifi_android/features/auth/presentation/login_screen.dart';
import '../support/fakes.dart';

void main() {
  testWidgets('app root applies the current One system bar style', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          brightness;
      final dependencies = AppDependencies(
        httpClient: FakeClient((_) async => _success(_loginData('unused'))),
        baseUrlStore: MemoryBaseUrlStore(Uri.parse('https://api.example.test')),
        tokenStore: MemoryTokenStore(),
      );
      await tester.pumpWidget(OneWifiApp(dependencies: dependencies));
      await tester.pump();

      final styles = tester
          .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byWidgetPredicate(
              (widget) => widget is AnnotatedRegion<SystemUiOverlayStyle>,
            ),
          )
          .map((region) => region.value);
      expect(
        styles.any(
          (style) =>
              style.statusBarColor == Colors.transparent &&
              style.systemNavigationBarColor == Colors.transparent,
        ),
        isTrue,
      );
      dependencies.dispose();
    }
  });

  testWidgets(
    'real transport login loads overview and remote logout failure still clears local session',
    (tester) async {
      final origin = Uri.parse('https://api.example.test');
      final password = _runtimeSecret(43, 3);
      final issuedToken = _runtimeSecret(79, 5);
      final tokenStore = MemoryTokenStore();
      var loginWasAnonymous = false;
      var overviewWasBearer = true;
      var logoutWasBearer = false;
      final client = FakeClient((request) async {
        switch (request.url.path) {
          case '/api/auth/login':
            loginWasAnonymous =
                request.method == 'POST' &&
                !request.headers.containsKey('authorization') &&
                !request.headers.containsKey('cookie') &&
                !request.headers.containsKey('x-csrf-token');
            final body = jsonDecode(await _requestBody(request));
            expect(body is Map<Object?, Object?>, isTrue);
            expect((body as Map<Object?, Object?>)['username'], 'admin');
            expect(body['password'] == password, isTrue);
            return _success(_loginData(issuedToken));
          case '/api/dashboard/host':
            overviewWasBearer =
                overviewWasBearer &&
                request.method == 'GET' &&
                request.headers['authorization'] == 'Bearer $issuedToken';
            return _success(_hostData());
          case '/api/dashboard/devices':
            overviewWasBearer =
                overviewWasBearer &&
                request.method == 'GET' &&
                request.headers['authorization'] == 'Bearer $issuedToken';
            return _success(_devicesData());
          case '/api/auth/logout':
            logoutWasBearer =
                request.method == 'POST' &&
                request.headers['authorization'] == 'Bearer $issuedToken';
            return _failure(
              503,
              code: 'unavailable',
              message: _runtimeSecret(67, 9),
            );
          default:
            throw StateError('Unexpected test route.');
        }
      });
      final dependencies = AppDependencies(
        httpClient: client,
        baseUrlStore: MemoryBaseUrlStore(origin),
        tokenStore: tokenStore,
      );

      await tester.pumpWidget(OneWifiApp(dependencies: dependencies));
      await tester.pump();
      await tester.enterText(find.byKey(LoginScreen.usernameFieldKey), 'admin');
      await tester.enterText(
        find.byKey(LoginScreen.passwordFieldKey),
        password,
      );
      await tester.tap(find.byKey(LoginScreen.signInTargetKey));
      await tester.pumpAndSettle();

      expect(loginWasAnonymous, isTrue);
      expect(overviewWasBearer, isTrue);
      expect(find.text('主机性能'), findsNothing);
      expect(find.text('主机'), findsOneWidget);
      expect(tokenStore.tokens[origin] == issuedToken, isTrue);

      await tester.tap(find.byKey(AndroidOneImsShell.logoutTargetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
      await tester.pumpAndSettle();

      expect(logoutWasBearer, isTrue);
      expect(find.byKey(LoginScreen.rootKey), findsOneWidget);
      expect(tokenStore.tokens.containsKey(origin), isFalse);
      expect(tokenStore.clearOrigins, <Uri>[origin]);
      dependencies.dispose();
    },
  );

  testWidgets(
    'app root disables splash only when reduced motion is requested',
    (tester) async {
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      for (final disabled in <bool>[false, true]) {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: disabled);
        final dependencies = AppDependencies(
          httpClient: FakeClient((_) async => _success(_loginData('unused'))),
          baseUrlStore: MemoryBaseUrlStore(
            Uri.parse('https://api.example.test'),
          ),
          tokenStore: MemoryTokenStore(),
        );
        await tester.pumpWidget(OneWifiApp(dependencies: dependencies));
        await tester.pump();

        final theme = Theme.of(tester.element(find.byKey(LoginScreen.rootKey)));
        expect(
          theme.splashFactory,
          disabled ? NoSplash.splashFactory : InkSparkle.splashFactory,
        );
        dependencies.dispose();
      }
    },
  );

  test('login never sends an old exact-origin bearer token', () async {
    final origin = Uri.parse('https://api.example.test');
    final oldToken = _runtimeSecret(73, 11);
    final newToken = _runtimeSecret(83, 13);
    final tokenStore = MemoryTokenStore(<Uri, String>{origin: oldToken});
    var anonymous = false;
    final dependencies = AppDependencies(
      httpClient: FakeClient((request) async {
        anonymous =
            request.url.path == '/api/auth/login' &&
            !request.headers.containsKey('authorization') &&
            !request.headers.containsKey('cookie');
        await _requestBody(request);
        return _success(_loginData(newToken));
      }),
      baseUrlStore: MemoryBaseUrlStore(origin),
      tokenStore: tokenStore,
    );

    await dependencies.sessionController.signIn(
      'admin',
      _runtimeSecret(41, 15),
    );

    expect(anonymous, isTrue);
    expect(dependencies.sessionController.state.status, SessionStatus.signedIn);
    expect(tokenStore.tokens[origin] == newToken, isTrue);
    dependencies.dispose();
  });

  test(
    'a current overview 401 expires the real session and clears token',
    () async {
      final origin = Uri.parse('https://api.example.test');
      final token = _runtimeSecret(89, 17);
      final tokenStore = MemoryTokenStore();
      final dependencies = AppDependencies(
        httpClient: FakeClient((request) async {
          if (request.url.path == '/api/auth/login') {
            await _requestBody(request);
            return _success(_loginData(token));
          }
          if (request.url.path == '/api/dashboard/host') {
            return _failure(
              401,
              code: 'unauthorized',
              message: _runtimeSecret(61, 19),
            );
          }
          return _success(_devicesData());
        }),
        baseUrlStore: MemoryBaseUrlStore(origin),
        tokenStore: tokenStore,
      );
      await dependencies.sessionController.signIn(
        'admin',
        _runtimeSecret(47, 21),
      );
      final overview = dependencies.createOverviewController();

      await overview.load();

      expect(
        dependencies.sessionController.state.status,
        SessionStatus.expired,
      );
      expect(tokenStore.tokens.containsKey(origin), isFalse);
      expect(
        dependencies.sessionController.state.failure?.message.contains(
          _runtimeSecret(61, 19),
        ),
        isFalse,
      );
      overview.dispose();
      dependencies.dispose();
    },
  );

  test('overview 403 remains a query failure without signing out', () async {
    final origin = Uri.parse('https://api.example.test');
    final token = _runtimeSecret(97, 23);
    final tokenStore = MemoryTokenStore();
    final dependencies = AppDependencies(
      httpClient: FakeClient((request) async {
        if (request.url.path == '/api/auth/login') {
          await _requestBody(request);
          return _success(_loginData(token));
        }
        return _failure(
          403,
          code: 'blocked_destination',
          message: _runtimeSecret(59, 25),
        );
      }),
      baseUrlStore: MemoryBaseUrlStore(origin),
      tokenStore: tokenStore,
    );
    await dependencies.sessionController.signIn(
      'admin',
      _runtimeSecret(49, 27),
    );
    final overview = dependencies.createOverviewController();

    await overview.load();

    expect(dependencies.sessionController.state.status, SessionStatus.signedIn);
    expect(overview.state.status, QueryStatus.failed);
    expect(tokenStore.tokens[origin] == token, isTrue);
    overview.dispose();
    dependencies.dispose();
  });
}

Future<String> _requestBody(http.BaseRequest request) async {
  return utf8.decode(await request.finalize().toBytes());
}

http.StreamedResponse _success(Object? data) =>
    _response(200, <String, Object?>{'data': data});

http.StreamedResponse _failure(
  int status, {
  required String code,
  required String message,
}) => _response(status, <String, Object?>{
  'error': <String, String>{'code': code, 'message': message},
});

http.StreamedResponse _response(int status, Object body) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    status,
  );
}

Map<String, Object?> _loginData(String token) => <String, Object?>{
  'user': <String, Object?>{'username': 'admin'},
  'csrf_token': _runtimeSecret(37, 29),
  'session_token': token,
  'expires_at': '2030-01-02T03:04:05Z',
  'authenticated': true,
  'status': 'ok',
};

Map<String, Object?> _hostData() => <String, Object?>{
  'host': <String, Object?>{
    'cpu_model': 'Qualcomm X75',
    'board_model': 'One Board',
    'memory_model': '',
    'disk_model': '',
  },
  'perf': <String, Object?>{
    'cpu_percent': 12.5,
    'memory_percent': 31.25,
    'memory_used_bytes': 4294967296,
    'memory_total_bytes': 8589934592,
    'disk_percent': 42.75,
    'disk_used_bytes': 12884901888,
    'disk_total_bytes': 34359738368,
    'net_rx_bps': 1024.5,
    'net_tx_bps': 512.25,
  },
};

List<Object?> _devicesData() => <Object?>[
  <String, Object?>{
    'id': 'demo-modem',
    'name': 'Demo modem',
    'device_type': 'pcie_ec20_ec25',
    'interface': '',
    'proxy_port': 0,
    'public_ip': '',
    'healthy': true,
    'operator': 'One Carrier',
    'signal_dbm': -73,
    'network_mode': 'LTE',
    'network_duplex': 'FDD',
    'vowifi_active': true,
    'vowifi_runtime': <String, Object?>{
      'device_id': 'demo-modem',
      'phase': 'ims_ready',
      'enabled': true,
      'active': true,
      'dataplane_mode': 'cellular',
      'iccid': _runtimeSecret(20, 31),
      'imsi': _runtimeSecret(15, 33),
      'sim_ready': true,
      'access_ready': true,
      'tunnel_ready': true,
      'ims_ready': true,
      'sms_ready': false,
      'reg_status': 1,
      'reg_status_text': 'registered',
      'network_mode': 'LTE',
      'local_phone': _runtimeSecret(13, 35),
      'phone_number_source': 'network',
      'last_error_class': '',
      'last_error': '',
      'last_reason': 'ready',
      'updated_at': '2026-01-01T00:00:00Z',
    },
    'network_connected': true,
    'model': 'EC25',
  },
];

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}
