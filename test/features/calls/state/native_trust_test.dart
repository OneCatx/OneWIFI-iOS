import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/gateway_io_client.dart';
import 'package:onewifi_android/core/security/gateway_trust_store.dart';

void main() {
  for (final unreadable in [false, true]) {
    test(
      'explicit trust repair remains possible with ${unreadable ? 'unreadable' : 'malformed'} old pin',
      () async {
        final store = _Trust()
          ..pin = 'corrupt'
          ..unreadable = unreadable;
        final factory = GatewayConnectionFactory(trustStore: store);
        addTearDown(factory.close);
        var changes = 0;
        factory.addListener(() => changes++);
        final origin = Uri.parse('https://gateway.test');
        await factory.setFingerprint(origin, 'a' * 64);
        expect(store.pin, 'a' * 64);
        expect(changes, 1);
        store.pin = 'corrupt';
        await factory.setFingerprint(origin, null);
        expect(store.pin, isNull);
        expect(changes, 2);
        store.fail = true;
        await expectLater(
          factory.setFingerprint(origin, 'b' * 64),
          throwsStateError,
        );
        expect(changes, 2);
      },
    );
  }
  test(
    'successful pin writes notify native consumers; failed writes do not',
    () async {
      final store = _Trust();
      final factory = GatewayConnectionFactory(trustStore: store);
      addTearDown(factory.close);
      final Object observable = factory;
      expect(observable, isA<Listenable>());
      var notifications = 0;
      (observable as Listenable).addListener(() => notifications++);
      final origin = Uri.parse('https://gateway.test');
      await factory.setFingerprint(origin, 'a' * 64);
      expect(notifications, 1);
      expect(await factory.readFingerprint(origin), 'a' * 64);
      store.fail = true;
      await expectLater(
        factory.setFingerprint(origin, 'b' * 64),
        throwsStateError,
      );
      expect(notifications, 1);
    },
  );
}

class _Trust implements GatewayTrustStore {
  String? pin;
  bool fail = false;
  bool unreadable = false;
  @override
  Future<String?> readFingerprint(Uri origin) async {
    if (unreadable) throw const FormatException('synthetic unreadable trust');
    return pin;
  }

  @override
  Future<void> writeFingerprint(Uri origin, String fingerprint) async {
    if (fail) throw StateError('storage unavailable');
    pin = fingerprint;
  }

  @override
  Future<void> clearFingerprint(Uri origin) async {
    pin = null;
  }
}
