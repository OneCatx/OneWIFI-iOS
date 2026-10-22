import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/security/gateway_trust_store.dart';
import 'package:onewifi_android/core/security/secure_token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'origin-specific fingerprint is normalized and invalid replacements preserve it',
    () async {
      final store = SecureGatewayTrustStore();
      final origin = Uri.parse('https://example.test');
      await store.writeFingerprint(origin, List.filled(32, 'AB').join(':'));
      expect(await store.readFingerprint(origin), 'ab' * 32);
      expect(
        await store.readFingerprint(Uri.parse('https://example.test:8443')),
        isNull,
      );
      expect(
        () => store.writeFingerprint(origin, 'invalid'),
        throwsFormatException,
      );
      expect(await store.readFingerprint(origin), 'ab' * 32);
    },
  );

  test(
    'logout cleanup only removes bearer tokens, preserving trust fingerprints',
    () async {
      final origin = Uri.parse('https://example.test');
      final bearer = SecureTokenStore();
      final trust = SecureGatewayTrustStore();
      await bearer.write(origin, 'synthetic-session');
      await trust.writeFingerprint(origin, 'a' * 64);
      await bearer.clearAll();
      expect(await bearer.read(origin), isNull);
      expect(await trust.readFingerprint(origin), 'a' * 64);
    },
  );
}
