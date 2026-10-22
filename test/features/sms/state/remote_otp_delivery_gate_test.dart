import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/sms/state/remote_otp_delivery_gate.dart';

void main() {
  group('RemoteOtpDeliveryGate', () {
    test('accepts a message only once across APNs and SSE', () {
      final gate = RemoteOtpDeliveryGate();

      expect(gate.claim(42), isTrue);
      expect(gate.claim(42), isFalse);
    });

    test('keeps distinct message ids independent', () {
      final gate = RemoteOtpDeliveryGate();

      expect(gate.claim(42), isTrue);
      expect(gate.claim(43), isTrue);
    });

    test('releases a failed delivery for retry by the other path', () {
      final gate = RemoteOtpDeliveryGate();

      expect(gate.claim(42), isTrue);
      gate.release(42);
      expect(gate.claim(42), isTrue);
    });

    test('rejects invalid message ids', () {
      final gate = RemoteOtpDeliveryGate();

      expect(gate.claim(0), isFalse);
      expect(gate.claim(-1), isFalse);
    });
  });
}
