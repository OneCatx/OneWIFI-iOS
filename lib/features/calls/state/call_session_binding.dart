import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/http/gateway_io_client.dart';
import '../../../core/security/session_resource.dart';
import '../../../core/state/session_state.dart';
import '../../auth/state/session_controller.dart';
import '../data/native_call_session.dart';
import '../data/native_call_snapshot.dart';

final class CallSessionBinding extends ChangeNotifier
    implements SessionResource, NativeCallView {
  CallSessionBinding({
    required this.native,
    required this.tokenProvider,
    required this.fingerprintProvider,
    this.trustChanges,
  });
  final NativeCallSession native;
  final Future<String?> Function(Uri) tokenProvider, fingerprintProvider;
  final GatewayConnectionFactory? trustChanges;
  SessionController? _session;
  StreamSubscription<NativeCallSnapshot>? _subscription;
  int _context = 0;
  int? _epoch;
  SessionStatus? _observedSessionStatus;
  bool _authenticationEnabled = false;
  int _trustIntent = 0;
  int _generation = -1, _revision = -1;
  bool _disposed = false;
  NativeCallSnapshot? _snapshot;
  String _status = 'unconfigured';
  Future<void>? _clearing;
  void attach(SessionController session) {
    assert(_session == null);
    _session = session;
    session.registerResource(this);
    session.addListener(_onSessionChanged);
    trustChanges?.addListener(_onTrustChanged);
    _onSessionChanged();
  }

  void _onSessionChanged() {
    final session = _session!;
    final wasSignedIn = _observedSessionStatus == SessionStatus.signedIn;
    _observedSessionStatus = session.state.status;
    if (session.state.status != SessionStatus.signedIn) {
      if (_authenticationEnabled || _epoch != null) unawaited(clear());
      return;
    }
    // Resource clear is an authentication teardown, even while SessionController
    // still exposes signedIn during asynchronous logout/storage work. Only a
    // subsequent real authentication transition can reopen this binding.
    if (!_authenticationEnabled && wasSignedIn) return;
    _authenticationEnabled = true;
    _configureCurrentSession();
  }

  void _configureCurrentSession() {
    final session = _session!;
    if (!_authenticationEnabled ||
        session.state.status != SessionStatus.signedIn) {
      return;
    }
    if (_epoch == session.sessionEpoch) return;
    _epoch = session.sessionEpoch;
    final context = ++_context;
    final epoch = session.sessionEpoch;
    final origin = session.origin;
    final expiry = session.state.expiresAt;
    bool current() =>
        !_disposed &&
        _authenticationEnabled &&
        _context == context &&
        session.sessionEpoch == epoch &&
        session.state.status == SessionStatus.signedIn;
    unawaited(() async {
      try {
        await _clearing;
        if (!current()) return;
        final token = await tokenProvider(origin);
        if (!current()) return;
        final fingerprint = origin.scheme == 'https'
            ? await fingerprintProvider(origin)
            : null;
        if (!current()) return;
        if (token == null || token.isEmpty) {
          throw PlatformException(code: 'call_unauthorized');
        }
        await native
            .configure(
              origin: origin,
              token: token,
              expiresAt: expiry,
              certificateFingerprint: fingerprint,
            )
            .timeout(const Duration(seconds: 5));
        if (!current()) return;
        final initial = await native.snapshot().timeout(
          const Duration(seconds: 5),
        );
        if (!current()) return;
        _accept(initial);
        if (!current()) return;
        _subscription = native.states.listen(
          (state) {
            if (current()) _accept(state);
          },
          onError: (Object _) {
            if (current()) _viewFailed();
          },
          onDone: () {
            if (current()) _viewFailed(permanent: true);
          },
        );
      } catch (error) {
        if (current()) {
          _snapshot = null;
          _status = error is PlatformException
              ? error.code
              : 'call_configuration_failed';
          notifyListeners();
        }
      }
    }());
  }

  void _onTrustChanged() {
    final session = _session;
    if (_disposed ||
        !_authenticationEnabled ||
        session == null ||
        session.state.status != SessionStatus.signedIn ||
        trustChanges?.changedTrustOrigin !=
            GatewayConnectionFactory.originOf(session.origin)) {
      return;
    }
    // Invalidate projection synchronously; clear native before reading new trust.
    final intent = ++_trustIntent;
    unawaited(
      _clearNativeContext().then((_) {
        if (!_disposed && _authenticationEnabled && intent == _trustIntent) {
          _configureCurrentSession();
        }
      }),
    );
  }

  void _accept(NativeCallSnapshot next) {
    if (next.generation < _generation ||
        (next.generation == _generation && next.revision <= _revision)) {
      return;
    }
    _generation = next.generation;
    _revision = next.revision;
    _snapshot = next;
    _status = next.status;
    notifyListeners();
    if (next.status == 'unauthorized') {
      final session = _session!;
      unawaited(session.expireIfCurrent(session.sessionEpoch));
    }
  }

  void _viewFailed({bool permanent = false}) {
    // Keep high water marks even when the display projection becomes unusable.
    _snapshot = null;
    _status = permanent ? 'call_view_closed' : 'call_view_failed';
    notifyListeners();
  }

  @override
  NativeCallSnapshot? get snapshot => _snapshot;
  @override
  String get status => _status;
  @override
  Future<void> clear() {
    _authenticationEnabled = false;
    _trustIntent++;
    return _clearNativeContext();
  }

  Future<void> _clearNativeContext() {
    _context++;
    _epoch = null;
    _snapshot = null;
    _status = 'unconfigured';
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
    if (!_disposed) notifyListeners();
    // Never queue teardown behind a suspended secure-storage read/configure.
    final current = _clearing;
    if (current != null) return current;
    final pending = native
        .clear()
        .timeout(const Duration(seconds: 3))
        .catchError((Object _) {
          if (!_disposed) {
            _status = 'call_clear_failed';
            notifyListeners();
          }
        });
    _clearing = pending;
    unawaited(
      pending.whenComplete(() {
        if (identical(_clearing, pending)) _clearing = null;
      }),
    );
    return pending;
  }

  @override
  Future<void> execute(String method, Map<String, Object?> values) async {
    final state = _snapshot;
    if (_disposed || state == null || state.status != 'configured') {
      throw PlatformException(code: 'call_session_closed');
    }
    if (!{
      'requestPermissions',
      'openAppSettings',
      'refreshEvents',
      'dial',
      'answer',
      'hangup',
      'mute',
      'route',
      'dtmf',
    }.contains(method)) {
      throw PlatformException(code: 'call_invalid_request');
    }
    if ({'answer', 'hangup', 'mute', 'route', 'dtmf'}.contains(method) &&
        (state.local == null ||
            values['uuid'] is! String ||
            values['uuid'] != state.local!.uuid)) {
      throw PlatformException(code: 'call_state_conflict');
    }
    await native.command(method, {
      ...values,
      if (method != 'requestPermissions') 'generation': state.generation,
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _context++;
    _session?.removeListener(_onSessionChanged);
    _session?.unregisterResource(this);
    trustChanges?.removeListener(_onTrustChanged);
    unawaited(clear());
    super.dispose();
  }
}
