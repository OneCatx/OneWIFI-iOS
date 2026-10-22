import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/base_url_policy.dart';
import '../domain/mihomo_backend.dart';

abstract interface class MihomoBackendStore {
  Future<MihomoBackend?> read();

  Future<void> write(MihomoBackend backend);
}

/// The shared in-process source. Changes invalidate consumers immediately.
abstract interface class ObservableMihomoBackendStore
    implements MihomoBackendStore, Listenable {
  int get revision;
}

bool _sameBackend(MihomoBackend? a, MihomoBackend? b) =>
    a?.origin == b?.origin && a?.secret == b?.secret;

MihomoBackendStore createMihomoBackendStore() {
  try {
    return CachedMihomoBackendStore(SharedPreferencesMihomoBackendStore());
  } on StateError {
    return MemoryMihomoBackendStore();
  }
}

final class MemoryMihomoBackendStore extends ChangeNotifier
    implements ObservableMihomoBackendStore {
  MemoryMihomoBackendStore([this._backend]);

  MihomoBackend? _backend;

  @override
  int get revision => _revision;
  int _revision = 0;

  @override
  Future<MihomoBackend?> read() async => _backend;

  @override
  Future<void> write(MihomoBackend backend) async {
    if (_sameBackend(_backend, backend)) return;
    _backend = backend;
    _revision += 1;
    notifyListeners();
  }
}

final class CachedMihomoBackendStore extends ChangeNotifier
    implements ObservableMihomoBackendStore {
  CachedMihomoBackendStore(this._inner);

  final MihomoBackendStore _inner;
  MihomoBackend? _cached;
  var _loaded = false;
  Future<void> _tail = Future<void>.value();
  int _revision = 0;

  @override
  int get revision => _revision;

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<MihomoBackend?> read() => _serialized(() async {
    if (!_loaded) {
      _cached = await _inner.read();
      _loaded = true;
    }
    return _cached;
  });

  @override
  Future<void> write(MihomoBackend backend) => _serialized(() async {
    await _inner.write(backend);
    final changed = !_loaded || !_sameBackend(_cached, backend);
    _cached = backend;
    _loaded = true;
    if (changed) {
      _revision += 1;
      notifyListeners();
    }
  });
}

final class SharedPreferencesMihomoBackendStore implements MihomoBackendStore {
  SharedPreferencesMihomoBackendStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String originKey = 'onewifi.mihomo.origin';
  static const String secretKey = 'onewifi.mihomo.secret';

  final SharedPreferencesAsync _preferences;

  @override
  Future<MihomoBackend?> read() async {
    final raw = await _preferences.getString(originKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final origin = BaseUrlPolicy.parseAndValidate(raw);
      final secret = (await _preferences.getString(secretKey) ?? '').trim();
      return MihomoBackend(origin: origin, secret: secret);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(MihomoBackend backend) async {
    final origin = BaseUrlPolicy.parseAndValidate(backend.origin.toString());
    await _preferences.setString(originKey, origin.toString());
    await _preferences.setString(secretKey, backend.secret.trim());
  }
}
