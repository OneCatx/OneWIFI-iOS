import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/http/request_slot.dart';

void main() {
  group('RequestSlot', () {
    test('a fresh ticket is current until a newer one begins', () {
      final slot = RequestSlot(RequestRegistry(), 'esim.inventory');

      final first = slot.begin();
      expect(first.isCurrent, isTrue);
      expect(slot.isActive, isTrue);

      final second = slot.begin();
      expect(first.isCurrent, isFalse);
      expect(first.cancellation.isCancelled, isTrue);
      expect(second.isCurrent, isTrue);
    });

    test('ending a ticket clears the active flag but keeps it current', () {
      final slot = RequestSlot(RequestRegistry(), 'esim.inventory');
      final ticket = slot.begin();

      ticket.end();

      expect(slot.isActive, isFalse);
      expect(ticket.isCurrent, isTrue);
    });

    test('ending a stale ticket does not clear the newer active one', () {
      final slot = RequestSlot(RequestRegistry(), 'esim.inventory');
      final stale = slot.begin();
      final active = slot.begin();

      stale.end();

      expect(slot.isActive, isTrue);
      expect(active.isCurrent, isTrue);
    });

    test('cancel voids the in-flight ticket and releases its registration', () {
      final registry = RequestRegistry();
      final slot = RequestSlot(registry, 'esim.download');
      final ticket = slot.begin();

      slot.cancel();

      expect(ticket.isCurrent, isFalse);
      expect(ticket.cancellation.isCancelled, isTrue);
      expect(slot.isActive, isFalse);
      // 登记已归还：同 key 再注册不会再去取消这张旧票据以外的任何东西。
      final next = registry.register('esim.download');
      expect(next.cancellation.isCancelled, isFalse);
    });

    test('cancel without an in-flight ticket still voids later checks', () {
      final slot = RequestSlot(RequestRegistry(), 'esim.download');
      final ticket = slot.begin();
      ticket.end();

      slot.cancel();

      expect(ticket.isCurrent, isFalse);
    });

    test('close makes every ticket stale, even ones begun afterwards', () {
      final slot = RequestSlot(RequestRegistry(), 'sms.send');
      final before = slot.begin();

      slot.close();
      final after = slot.begin();

      expect(before.isCurrent, isFalse);
      expect(before.cancellation.isCancelled, isTrue);
      expect(after.isCurrent, isFalse);
    });

    test('an overridden key is what gets registered and released', () {
      final registry = RequestRegistry();
      final slot = RequestSlot(registry, 'calls.active');

      final ticket = slot.begin(key: 'calls.active:dev-1');
      expect(ticket.key, 'calls.active:dev-1');

      final clash = registry.register('calls.active:dev-1');
      expect(ticket.cancellation.isCancelled, isTrue);
      expect(ticket.isCurrent, isFalse);

      registry.remove('calls.active:dev-1', clash);
      ticket.end();
      expect(slot.isActive, isFalse);
    });

    test('registry-level cancelAll makes the ticket stale', () {
      final registry = RequestRegistry();
      final slot = RequestSlot(registry, 'auth.restore');
      final ticket = slot.begin();

      registry.cancelAll();

      expect(ticket.isCurrent, isFalse);
    });
  });
}
