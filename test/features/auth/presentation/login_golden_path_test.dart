import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/config/base_url_policy.dart';
import 'package:onewifi_android/core/config/base_url_store.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/security/secure_token_store.dart';
import 'package:onewifi_android/core/state/session_state.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import 'package:onewifi_android/features/auth/domain/session_user.dart';
import 'package:onewifi_android/features/auth/presentation/login_screen.dart';
import 'package:onewifi_android/features/auth/state/session_controller.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';

/// P2 登录黄金路径：成功签发会话 + 关键错误码映射到登录页文案。
void main() {
  testWidgets('golden path: valid credentials reach signedIn',
      (tester) async {
    final harness = _Harness();
    await harness.controller.bootstrap();
    await tester.pumpWidget(harness.widget());

    await tester.enterText(find.byKey(LoginScreen.hostFieldKey), '10.0.0.8');
    await tester.enterText(find.byKey(LoginScreen.portFieldKey), '6688');
    await tester.enterText(find.byKey(LoginScreen.usernameFieldKey), 'admin');
    await tester.enterText(
      find.byKey(LoginScreen.passwordFieldKey),
      _runtimeSecret(31, 3),
    );
    await tester.tap(find.byKey(LoginScreen.signInTargetKey));
    await tester.pumpAndSettle();

    expect(harness.repository.loginCount, 1);
    expect(harness.controller.state.status, SessionStatus.signedIn);
    expect(harness.controller.origin, Uri.parse('http://10.0.0.8:6688'));
    expect(harness.controller.state.failure, isNull);
  });

  testWidgets('invalid_credentials shows credential copy', (tester) async {
    await _expectLoginFailureCopy(
      tester,
      failure: const ApiFailure(
        ApiFailureKind.http,
        requestId: 'local-invalid-credentials',
        statusCode: 401,
        backendCode: 'invalid_credentials',
      ),
      expected: '用户名或密码错误。',
    );
  });

  testWidgets('unauthorized shows session-expired copy', (tester) async {
    await _expectLoginFailureCopy(
      tester,
      failure: const ApiFailure(
        ApiFailureKind.http,
        requestId: 'local-unauthorized',
        statusCode: 401,
        backendCode: 'unauthorized',
      ),
      expected: '登录已失效，请重新登录。',
    );
  });

  testWidgets('invalid_csrf shows session re-login copy', (tester) async {
    await _expectLoginFailureCopy(
      tester,
      failure: const ApiFailure(
        ApiFailureKind.http,
        requestId: 'local-invalid-csrf',
        statusCode: 403,
        backendCode: 'invalid_csrf',
      ),
      expectedSubstring: '会话校验失败',
    );
  });

  testWidgets('network_access_denied keeps intranet policy copy',
      (tester) async {
    await _expectLoginFailureCopy(
      tester,
      failure: const ApiFailure(
        ApiFailureKind.http,
        requestId: 'local-network-access-denied',
        statusCode: 403,
        backendCode: 'network_access_denied',
      ),
      expectedSubstring: '只允许内网登录',
      forbiddenExact: '没有权限执行此操作。',
    );
  });

  testWidgets('https_required shows HTTPS requirement copy', (tester) async {
    // Origin already https so login_screen will not auto-retry upgrade.
    await _expectLoginFailureCopy(
      tester,
      origin: Uri.parse('https://192.168.1.88:6688'),
      failure: const ApiFailure(
        ApiFailureKind.http,
        requestId: 'local-https-required',
        statusCode: 403,
        backendCode: 'https_required',
      ),
      expected: '这台主机要求走 HTTPS，把登录页的 HTTPS 打开。',
    );
  });
}

Future<void> _expectLoginFailureCopy(
  WidgetTester tester, {
  required ApiFailure failure,
  Uri? origin,
  String? expected,
  String? expectedSubstring,
  String? forbiddenExact,
}) async {
  final harness = _Harness(
    origin: origin,
    loginHandler: (_) async => throw failure,
  );
  await harness.controller.bootstrap();
  await tester.pumpWidget(harness.widget());
  await tester.enterText(find.byKey(LoginScreen.usernameFieldKey), 'admin');
  await tester.enterText(
    find.byKey(LoginScreen.passwordFieldKey),
    _runtimeSecret(31, 3),
  );
  await tester.tap(find.byKey(LoginScreen.signInTargetKey));
  await tester.pumpAndSettle();

  expect(harness.controller.state.status, SessionStatus.failed);
  if (expected != null) {
    expect(find.text(expected), findsOneWidget);
  }
  if (expectedSubstring != null) {
    expect(find.textContaining(expectedSubstring), findsOneWidget);
  }
  if (forbiddenExact != null) {
    expect(find.text(forbiddenExact), findsNothing);
  }
}

final class _Harness {
  _Harness({
    Uri? origin,
    Future<SessionUser> Function(String username)? loginHandler,
  }) : origin = origin ?? BaseUrlPolicy.defaultOrigin,
       tokenStore = _TokenStore(),
       registry = RequestRegistry() {
    baseUrlStore = _BaseUrlStore(this.origin);
    repository = _AuthRepository(loginHandler: loginHandler);
    controller = SessionController(
      repository: repository,
      tokenStore: tokenStore,
      baseUrlStore: baseUrlStore,
      requestRegistry: registry,
    );
  }

  final Uri origin;
  final _TokenStore tokenStore;
  late final _BaseUrlStore baseUrlStore;
  final RequestRegistry registry;
  late final _AuthRepository repository;
  late final SessionController controller;

  Widget widget() {
    return MaterialApp(
      theme: OneTheme.light(),
      home: LoginScreen(
        controller: controller,
        readLicense: () async => const ProductLicense(
          key: 'AB12-CD34-EF56-GH78',
          activated: true,
        ),
      ),
    );
  }
}

final class _AuthRepository implements AuthRepository {
  _AuthRepository({this.loginHandler});

  final Future<SessionUser> Function(String username)? loginHandler;
  int loginCount = 0;

  @override
  Future<SessionUser> login(String username, String password) async {
    loginCount += 1;
    return loginHandler?.call(username) ??
        Future<SessionUser>.value(SessionUser(username));
  }

  @override
  Future<SessionUser> restore({RequestCancellation? cancellation}) async {
    return SessionUser('admin');
  }

  @override
  Future<void> logout() async {}
}

final class _TokenStore implements TokenStore {
  @override
  Future<String?> read(Uri origin) async => null;

  @override
  Future<void> write(Uri origin, String token) async {}

  @override
  Future<void> clear(Uri origin) async {}

  @override
  Future<void> clearAll() async {}
}

final class _BaseUrlStore implements BaseUrlStore {
  _BaseUrlStore(this.origin);

  Uri origin;

  @override
  Future<Uri> read() async => origin;

  @override
  Future<void> write(Uri origin) async {
    this.origin = origin;
  }
}

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}
