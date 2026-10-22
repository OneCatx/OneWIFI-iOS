import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/config/base_url_policy.dart';
import 'package:onewifi_android/core/config/base_url_store.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/security/secure_token_store.dart';
import 'package:onewifi_android/core/state/session_state.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/choice_toggle.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import 'package:onewifi_android/features/auth/domain/session_user.dart';
import 'package:onewifi_android/features/auth/presentation/login_screen.dart';
import 'package:onewifi_android/features/auth/state/session_controller.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';

void main() {
  testWidgets('login prefills host and port from the stored origin', (
    tester,
  ) async {
    final origin = Uri.parse('http://192.168.10.20:6688');
    final harness = _Harness(origin: origin);
    await harness.controller.bootstrap();

    await tester.pumpWidget(harness.widget());

    expect(
      tester
          .widget<TextFormField>(find.byKey(LoginScreen.hostFieldKey))
          .controller
          ?.text,
      '192.168.10.20',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(LoginScreen.portFieldKey))
          .controller
          ?.text,
      '6688',
    );
  });

  testWidgets('sign-in persists a different host and port before login', (
    tester,
  ) async {
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

    expect(harness.baseUrlStore.origin, Uri.parse('http://10.0.0.8:6688'));
    expect(harness.controller.origin, Uri.parse('http://10.0.0.8:6688'));
    expect(harness.repository.loginCount, 1);
  });

  testWidgets('sign-in accepts a public HTTP NPS host and port', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.controller.bootstrap();
    await tester.pumpWidget(harness.widget());

    await tester.enterText(find.byKey(LoginScreen.hostFieldKey), '8.8.8.8');
    await tester.enterText(find.byKey(LoginScreen.portFieldKey), '1688');
    await tester.enterText(find.byKey(LoginScreen.usernameFieldKey), 'admin');
    await tester.enterText(
      find.byKey(LoginScreen.passwordFieldKey),
      _runtimeSecret(31, 3),
    );
    await tester.ensureVisible(find.byKey(LoginScreen.signInTargetKey));
    await tester.tap(find.byKey(LoginScreen.signInTargetKey));
    await tester.pumpAndSettle();

    expect(harness.baseUrlStore.origin, Uri.parse('http://8.8.8.8:1688'));
    expect(harness.repository.loginCount, 1);
    expect(find.textContaining('公网明文 HTTP'), findsOneWidget);
  });

  testWidgets('failed sign-in shows the network failure copy', (tester) async {
    final harness = _Harness(
      loginHandler: (_) async {
        throw const ApiFailure(
          ApiFailureKind.network,
          requestId: 'local-network-failure',
        );
      },
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

    expect(find.text('无法连接到服务。'), findsOneWidget);
  });

  testWidgets('sign-in 403 for internal-only access explains the policy', (
    tester,
  ) async {
    final harness = _Harness(
      loginHandler: (_) async {
        throw const ApiFailure(
          ApiFailureKind.http,
          requestId: 'local-login-forbidden',
          statusCode: 403,
          backendCode: 'network_access_denied',
        );
      },
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

    expect(find.text('没有权限执行此操作。'), findsNothing);
    expect(find.textContaining('只允许内网登录'), findsOneWidget);
  });

  testWidgets('http 403 invalid_redirect_host retries over https', (
    tester,
  ) async {
    late final _Harness harness;
    harness = _Harness(
      origin: Uri.parse('http://8.137.155.86:6688'),
      loginHandler: (_) async {
        if (harness.controller.origin.scheme != 'https') {
          throw const ApiFailure(
            ApiFailureKind.http,
            requestId: 'local-invalid-redirect-host',
            statusCode: 403,
            backendCode: 'invalid_redirect_host',
          );
        }
        return SessionUser('admin');
      },
    );
    await harness.controller.bootstrap();
    await tester.pumpWidget(harness.widget());
    await tester.enterText(find.byKey(LoginScreen.usernameFieldKey), 'admin');
    await tester.enterText(
      find.byKey(LoginScreen.passwordFieldKey),
      _runtimeSecret(31, 3),
    );
    await tester.ensureVisible(find.byKey(LoginScreen.signInTargetKey));
    await tester.tap(find.byKey(LoginScreen.signInTargetKey));
    await tester.pumpAndSettle();

    expect(harness.repository.loginCount, 2);
    expect(harness.controller.origin, Uri.parse('https://8.137.155.86:6688'));
    expect(harness.controller.state.status, SessionStatus.signedIn);
    expect(
      tester.widget<ChoiceToggle>(find.byKey(LoginScreen.httpsSwitchKey)).value,
      isTrue,
    );
    expect(find.text('没有权限执行此操作。'), findsNothing);
  });

  testWidgets('http 403 https_required retries over https', (tester) async {
    late final _Harness harness;
    harness = _Harness(
      origin: Uri.parse('http://192.168.1.88:6688'),
      loginHandler: (_) async {
        if (harness.controller.origin.scheme != 'https') {
          throw const ApiFailure(
            ApiFailureKind.http,
            requestId: 'local-https-required',
            statusCode: 403,
            backendCode: 'https_required',
          );
        }
        return SessionUser('admin');
      },
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

    expect(harness.controller.origin.scheme, 'https');
    expect(harness.controller.state.status, SessionStatus.signedIn);
    expect(harness.repository.loginCount, 2);
  });

  testWidgets(
    'first login shows the license code and binds it before sign-in',
    (tester) async {
      final harness = _Harness();
      await harness.controller.bootstrap();
      var bound = '';
      await tester.pumpWidget(
        harness.widget(
          readLicense: () async => const ProductLicense(),
          bindLicense: (code) async {
            bound = code;
            return const ProductLicense(
              key: 'AB12-CD34-EF56-GH78',
              activated: true,
            );
          },
        ),
      );
      await tester.pump();
      expect(find.byKey(LoginScreen.licenseFieldKey), findsOneWidget);
      await tester.enterText(find.byKey(LoginScreen.usernameFieldKey), 'admin');
      await tester.enterText(
        find.byKey(LoginScreen.passwordFieldKey),
        _runtimeSecret(31, 3),
      );
      await tester.enterText(
        find.byKey(LoginScreen.licenseFieldKey),
        'ab12-cd34-ef56-gh78',
      );
      await tester.ensureVisible(find.byKey(LoginScreen.signInTargetKey));
      await tester.tap(find.byKey(LoginScreen.signInTargetKey));
      await tester.pumpAndSettle();
      expect(bound, 'AB12-CD34-EF56-GH78');
      expect(harness.repository.loginCount, 1);
    },
  );

  testWidgets('licensed login hides the license code field', (tester) async {
    final harness = _Harness();
    await harness.controller.bootstrap();
    await tester.pumpWidget(harness.widget());
    await tester.pump();
    expect(find.byKey(LoginScreen.licenseFieldKey), findsNothing);
  });
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

  Widget widget({
    Future<ProductLicense> Function()? readLicense,
    Future<ProductLicense> Function(String code)? bindLicense,
  }) {
    return MaterialApp(
      theme: OneTheme.light(),
      home: LoginScreen(
        controller: controller,
        readLicense:
            readLicense ??
            () async => const ProductLicense(
              key: 'AB12-CD34-EF56-GH78',
              activated: true,
            ),
        bindLicense: bindLicense,
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
