import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/request_registry.dart';

void main() {
  group('RequestRegistry', () {
    test('replacing a stable key cancels the older read', () {
      final registry = RequestRegistry();

      final older = registry.register('auth.restore');
      final newer = registry.register('auth.restore');

      expect(older.cancellation.isCancelled, isTrue);
      expect(newer.cancellation.isCancelled, isFalse);
    });

    test('removing an older generation leaves the replacement registered', () {
      final registry = RequestRegistry();
      final older = registry.register('auth.restore');
      final newer = registry.register('auth.restore');

      registry.remove('auth.restore', older);
      final latest = registry.register('auth.restore');

      expect(newer.cancellation.isCancelled, isTrue);
      expect(latest.cancellation.isCancelled, isFalse);
    });

    test(
      'removing the matching handle prevents later replacement cancellation',
      () {
        final registry = RequestRegistry();
        final completed = registry.register('auth.restore');

        registry.remove('auth.restore', completed);
        registry.register('auth.restore');

        expect(completed.cancellation.isCancelled, isFalse);
      },
    );

    test('cancelAll cancels every registered read and clears the registry', () {
      final registry = RequestRegistry();
      final restore = registry.register('auth.restore');
      final overview = registry.register('overview.load');

      registry.cancelAll();
      final nextRestore = registry.register('auth.restore');

      expect(restore.cancellation.isCancelled, isTrue);
      expect(overview.cancellation.isCancelled, isTrue);
      expect(nextRestore.cancellation.isCancelled, isFalse);
    });
  });
}
