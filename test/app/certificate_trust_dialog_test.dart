import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/gateway_io_client.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/security/gateway_trust_store.dart';
import 'package:onewifi_android/features/auth/data/auth_repository.dart';
import 'package:onewifi_android/features/auth/domain/session_user.dart';
import 'package:onewifi_android/features/auth/presentation/login_screen.dart';
import 'package:onewifi_android/features/auth/state/session_controller.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';
import '../support/fakes.dart';

void main() {
  testWidgets(
    'certificate trust can be explicitly configured before login without sending credentials',
    (tester) async {
      final store = _Trust();
      final connections = GatewayConnectionFactory(trustStore: store);
      final auth = _Auth();
      final session = SessionController(
        repository: auth,
        tokenStore: MemoryTokenStore(),
        baseUrlStore: MemoryBaseUrlStore(Uri.parse('http://192.168.1.88:6699')),
        requestRegistry: RequestRegistry(),
        connections: connections,
      );
      addTearDown(connections.close);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            controller: session,
            readLicense: () async => const ProductLicense(
              key: 'AB12-CD34-EF56-GH78',
              activated: true,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(LoginScreen.fingerprintKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('certificate-fingerprint')),
        'A' * 64,
      );
      await tester.ensureVisible(find.text('保存此证书指纹'));
      await tester.tap(find.text('保存此证书指纹'));
      await tester.pumpAndSettle();
      expect(store.pins[Uri.parse('https://192.168.1.88:6699')], 'a' * 64);
      expect(auth.logins, 0);
    },
  );
}

class _Trust implements GatewayTrustStore {
  final pins = <Uri, String>{};
  @override
  Future<String?> readFingerprint(Uri origin) async => pins[origin];
  @override
  Future<void> writeFingerprint(Uri origin, String value) async {
    pins[origin] = value;
  }

  @override
  Future<void> clearFingerprint(Uri origin) async {
    pins.remove(origin);
  }
}

class _Auth implements AuthRepository {
  int logins = 0;
  @override
  Future<SessionUser> login(String username, String password) async {
    logins++;
    return SessionUser(username);
  }

  @override
  Future<SessionUser> restore({RequestCancellation? cancellation}) async =>
      SessionUser('test');
  @override
  Future<void> logout() async {}
}
