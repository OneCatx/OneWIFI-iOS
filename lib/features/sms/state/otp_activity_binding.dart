import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import '../../../core/security/session_resource.dart';
import '../../auth/state/session_controller.dart';
import '../data/ios_push_endpoint_client.dart';
import '../data/otp_activity_bridge.dart';
import '../data/remote_otp_stream_client.dart';
import '../domain/remote_otp_pairing.dart';

enum OtpActivityReadiness {
  waiting,
  ready,
  unavailable,
  upgradeRequired,
  clockError,
}

/// One paired source owns one receive-only ActivityKit session. SMS delivery
/// never enters this owner. HTTP serialization is separate from local teardown.
final class OtpActivityBinding extends ChangeNotifier
    with WidgetsBindingObserver
    implements SessionResource {
  OtpActivityBinding({
    required this.client,
    OtpActivityBridge? native,
    DateTime Function()? now,
  }) : native = native ?? OtpActivityBridge(),
       _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _events = this.native.changes.listen(_accept);
  }
  final IosPushEndpointClient client;
  final OtpActivityBridge native;
  final DateTime Function() _now;
  SessionController? _session;
  StreamSubscription<OtpActivitySnapshot>? _events;
  RemoteOtpEndpoint? _endpoint;
  String _device = '',
      _environment = '',
      _scope = '',
      _context = '',
      _serverId = '';
  String _acknowledged = '';
  int _generation = 0, _attempts = 0, _foregroundEpoch = 0, _preparedEpoch = -1;
  bool _foreground = true,
      _backgroundSeen = false,
      _disposed = false,
      _allowed = true;
  bool _protocol = false, _conflict = false;
  Future<void> _tail = Future<void>.value();
  Timer? _retry;
  Timer? _readinessExpiry;
  OtpActivitySnapshot? _snapshot;
  int? _effectiveExpiry;
  OtpActivityReadiness _readiness = OtpActivityReadiness.waiting;
  OtpActivityReadiness get readiness =>
      _readiness == OtpActivityReadiness.ready &&
          (expiresAt ?? 0) <= _now().millisecondsSinceEpoch ~/ 1000
      ? OtpActivityReadiness.unavailable
      : _readiness;
  int? get expiresAt => _effectiveExpiry ?? _snapshot?.expiresAt;
  void attach(SessionController session) {
    _session = session;
    session.registerResource(this);
  }

  Future<void> configure(
    RemoteOtpEndpoint endpoint,
    String device,
    String environment,
  ) {
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              endpoint.baseUrl.toString(),
              endpoint.token,
              device,
              environment,
            ]),
          ),
        )
        .toString();
    if (!_allowed || _disposed) return Future<void>.value();
    if (_context != key) {
      unawaited(_invalidate());
      _context = key;
      _endpoint = endpoint;
      _device = device;
      _environment = environment;
      _preparedEpoch = -1;
      _protocol = false;
      _conflict = false;
    }
    return _enqueue(_synchronize);
  }

  Future<void> prepareExplicitly() {
    // An explicit foreground action may retry preparation, but native still
    // honors user-dismissal suppression in this foreground session.
    if (_foreground && _allowed) {
      _preparedEpoch = -1;
      _conflict = false;
    }
    return _enqueue(_synchronize);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _backgroundSeen = true;
      _foreground = false;
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (_backgroundSeen) {
        _backgroundSeen = false;
        _foregroundEpoch++;
        _conflict = false;
        _protocol = false;
        _attempts = 0;
        unawaited(_enqueue(_synchronize));
      }
    }
  }

  Future<void> _synchronize() async {
    final endpoint = _endpoint;
    if (!_live || endpoint == null || _conflict) return;
    final generation = _generation;
    final device = _device, environment = _environment;
    var checkingMode = false;
    bool current() => _live && generation == _generation;
    try {
      if (!_protocol) {
        checkingMode = true;
        final receipt = await client.register(
          endpoint: endpoint,
          deviceToken: _device,
          environment: _environment,
        );
        if (!current()) return;
        checkingMode = false;
        if ((receipt.serverTime - _now().millisecondsSinceEpoch ~/ 1000).abs() >
            60) {
          _set(OtpActivityReadiness.clockError);
          return;
        }
        _serverId = receipt.activityId;
        _protocol = true;
      }
      if (_scope.isEmpty) {
        final scope = await native.scopeIdentifier(_context);
        if (!current() || scope.isEmpty) return;
        _scope = scope;
      }
      final pendingEnds = await native.pendingEnds(_scope);
      if (!current()) return;
      for (final ended in pendingEnds) {
        await _revoke(endpoint, _device, _environment, ended);
        if (!current()) return;
      }
      if (_foreground && _preparedEpoch != _foregroundEpoch) {
        _preparedEpoch = _foregroundEpoch;
        final value = await native.prepare(_scope);
        if (!current()) return;
        _accept(value, authoritative: true);
      } else {
        final value = await native.snapshot();
        if (!current()) return;
        _accept(value, authoritative: true);
      }
      if (!current()) return;
      await _registerSnapshot(generation);
    } on RemoteOtpUnauthorized {
      if (current()) unawaited(clear());
    } on FormatException {
      if (current()) {
        if (checkingMode) {
          await _registerOrdinaryFallback(
            endpoint,
            device,
            environment,
            generation,
          );
        } else {
          _set(OtpActivityReadiness.upgradeRequired);
        }
      }
    } on IosPushRequestException catch (error) {
      if (!current()) return;
      if (checkingMode && error.modeUnsupported) {
        await _registerOrdinaryFallback(
          endpoint,
          device,
          environment,
          generation,
        );
      } else if (error.statusCode == 400 || error.statusCode == 404) {
        _set(OtpActivityReadiness.upgradeRequired);
      } else if (error.statusCode == 409) {
        _conflict = true;
        _protocol = false;
        _set(OtpActivityReadiness.unavailable);
      } else {
        _scheduleRetry();
      }
    } catch (_) {
      if (current()) {
        _set(OtpActivityReadiness.waiting);
        _scheduleRetry();
      }
    }
  }

  Future<void> _registerOrdinaryFallback(
    RemoteOtpEndpoint endpoint,
    String device,
    String environment,
    int generation,
  ) async {
    bool current() => _live && generation == _generation;
    if (!current()) return;
    _set(OtpActivityReadiness.upgradeRequired);
    try {
      await client.registerOrdinary(
        endpoint: endpoint,
        deviceToken: device,
        environment: environment,
      );
      if (current()) {
        _attempts = 0;
        _retry?.cancel();
        _retry = null;
      }
    } on RemoteOtpUnauthorized {
      if (current()) unawaited(clear());
    } catch (_) {
      if (current()) _scheduleRetry();
    }
  }

  void _accept(OtpActivitySnapshot? value, {bool authoritative = false}) {
    if (!_live || value == null) return;
    if (value.state == 'none' && value.scopeId.isEmpty) {
      _snapshot = null;
      _acknowledged = '';
      _set(OtpActivityReadiness.unavailable);
      return;
    }
    if (value.scopeId != _scope) return;
    final before = _snapshot;
    if (before != null &&
        before.activityId != value.activityId &&
        !authoritative) {
      return;
    }
    if (before != null &&
        before.activityId == value.activityId &&
        value.revision < before.revision) {
      return;
    }
    if (before != null &&
        before.activityId == value.activityId &&
        {'ended', 'dismissed'}.contains(before.state) &&
        value.state == 'active') {
      return;
    }
    if (before?.activityId != value.activityId) _effectiveExpiry = null;
    _snapshot = value; // Full snapshot: an empty token clears the previous one.
    if (before?.identity == value.identity) return;
    _acknowledged = '';
    _set(
      value.state == 'active'
          ? OtpActivityReadiness.waiting
          : OtpActivityReadiness.unavailable,
    );
    unawaited(_enqueue(() => _registerSnapshot(_generation)));
  }

  Future<void> _registerSnapshot(int generation) async {
    final value = _snapshot, endpoint = _endpoint;
    if (!_live ||
        generation != _generation ||
        !_protocol ||
        _conflict ||
        value == null ||
        endpoint == null ||
        value.scopeId != _scope ||
        value.activityId.isEmpty ||
        value.identity == _acknowledged ||
        (!value.active && !{'ended', 'dismissed'}.contains(value.state))) {
      return;
    }
    if (value.active &&
        (_effectiveExpiry ?? value.expiresAt) <=
            _now().millisecondsSinceEpoch ~/ 1000) {
      _set(OtpActivityReadiness.unavailable);
      return;
    }
    try {
      final receipt = await client.registerActivity(
        endpoint: endpoint,
        deviceToken: _device,
        environment: _environment,
        expectedActivityId: _serverId,
        activity: value.withExpiry(_effectiveExpiry ?? value.expiresAt),
      );
      if (!_live || generation != _generation) return;
      if (receipt.activityId != value.activityId ||
          receipt.revision != value.revision ||
          receipt.state != value.state ||
          receipt.expiresAt <= 0 ||
          receipt.expiresAt > (_effectiveExpiry ?? value.expiresAt)) {
        throw const FormatException('接收活动回执不匹配。');
      }
      _serverId = receipt.activityId;
      _effectiveExpiry = receipt.expiresAt;
      if (_snapshot?.identity != value.identity) return;
      _acknowledged = value.identity;
      _attempts = 0;
      _retry?.cancel();
      _retry = null;
      _set(
        value.active
            ? OtpActivityReadiness.ready
            : OtpActivityReadiness.unavailable,
      );
    } on RemoteOtpUnauthorized {
      if (_live && generation == _generation) unawaited(clear());
    } on IosPushRequestException catch (error) {
      if (_live && generation == _generation) {
        if (error.statusCode == 409) {
          _conflict = true;
          _protocol = false;
          _set(OtpActivityReadiness.unavailable);
        } else {
          _set(OtpActivityReadiness.waiting);
          _scheduleRetry();
        }
      }
    } catch (_) {
      if (_live && generation == _generation) {
        _set(OtpActivityReadiness.waiting);
        _scheduleRetry();
      }
    }
  }

  void _scheduleRetry() {
    if (!_live || _attempts >= 5 || _retry?.isActive == true) return;
    final delay = Duration(seconds: 1 << _attempts++);
    _retry = Timer(delay, () {
      _retry = null;
      unawaited(_enqueue(_synchronize));
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final pending = _tail.then((_) => action());
    _tail = pending.catchError((Object _) {});
    return _tail;
  }

  bool get _live => !_disposed && _allowed;
  void _set(OtpActivityReadiness value) {
    _readinessExpiry?.cancel();
    _readinessExpiry = null;
    if (value == OtpActivityReadiness.ready) {
      final remaining = (expiresAt ?? 0) * 1000 - _now().millisecondsSinceEpoch;
      if (remaining <= 0) {
        value = OtpActivityReadiness.unavailable;
      } else {
        final generation = _generation;
        final identity = _snapshot?.identity;
        _readinessExpiry = Timer(Duration(milliseconds: remaining), () {
          if (_live &&
              generation == _generation &&
              _snapshot?.identity == identity &&
              _readiness == OtpActivityReadiness.ready) {
            // Only the readiness projection expires. This never ends, clears,
            // or recreates the ActivityKit activity or its OTP content.
            _set(OtpActivityReadiness.unavailable);
          }
        });
      }
    }
    _readiness = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> _invalidate() async {
    final scope = _scope,
        endpoint = _endpoint,
        device = _device,
        environment = _environment;
    final effectiveExpiry = _effectiveExpiry;
    _generation++;
    _scope = '';
    _snapshot = null;
    _effectiveExpiry = null;
    _acknowledged = '';
    _serverId = '';
    _retry?.cancel();
    _retry = null;
    _attempts = 0;
    _protocol = false;
    _set(OtpActivityReadiness.unavailable);
    if (scope.isEmpty) return;
    try {
      final ended = await native.end(scope);
      if (ended != null && endpoint != null && ended.activityId.isNotEmpty) {
        // Best effort, conditional on the old identity. Never queues local end
        // behind an HTTP request and never consumes this reply into new state.
        unawaited(
          _revoke(
            endpoint,
            device,
            environment,
            ended.withExpiry(effectiveExpiry ?? ended.expiresAt),
          ),
        );
      }
    } catch (_) {
      /* Native retains its terminal snapshot for next reconciliation. */
    }
  }

  Future<void> _revoke(
    RemoteOtpEndpoint endpoint,
    String device,
    String environment,
    OtpActivitySnapshot ended,
  ) async {
    try {
      final receipt = await client.registerActivity(
        endpoint: endpoint,
        deviceToken: device,
        environment: environment,
        expectedActivityId: ended.activityId,
        activity: ended,
      );
      if (receipt.activityId == ended.activityId &&
          receipt.revision == ended.revision &&
          receipt.state == ended.state) {
        await native.acknowledgeEnd(ended);
      }
    } catch (_) {
      /* Retain the native tombstone for the next authenticated entry. */
    }
  }

  void enable() {
    if (!_disposed) _allowed = true;
  }

  @override
  Future<void> clear() {
    _allowed = false;
    _context = '';
    final pending = _invalidate();
    _endpoint = null;
    return pending;
  }

  @override
  void dispose() {
    if (_disposed) return;
    unawaited(clear());
    _disposed = true;
    _session?.unregisterResource(this);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel() ?? Future<void>.value());
    native.dispose();
    super.dispose();
  }
}
