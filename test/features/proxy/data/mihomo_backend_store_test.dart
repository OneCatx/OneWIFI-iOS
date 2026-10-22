import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/proxy/data/mihomo_backend_store.dart';
import 'package:onewifi_android/features/proxy/domain/mihomo_backend.dart';

void main() {
  for (final cached in [false, true]) {
    test(
      'backend revision distinguishes ABA and credentials (cached=$cached)',
      () async {
        final memory = MemoryMihomoBackendStore(_backend('a'));
        final ObservableMihomoBackendStore store = cached
            ? CachedMihomoBackendStore(memory)
            : memory;
        await store.read();
        var changes = 0;
        store.addListener(() => changes++);
        await store.write(_backend('b'));
        await store.write(_backend('a'));
        await store.write(_backend('a', 'changed'));
        await store.write(_backend('a', 'changed'));
        expect(changes, 3);
        expect(store.revision, 3);
        expect((await store.read())!.secret, 'changed');
      },
    );
  }

  test('slow initial read cannot overwrite a later cached write', () async {
    final inner = _Storage();
    final store = CachedMihomoBackendStore(inner);
    final read = store.read();
    await inner.readStarted.future;
    final write = store.write(_backend('b'));
    inner.initial.complete(_backend('a'));
    await read;
    await write;
    expect((await store.read())!.origin.host, 'b.test');
  });

  test(
    'cached persistence writes are serialized and failure keeps committed backend',
    () async {
      final inner = _Storage()..initial.complete(_backend('a'));
      final store = CachedMihomoBackendStore(inner);
      await store.read();
      final gate = Completer<void>();
      inner.writeGate = gate.future;
      final first = store.write(_backend('b'));
      await inner.writeStarted.future;
      final second = store.write(_backend('c'));
      gate.complete();
      await Future.wait([first, second]);
      expect(inner.maxWrites, 1);
      expect((await store.read())!.origin.host, 'c.test');
      final revision = store.revision;
      inner.fail = true;
      await expectLater(store.write(_backend('d')), throwsStateError);
      expect((await store.read())!.origin.host, 'c.test');
      expect(store.revision, revision);
    },
  );
}

MihomoBackend _backend(String host, [String secret = '']) =>
    MihomoBackend(origin: Uri.parse('http://$host.test:9090'), secret: secret);

final class _Storage implements MihomoBackendStore {
  final initial = Completer<MihomoBackend?>();
  final readStarted = Completer<void>();
  final writeStarted = Completer<void>();
  Future<void>? writeGate;
  int writes = 0;
  int maxWrites = 0;
  bool fail = false;

  @override
  Future<MihomoBackend?> read() {
    if (!readStarted.isCompleted) readStarted.complete();
    return initial.future;
  }

  @override
  Future<void> write(MihomoBackend backend) async {
    writes++;
    if (writes > maxWrites) maxWrites = writes;
    if (!writeStarted.isCompleted) writeStarted.complete();
    try {
      await writeGate;
      if (fail) throw StateError('storage failure');
    } finally {
      writes--;
    }
  }
}
