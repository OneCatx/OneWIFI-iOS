import 'dart:async';

import '../../../core/config/base_url_policy.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/request_notifier.dart';
import '../data/ios_apns_bridge.dart';
import '../data/ios_push_endpoint_client.dart';
import '../data/remote_otp_pairing_store.dart';
import '../data/remote_otp_stream_client.dart';
import '../domain/remote_otp_pairing.dart';
import '../domain/sms.dart';
import 'otp_activity_binding.dart';
import 'remote_otp_delivery_gate.dart';

enum RemoteOtpStatus { unpaired, connecting, connected, retrying, unauthorized }

final class RemoteOtpState {
  const RemoteOtpState({
    required this.status,
    required this.endpoint,
    this.error,
  });
  const RemoteOtpState.unpaired()
    : this(status: RemoteOtpStatus.unpaired, endpoint: null);

  final RemoteOtpStatus status;
  final Uri? endpoint;
  final String? error;
  bool get paired => endpoint != null;
}

final class RemoteOtpController extends RequestNotifier {
  RemoteOtpController({
    required this.store,
    required this.streamClient,
    required this.pushClient,
    required this.apns,
    required this.otpSink,
    this.pollingOriginProvider,
  }) : activity = OtpActivityBinding(client: pushClient);

  final RemoteOtpPairingStore store;
  final RemoteOtpStreamClient streamClient;
  final IosPushEndpointClient pushClient;
  final OtpActivityBinding activity;
  final IosApnsBridge apns;
  final SmsOtpSink? otpSink;
  final Future<Uri> Function()? pollingOriginProvider;
  RemoteOtpState _state = const RemoteOtpState.unpaired();
  StreamSubscription<RemoteOtpEvent>? _stream;
  StreamSubscription<IosApnsEvent>? _apnsEvents;
  StreamSubscription<void>? _tokenChanges;
  Timer? _retry;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  int _lastEventId = 0;
  int _retryMs = 1000;
  bool _enabled = true;
  RemoteOtpDeliveryGate _deliveryGate = RemoteOtpDeliveryGate();
  Future<void>? _restoring;
  String _restoredIdentity = '';

  RemoteOtpState get state => _state;

  @override
  List<RequestSlot> get slots => const <RequestSlot>[];

  /// Configured pairing owns alerts only for the polling gateway, including
  /// the restore/registration window and temporary stream disconnections.
  Future<bool> ownsPollingAlerts() async {
    final originProvider = pollingOriginProvider;
    if (originProvider == null) return false;
    final endpoint = await store.read();
    if (endpoint == null) return false;
    final pairedUrl = endpoint.baseUrl;
    // A pairing may target a mounted gateway; dropping its path would claim
    // notifications for a different source at the same host.
    if (pairedUrl.path.isNotEmpty && pairedUrl.path != '/') return false;
    final pollingOrigin = await originProvider();
    return BaseUrlPolicy.parseAndValidate(pairedUrl.toString()) ==
        BaseUrlPolicy.parseAndValidate(pollingOrigin.toString());
  }

  Future<void> restore() {
    final pending = _restoring;
    if (pending != null) return pending;
    final future = _restore();
    _restoring = future;
    return future.whenComplete(() {
      if (identical(_restoring, future)) _restoring = null;
    });
  }

  Future<void> _restore() async {
    final generation = _generation;
    final endpoint = await store.read();
    if (!_current(generation)) return;
    final identity = endpoint == null
        ? ''
        : '${endpoint.baseUrl}/${endpoint.token}';
    if (_restoredIdentity == identity && _stream != null) return;
    if (_restoredIdentity != identity) _deliveryGate = RemoteOtpDeliveryGate();
    _lastEventId = endpoint == null ? 0 : await store.readLastEventId();
    _listenAPNs();
    await apns.start();
    if (!_current(generation)) return;
    if (endpoint == null) {
      _set(const RemoteOtpState.unpaired());
      return;
    }
    await _register(endpoint);
    if (!_current(generation)) return;
    await _ensureNotificationPermission();
    if (!_current(generation)) return;
    _restoredIdentity = identity;
    _connect(endpoint);
  }

  Future<void> pair(String raw) async {
    final endpoint = RemoteOtpPairing.parse(raw);
    _generation += 1;
    final generation = _generation;
    _stop();
    await activity.clear();
    if (!_current(generation)) return;
    activity.enable();
    _deliveryGate = RemoteOtpDeliveryGate();
    await store.write(endpoint);
    if (!_current(generation)) return;
    _lastEventId = 0;
    _retryMs = 1000;
    _listenAPNs();
    await apns.start();
    if (!_current(generation)) return;
    await _register(endpoint);
    if (!_current(generation)) return;
    await _ensureNotificationPermission();
    if (!_current(generation)) return;
    _connect(endpoint);
  }

  Future<void> disconnect() async {
    _generation += 1;
    _stop();
    await activity.clear();
    _deliveryGate = RemoteOtpDeliveryGate();
    await store.clear();
    if (!isDisposed) _set(const RemoteOtpState.unpaired());
  }

  void setEnabled(bool enabled) {
    if (isDisposed || _enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      _generation += 1;
      _stop();
      unawaited(activity.clear());
      return;
    }
    activity.enable();
    unawaited(restore());
  }

  void _listenAPNs() {
    _apnsEvents ??= apns.events.listen((event) {
      _enqueue(() => _handleNativeEvent(event));
    });
    _tokenChanges ??= apns.tokenChanges.listen((_) {
      _enqueue(_registerCurrentEndpoint);
    });
  }

