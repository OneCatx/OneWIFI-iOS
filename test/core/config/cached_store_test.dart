import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/config/base_url_store.dart';
import 'package:onewifi_android/core/security/secure_token_store.dart';
import '../../support/fakes.dart';

void main() {
  test('CachedBaseUrlStore 第二次 read 不再打内层', () async {
    final inner = _CountingOrigin(Uri.parse('http://192.168.1.88:6699'));
    final store = CachedBaseUrlStore(inner);
    expect(await store.read(), inner.origin);
    expect(await store.read(), inner.origin);
    expect(inner.reads, 1);

    await store.write(Uri.parse('http://10.0.0.8:6688'));
    expect(inner.writes, 1);
    expect(await store.read(), Uri.parse('http://10.0.0.8:6688'));
    expect(inner.reads, 1);
  });

  test('CachedTokenStore 第二次 read 不再打内层，write/clear 使缓存失效', () async {
    final origin = Uri.parse('https://api.example.test');
    final inner = MemoryTokenStore(<Uri, String>{origin: 'token-1'});
    final store = CachedTokenStore(inner);
    expect(await store.read(origin), 'token-1');
    inner.tokens[origin] = 'stale';
    expect(await store.read(origin), 'token-1');

    await store.write(origin, 'token-2');
    expect(await store.read(origin), 'token-2');
    await store.clear(origin);
    expect(await store.read(origin), isNull);
  });
}

final class _CountingOrigin implements BaseUrlStore {
  _CountingOrigin(this.origin);

  Uri origin;
  int reads = 0;
  int writes = 0;

  @override
  Future<Uri> read() async {
    reads += 1;
    return origin;
  }

  @override
  Future<void> write(Uri origin) async {
    writes += 1;
    this.origin = origin;
  }
}