  Future<void> _registerCurrentEndpoint() async {
    final generation = _generation;
    final endpoint = await store.read();
    if (endpoint != null && _current(generation)) await _register(endpoint);
  }

  Future<void> _register(RemoteOtpEndpoint endpoint) async {
    final token = apns.deviceToken;
    final environment = apns.environment;
    if (token.isEmpty || environment.isEmpty) return;
    try {
      await activity.configure(endpoint, token, environment);
    } on RemoteOtpUnauthorized {
      if (!isDisposed) {
        _set(
          RemoteOtpState(
            status: RemoteOtpStatus.unauthorized,
            endpoint: endpoint.baseUrl,
            error: '令牌无效，请重新配对。',
          ),
        );
      }
    } catch (_) {
      // APNs token can arrive before network is usable; SSE retry will retry it.
    }
  }

  /// 配对后系统通知权限仍是「未决定」时，后台横幅永远不会出现。
  /// 灵动岛与通知权限是两套开关，能显示灵动岛不代表系统允许展示通知。
  Future<void> _ensureNotificationPermission() async {
    try {
      await apns.refreshAuthorization();
      if (isDisposed || !_enabled) return;
      if (apns.status.value.authorization ==
          IosPushAuthorization.notDetermined) {
        await apns.requestAuthorization();
      }
    } catch (_) {
      // 权限申请失败不能阻塞配对与 SSE 连接。
    }
  }

  void _connect(RemoteOtpEndpoint endpoint) {
    if (isDisposed || !_enabled) return;
    final generation = _generation;
    _stream = streamClient
        .open(endpoint, lastEventId: _lastEventId)
        .listen(
          (event) =>
              _enqueue(() => _handleStreamEvent(event, endpoint, generation)),
          onError: (Object error, StackTrace _) =>
              _onStreamError(error, endpoint, generation),
          onDone: () => _scheduleRetry(endpoint, generation),
          cancelOnError: true,
        );
    _set(
      RemoteOtpState(
        status: RemoteOtpStatus.connecting,
        endpoint: endpoint.baseUrl,
      ),
    );
  }

  Future<void> _handleStreamEvent(
    RemoteOtpEvent event,
    RemoteOtpEndpoint endpoint,
    int generation,
  ) async {
    if (!_current(generation)) return;
    if (event.type == RemoteOtpEventType.connected) {
      _retryMs = 1000;
      _set(
        RemoteOtpState(
          status: RemoteOtpStatus.connected,
          endpoint: endpoint.baseUrl,
        ),
      );
      await _register(endpoint);
      return;
    }
    if (event.id <= _lastEventId) return;
    if (!_current(generation) || !_deliveryGate.claim(event.id)) return;
    await _acknowledge(endpoint, event.id);
    await _advanceStream(event.id, generation);
  }

  Future<void> _handleNativeEvent(IosApnsEvent event) async {
    final generation = _generation;
    final endpoint = await store.read();
    if (endpoint == null || !_current(generation)) return;
    if (!_current(generation) || !_deliveryGate.claim(event.smsId)) return;
    // APNs owns the banner; only the server writes the prepared activity.
    await _acknowledge(endpoint, event.smsId);
    await _advanceStream(event.smsId, generation);
  }

  Future<void> _acknowledge(RemoteOtpEndpoint endpoint, int smsId) async {
    final token = apns.deviceToken;
    if (token.isEmpty || smsId <= 0) return;
    await pushClient.acknowledge(
      endpoint: endpoint,
      deviceToken: token,
      smsId: smsId,
    );
    await store.writeLastAcknowledgedPushId(smsId);
  }

  Future<void> _advanceStream(int id, int generation) async {
    if (!_current(generation) || id <= _lastEventId) return;
    await store.writeLastEventId(id);
    if (_current(generation)) _lastEventId = id;
  }

  void _onStreamError(
    Object error,
    RemoteOtpEndpoint endpoint,
    int generation,
  ) {
    if (!_current(generation)) return;
    if (error is RemoteOtpUnauthorized) {
      _stop();
      unawaited(activity.clear());
      _set(
        RemoteOtpState(
          status: RemoteOtpStatus.unauthorized,
          endpoint: endpoint.baseUrl,
          error: '令牌无效，请重新配对。',
        ),
      );
      return;
    }
    _scheduleRetry(endpoint, generation, error: error);
  }

  void _scheduleRetry(
    RemoteOtpEndpoint endpoint,
    int generation, {
    Object? error,
  }) {
    if (!_current(generation)) return;
    _stream = null;
    final delay = _retryMs;
    _retryMs = (_retryMs * 2).clamp(1000, 60000);
    _set(
      RemoteOtpState(
        status: RemoteOtpStatus.retrying,
        endpoint: endpoint.baseUrl,
        error: error?.toString(),
      ),
    );
    _retry?.cancel();
    _retry = Timer(Duration(milliseconds: delay), () => _connect(endpoint));
  }

  void _enqueue(Future<void> Function() operation) {
    _tail = _tail.then((_) => operation()).catchError((Object _) {});
  }

  bool _current(int generation) =>
      !isDisposed && _enabled && generation == _generation;

  void _stop() {
    _retry?.cancel();
    _retry = null;
    unawaited(_stream?.cancel() ?? Future<void>.value());
    _stream = null;
  }

  void _set(RemoteOtpState value) => publish(() => _state = value);

  @override
  void dispose() {
    _generation += 1;
    activity.dispose();
    _stop();
    unawaited(_apnsEvents?.cancel() ?? Future<void>.value());
    unawaited(_tokenChanges?.cancel() ?? Future<void>.value());
    unawaited(apns.dispose());
    super.dispose();
  }
}
