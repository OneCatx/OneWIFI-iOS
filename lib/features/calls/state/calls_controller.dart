import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/http/http_transport.dart';
import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../../devices/domain/device.dart';
import '../data/call_handset.dart';
import '../data/calls_repository.dart';
import '../data/native_call_session.dart';
import '../data/native_call_snapshot.dart';
import '../domain/call.dart';

final class CallsController extends RequestNotifier {
  CallsController({
    required this.repository,
    required this.originProvider,
    required this.tokenProvider,
    required RequestRegistry requestRegistry,
    CallHandset? handset,
    this.nativeCalls,
  }) : handset =
           handset ??
           (nativeCalls != null || defaultTargetPlatform == TargetPlatform.iOS
               ? SilentCallHandset()
               : ChannelCallHandset()),
       _read = RequestSlot(requestRegistry, 'calls.load'),
       _dial = RequestSlot(requestRegistry, 'calls.dial'),
       _answer = RequestSlot(requestRegistry, 'calls.answer'),
       _hangup = RequestSlot(requestRegistry, 'calls.hangup'),
       _media = RequestSlot(requestRegistry, 'calls.media') {
    nativeCalls?.addListener(_nativeChanged);
  }

  final CallsRepository repository;
  final Future<Uri> Function() originProvider;
  final Future<String?> Function(Uri origin) tokenProvider;
  final CallHandset handset;
  final NativeCallView? nativeCalls;
  final RequestSlot _read;
  final RequestSlot _dial;
  final RequestSlot _answer;
  final RequestSlot _hangup;
  final RequestSlot _media;

  QueryState<List<VoiceCall>> _calls =
      const QueryState<List<VoiceCall>>.initial(key: 'calls.load');
  ActionState _dialAction = const ActionState.idle();
  ActionState _answerAction = const ActionState.idle();
  ActionState _hangupAction = const ActionState.idle();
  String? _deviceId;
  String _dialNumber = '';
  String _notice = '';
  bool _noticeError = false;
  (int?, String?, bool, String)? _lastNativeError;
  bool _nativeOwnsNotice = false;
  WebSocket? _mediaSocket;
  StreamSubscription<dynamic>? _downlink;
  String? _mediaCallId;
  int _pcmBytes = 0;
  CallMediaMeta? _mediaMeta;
  Timer? _poll;
  /// When false, periodic refresh is armed but not ticking (tab left / screen disposed).
  bool _pollUiActive = false;
  Future<void>? _refreshInFlight;
  Future<void>? _mediaInFlight;
  int _deviceGeneration = 0;
  int _mediaGeneration = 0;
  bool _audioReady = false;
  Future<void> _mediaClosing = Future<void>.value();

  QueryState<List<VoiceCall>> get calls => _calls;
  List<VoiceCall> get items => usesNative
      ? [
          for (final device in nativeSnapshot?.devices ?? <NativeCallDevice>[])
            if (device.id == _deviceId) ...device.calls,
        ]
      : _calls.lastGoodData ?? const <VoiceCall>[];
  ActionState get dialAction => _dialAction;
  ActionState get answerAction => _answerAction;
  ActionState get hangupAction => _hangupAction;
  String? get deviceId => _deviceId;
  String get dialNumber => _dialNumber;
  String get notice => _notice;
  bool get noticeError => _noticeError;
  CallMediaMeta? get mediaMeta => _mediaMeta;
  int get pcmBytes => _pcmBytes;
  bool get mediaConnected => usesNative
      ? localCall?.audioReady == true
      : _mediaSocket != null && _audioReady;
  bool get usesNative =>
      nativeCalls != null ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
  NativeCallSnapshot? get nativeSnapshot => nativeCalls?.snapshot;
  NativeLocalCall? get localCall => nativeSnapshot?.local;
  bool get nativeBusy =>
      _nativeRequests > 0 || localCall?.actionPending == true;
  int _nativeRequests = 0;
  String _nativeRefreshError = '';
  bool get canRefreshNative =>
      !isDisposed &&
      nativeSnapshot?.status == 'configured' &&
      nativeSnapshot?.foreground == true &&
      nativeSnapshot?.error != 'call_history_limit' &&
      nativeSnapshot?.eventStatus != 'unauthorized' &&
      !nativeBusy &&
      _refreshInFlight == null;
  String get nativeEventDiagnostic => switch (nativeSnapshot?.eventError) {
    'call_trust' => '安全连接失败（call_trust），请检查网关证书与信任设置',
    'call_protocol_violation' => '事件格式不兼容（call_protocol_violation），请检查网关版本',
    'call_events_http_rejected' => '网关拒绝事件请求（call_events_http_rejected）',
    'call_events_rate_limited' => '请求过于频繁（call_events_rate_limited）',
    'call_events_server_error' => '网关服务暂时异常（call_events_server_error）',
    'call_transport' => '事件连接中断（call_transport）',
    'call_events_stale' => '事件连接超时（call_events_stale）',
    'call_unavailable' => '网关尚不支持事件服务（call_unavailable）',
    'call_unauthorized' => '通话授权已失效（call_unauthorized）',
    '' || null => _nativeRefreshError,
    _ => '事件监听发生未知错误，请检查网关后重试',
  };
  int _commandSequence = 0;
  bool _ending = false;
  bool get canHangupNative =>
      localCall?.hasCall == true &&
      localCall?.phase != 'disconnecting' &&
      !_ending;
  bool get canDialNative =>
      nativeSnapshot?.canReceiveCalls == true &&
      !nativeBusy &&
      localCall?.hasCall != true &&
      (nativeSnapshot?.devices.any((d) => d.id == _deviceId && d.ready) ??
          false);
  bool get canControlNativeAudio =>
      nativeSnapshot?.isFresh == true &&
      !nativeBusy &&
      localCall?.canControlAudio == true;
  bool get canSendDtmf =>
      canControlNativeAudio && localCall?.dtmfSupported == true;
  List<VoiceCall> get nativeLiveCalls => [
    for (final d in nativeSnapshot?.devices ?? <NativeCallDevice>[])
      ...d.calls.where((c) => c.isLive),
  ];
  String get nativeStatusLabel {
    final state = nativeSnapshot;
    if (state == null) {
      return switch (nativeCalls?.status) {
        'call_invalid_configuration' ||
        'call_insecure_origin' => '原生通话需要 HTTPS 或局域网地址',
        'call_view_failed' => '通话状态已中断，请重新登录恢复',
        'call_view_closed' => '通话状态已关闭，请重新登录恢复',
        'call_unauthorized' || 'unauthorized' => '通话授权已失效，请重新登录',
        'call_transport' => '系统通话配置连接失败，请检查网关后重新登录',
        'call_configuration_failed' || 'call_clear_failed' => '原生通话不可用，请重新登录',
        'unconfigured' || null => '正在配置系统通话',
        _ => '系统通话配置失败，请重新登录',
      };
    }
    if (state.status == 'unauthorized' || state.eventStatus == 'unauthorized') {
      return '通话授权已失效，请重新登录';
    }
    if (state.status != 'configured') return '正在配置系统通话';
    if (state.error == 'call_history_limit') return '通话历史已达安全上限，请重新登录';
    switch (state.eventStatus) {
      case 'unavailable':
        return '网关尚不支持原生通话服务';
      case 'failed':
        return '通话监听失败，请检查诊断后刷新';
      case 'stopped':
        return state.foreground ? '通话监听已停止，可刷新恢复' : '后台空闲，通话监听已停止';
      case 'connecting':
        return '正在同步通话状态';
      case 'offline':
        return '通话连接已断开，正在自动重试';
      case 'stale':
        return '通话状态可能已过期，正在自动重试';
    }
    if (state.permissions['microphone'] != true) return '需要麦克风权限才能拨打或接听';
    return state.canReceiveCalls ? '前台来电监听已就绪' : '系统通话尚未就绪';
  }

  void _nativeChanged() {
    if (isDisposed) return;
    final localError = localCall?.error.isNotEmpty == true;
    final error = localError ? localCall!.error : nativeSnapshot?.error ?? '';
    final identity = (
      nativeSnapshot?.generation,
      localCall?.uuid,
      localError,
      error,
    );
    publish(() {
      if (nativeSnapshot == null ||
          nativeSnapshot!.isFresh ||
          nativeSnapshot!.generation != _lastNativeError?.$1) {
        _nativeRefreshError = '';
      }
      // Repeated snapshots must not reclaim a newer local/command notice.
      // A different call or local-to-global failure is a new source, even when
      // its code is identical. Revision alone does not change ownership.
      if (identity != _lastNativeError) {
        _lastNativeError = identity;
        if (error.isNotEmpty) {
          final pending = error == 'call_remote_end_unconfirmed';
          _notice = pending ? '本机已结束，远端状态待确认' : '通话失败（$error）';
          _noticeError = !pending;
          _nativeOwnsNotice = true;
        } else if (_nativeOwnsNotice) {
          _notice = '';
          _noticeError = false;
          _nativeOwnsNotice = false;
        }
      }
    });
  }

  Future<void> requestPermissions() => _nativeCommand('requestPermissions', {});
  Future<void> openAppSettings() => _nativeCommand('openAppSettings', {});
  Future<void> setMuted(bool muted, {String? uuid}) async {
    final target = uuid ?? localCall?.uuid;
    if (canControlNativeAudio && target == localCall?.uuid) {
      await _nativeCommand('mute', {'muted': muted, 'uuid': target});
    }
  }

  Future<void> setRoute(String endpoint, {String? uuid}) async {
    final target = uuid ?? localCall?.uuid;
    if (canControlNativeAudio &&
        target == localCall?.uuid &&
        (localCall?.endpoints.any((e) => e.id == endpoint) ?? false)) {
      await _nativeCommand('route', {'endpoint': endpoint, 'uuid': target});
    }
  }

  Future<void> sendDtmf(String digit, {String? uuid}) async {
    final target = uuid ?? localCall?.uuid;
    if (canSendDtmf &&
        target == localCall?.uuid &&
        RegExp(r'^[0-9*#]$').hasMatch(digit)) {
      await _nativeCommand('dtmf', {'digit': digit, 'uuid': target});
    }
  }

  Future<void> _nativeCommand(
    String method,
    Map<String, Object?> values,
  ) async {
    if (isDisposed || (method == 'hangup' ? _ending : _nativeRequests > 0)) {
      return;
    }
    final native = nativeCalls;
    if (native == null) {
      _setNotice('原生通话尚未配置', error: true);
      return;
    }
    final sequence = ++_commandSequence;
    publish(() {
      _nativeRequests++;
      if (method == 'hangup') _ending = true;
    });
    final generation = native.snapshot?.generation;
    try {
      await native.execute(method, values);
      if (!isDisposed &&
          sequence == _commandSequence &&
          generation == native.snapshot?.generation) {
        if ((localCall?.error.isNotEmpty ?? false) ||
            (nativeSnapshot?.error.isNotEmpty ?? false)) {
          _nativeChanged();
          return;
        }
        _setNotice(
          switch (method) {
            'requestPermissions' => '请按系统提示授权麦克风',
            'openAppSettings' => '已请求打开系统设置',
            _ => '请求已提交，等待系统通话状态',
          },
        );
      }
    } catch (error) {
      if (!isDisposed &&
          sequence == _commandSequence &&
          generation == native.snapshot?.generation) {
        _setNotice(
          error is PlatformException
              ? switch (error.code) {
                  'call_system_transaction' => '系统拒绝通话请求，请查看下方 CK-D1 诊断',
                  _ => '通话请求失败（${error.code}）',
                }
              : '通话请求失败',
          error: true,
        );
      }
    } finally {
      if (!isDisposed) {
        publish(() {
          _nativeRequests--;
          if (method == 'hangup') _ending = false;
        });
      }
    }
  }

  List<VoiceCall> get liveCalls =>
      items.where((call) => call.isLive).toList(growable: false);

  List<VoiceCall> get historyCalls => items
      .where((call) => !call.isLive)
      .toList(growable: false)
      .reversed
      .toList(growable: false);

  VoiceCall? get handsetCall {
    for (final call in items) {
      if (!call.mediaReady || call.id.isEmpty) continue;
      if (call.state == CallLifecycle.active ||
          call.state == CallLifecycle.ringing ||
          call.state == CallLifecycle.dialing ||
          call.state == CallLifecycle.earlyMedia) {
        return call;
      }
    }
    return null;
  }

  @override
  List<RequestSlot> get slots => <RequestSlot>[
    _read,
    _dial,
    _answer,
    _hangup,
    _media,
  ];

  void selectDevice(String? id) {
    if (isDisposed || _deviceId == id) return;
    if (usesNative) {
      publish(() => _deviceId = id);
      return;
    }
    _deviceGeneration++;
    for (final slot in slots) {
      slot.cancel();
    }
    _refreshInFlight = null;
    _deviceId = id;
    _dialNumber = '';
    _notice = '';
    _noticeError = false;
    _calls = const QueryState<List<VoiceCall>>.initial(key: 'calls.load');
    _dialAction = const ActionState.idle();
    _answerAction = const ActionState.idle();
    _hangupAction = const ActionState.idle();
    unawaited(_closeMedia());
    publish(() {});
    _poll?.cancel();
    _poll = null;
    if (id != null && id.isNotEmpty) {
      unawaited(refresh());
      _armPollIfNeeded();
    }
  }

  /// Bind 2s list poll to CallsScreen visibility (session controller outlives the tab).
  void setPollUiActive(bool active) {
    if (isDisposed || _pollUiActive == active) return;
    _pollUiActive = active;
    if (active &&
        !usesNative &&
        _deviceId != null &&
        _deviceId!.isNotEmpty) {
      unawaited(refresh(quiet: true));
    }
    _armPollIfNeeded();
  }

  void _armPollIfNeeded() {
    _poll?.cancel();
    _poll = null;
    if (isDisposed ||
        usesNative ||
        !_pollUiActive ||
        _deviceId == null ||
        _deviceId!.isEmpty) {
      return;
    }
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(refresh(quiet: true));
    });
  }

  void appendKey(String key) {
    publish(() => _dialNumber = appendDialKey(_dialNumber, key));
  }

  void backspace() {
    publish(() => _dialNumber = backspaceDial(_dialNumber));
  }

  void setDialNumber(String value) {
    publish(() => _dialNumber = normalizeDialNumber(value));
  }

  Future<void> refresh({bool quiet = false}) {
    if (usesNative) {
      final active = _refreshInFlight;
      if (active != null) return active;
      if (!canRefreshNative) return Future<void>.value();
      final completer = Completer<void>();
      _refreshInFlight = completer.future;
      final generation = nativeSnapshot!.generation;
      publish(() => _nativeRefreshError = '');
      unawaited(() async {
        try {
          await nativeCalls!.execute('refreshEvents', {});
        } catch (_) {
          if (!isDisposed && nativeSnapshot?.generation == generation) {
            publish(() => _nativeRefreshError = '刷新请求未被接受，请检查通话状态后重试');
          }
        } finally {
          if (identical(_refreshInFlight, completer.future)) {
            _refreshInFlight = null;
            if (!isDisposed) publish(() {});
          }
          completer.complete();
        }
      }());
      return completer.future;
    }
    final id = _deviceId;
    if (id == null || id.isEmpty || isDisposed) return Future<void>.value();
    final active = _refreshInFlight;
    if (active != null) return active;
    // Publish the shared future before runQuery can notify listeners/re-enter.
    final completer = Completer<void>();
    _refreshInFlight = completer.future;
    _refresh(id, _deviceGeneration, quiet: quiet).then(
      (_) {
        if (identical(_refreshInFlight, completer.future)) {
          _refreshInFlight = null;
        }
        completer.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_refreshInFlight, completer.future)) {
          _refreshInFlight = null;
        }
        completer.completeError(error, stack);
      },
    );
    return completer.future;
  }

  Future<void> _refresh(
    String id,
    int generation, {
    required bool quiet,
  }) async {
    await runQuery<List<VoiceCall>>(
      slot: _read,
      current: () => _calls,
      set: (next) {
        publish(() => _calls = next);
      },
      silent: quiet,
      fetch: (ticket) =>
          repository.fetchCalls(id, cancellation: ticket.cancellation),
      onData: (list, ticket) async {
        if (!ticket.isCurrent ||
            isDisposed ||
            generation != _deviceGeneration) {
          return;
        }
        VoiceCall? handset;
        for (final call in list) {
          if (call.deviceId != id || !call.mediaReady || call.id.isEmpty) {
            continue;
          }
          if (call.state == CallLifecycle.active ||
              call.state == CallLifecycle.ringing ||
              call.state == CallLifecycle.dialing ||
              call.state == CallLifecycle.earlyMedia) {
            handset = call;
            break;
          }
        }
        if (handset != null) {
          unawaited(ensureMedia(handset));
        } else if (_mediaCallId != null &&
            !list.any(
              (call) =>
                  call.deviceId == id && call.id == _mediaCallId && call.isLive,
            )) {
          await _closeMedia();
        }
      },
    );
    if (isDisposed || generation != _deviceGeneration) return;
    if (!quiet && _calls.status == QueryStatus.failed) {
      final failure = _calls.failure;
      final code = failure?.backendCode;
      _setNotice(
        code == null || code.isEmpty ? '无法拉取通话列表' : '无法拉取通话列表（$code）',
        error: true,
      );
    }
  }

  Future<void> dial() async {
    if (usesNative) {
      if (!validDialNumber(_dialNumber)) {
        _setNotice('号码无效', error: true);
        return;
      }
      if (!canDialNative) {
        _setNotice(nativeStatusLabel, error: true);
        return;
      }
      return _nativeCommand('dial', {
        'deviceId': _deviceId,
        'number': normalizeDialNumber(_dialNumber),
      });
    }
    final id = _deviceId;
    final number = normalizeDialNumber(_dialNumber);
    if (id == null || id.isEmpty) {
      _setNotice('先选设备', error: true);
      return;
    }
    if (!validDialNumber(number)) {
      _setNotice('号码无效', error: true);
      return;
    }
    final ok = await runAction<VoiceCall>(
      slot: _dial,
      current: () => _dialAction,
      set: (next) => publish(() => _dialAction = next),
      request: (ticket) =>
          repository.dial(id, number, cancellation: ticket.cancellation),
      onSuccess: (result, _) {
        _setNotice('已拨出');
        unawaited(refresh());
        return const ActionState.succeeded();
      },
      onFailure: (error) =>
          _setNotice(_errorMessage(error, '拨号失败'), error: true),
    );
    if (!ok && _dialAction.status != ActionStatus.failed) {
      // ignored when already submitting
    }
  }

  Future<void> answer(VoiceCall call, {String? uuid}) async {
    if (usesNative) {
      final local = localCall;
      final target = uuid ?? local?.uuid;
      if (nativeSnapshot?.canReceiveCalls != true ||
          local == null ||
          target != local.uuid ||
          local.deviceId != call.deviceId ||
          local.id != call.id ||
          !call.isRingingIncoming ||
          call.id.isEmpty) {
        return;
      }
      return _nativeCommand('answer', {
        'uuid': target,
        'deviceId': call.deviceId,
        'id': call.id,
      });
    }
    final id = _deviceId;
    if (id == null || id.isEmpty || call.deviceId != id || call.id.isEmpty) {
      return;
    }
    await runAction<VoiceCall>(
      slot: _answer,
      current: () => _answerAction,
      set: (next) => publish(() => _answerAction = next),
      request: (ticket) =>
          repository.answer(id, call.id, cancellation: ticket.cancellation),
      onSuccess: (result, _) {
        _setNotice('已接听');
        unawaited(refresh());
        return const ActionState.succeeded();
      },
      onFailure: (error) =>
          _setNotice(_errorMessage(error, '接听失败'), error: true),
    );
  }

  Future<void> hangup(VoiceCall call, {String? uuid}) async {
    if (usesNative) {
      final local = localCall;
      final target = uuid ?? local?.uuid;
      if (local == null ||
          target != local.uuid ||
          local.deviceId != call.deviceId ||
          local.id != call.id ||
          !canHangupNative) {
        return;
      }
      return _nativeCommand('hangup', {
        'uuid': target,
        'deviceId': call.deviceId,
        'id': call.id,
      });
    }
    final id = _deviceId;
    if (id == null || id.isEmpty || call.deviceId != id || call.id.isEmpty) {
      return;
    }
    await runAction<void>(
      slot: _hangup,
      current: () => _hangupAction,
      set: (next) => publish(() => _hangupAction = next),
      request: (ticket) async {
        try {
          await repository.hangup(
            id,
            call.id,
            cancellation: ticket.cancellation,
          );
        } on ApiFailure catch (error) {
          if (error.backendCode == 'call_not_found' ||
              error.backendCode == 'call_state') {
            return;
          }
          rethrow;
        }
      },
      onSuccess: (result, _) {
        if (_mediaCallId == call.id) unawaited(_closeMedia());
        _setNotice('已挂断');
        unawaited(refresh());
        return const ActionState.succeeded();
      },
      onFailure: (error) =>
          _setNotice(_errorMessage(error, '挂断失败'), error: true),
    );
  }

  Future<void> ensureMedia(VoiceCall call) {
    if (usesNative) return Future<void>.value();
    final id = _deviceId;
    if (isDisposed ||
        id == null ||
        id.isEmpty ||
        call.deviceId != id ||
        call.id.isEmpty ||
        !call.isLive) {
      return Future<void>.value();
    }
    if (_mediaCallId == call.id) {
      final active = _mediaInFlight;
      if (active != null) return active;
      if (_mediaSocket != null) return Future<void>.value();
    }
    final closing = _closeMedia();
    final ticket = _media.begin();
    _mediaCallId = call.id;
    final completer = Completer<void>();
    _mediaInFlight = completer.future;
    _connectMedia(id, call.id, ticket, closing).then(
      (_) => completer.complete(),
      onError: (Object error, StackTrace stack) =>
          completer.completeError(error, stack),
    );
    return completer.future;
  }

  Future<void> _connectMedia(
    String id,
    String callId,
    RequestTicket ticket,
    Future<void> closing,
  ) async {
    try {
      await closing;
      if (!ticket.isCurrent || isDisposed) return;
      final meta = await repository.fetchMediaMeta(
        id,
        callId,
        cancellation: ticket.cancellation,
      );
      if (!ticket.isCurrent || isDisposed) return;
      final origin = await originProvider();
      if (!ticket.isCurrent || isDisposed) return;
      final token = await tokenProvider(origin);
      if (!ticket.isCurrent || isDisposed) return;
      final socket = await repository.openMediaSocket(
        origin: origin,
        deviceId: id,
        callId: callId,
        accessToken: token,
      );
      if (!ticket.isCurrent || isDisposed) {
        await socket.close();
        return;
      }
      _mediaSocket = socket;
      _downlink = socket.listen(
        (dynamic event) {
          if (!identical(_mediaSocket, socket) || !_audioReady || isDisposed) {
            return;
          }
          final bytes = pcmPayload(event);
          if (bytes == null) return;
          handset.playDownlink(bytes);
          publish(() => _pcmBytes += bytes.length);
        },
        onDone: () {
          if (identical(_mediaSocket, socket)) {
            unawaited(_closeMedia());
            publish(() {});
          }
        },
        onError: (_) {
          if (!identical(_mediaSocket, socket)) return;
          unawaited(_closeMedia());
          _setNotice('媒体通道已断开', error: true);
        },
        cancelOnError: true,
      );
      await handset.attach(socket);
      if (!ticket.isCurrent || isDisposed || !identical(_mediaSocket, socket)) {
        return;
      }
      publish(() {
        _mediaMeta = meta;
        _audioReady = true;
        _pcmBytes = 0;
        _notice = '';
        _noticeError = false;
      });
    } catch (error) {
      if (ticket.isCurrent && !isDisposed) {
        final closing = _closeMedia();
        final generation = _mediaGeneration;
        await closing;
        if (generation == _mediaGeneration && !isDisposed) {
          _setNotice(_errorMessage(error, '媒体通道未接通'), error: true);
        }
      }
    } finally {
      if (ticket.isCurrent) _mediaInFlight = null;
      ticket.end();
    }
  }

  void syncDevices(List<DeviceSnapshot> devices) {
    if (_deviceId != null && devices.any((device) => device.id == _deviceId)) {
      return;
    }
    selectDevice(devices.isEmpty ? null : devices.first.id);
  }

  @override
  void dispose() {
    if (isDisposed) return;
    nativeCalls?.removeListener(_nativeChanged);
    _poll?.cancel();
    super.dispose();
    if (!usesNative) unawaited(_closeMedia());
  }

  Future<void> _closeMedia() {
    final generation = ++_mediaGeneration;
    _media.cancel();
    _mediaInFlight = null;
    final socket = _mediaSocket;
    final downlink = _downlink;
    _mediaSocket = null;
    _audioReady = false;
    _downlink = null;
    _mediaCallId = null;
    _pcmBytes = 0;
    _mediaMeta = null;
    // Start stop immediately to cancel a pending permission request. Join every
    // resource independently so a stop failure cannot skip socket release.
    Future<void> settle(Future<dynamic> Function() action) async {
      try {
        await action();
      } catch (error) {
        if (generation == _mediaGeneration && !isDisposed) {
          _setNotice(_errorMessage(error, '音频停止失败'), error: true);
        }
      }
    }

    _mediaClosing = Future.wait<void>([
      _mediaClosing,
      if (downlink != null) settle(downlink.cancel),
      settle(handset.detach),
      if (socket != null) settle(socket.close),
    ]).then((_) {});
    return _mediaClosing;
  }

  void _setNotice(String text, {bool error = false}) => publish(() {
    _nativeOwnsNotice = false;
    _notice = text;
    _noticeError = error;
  });

  String _errorMessage(Object error, String fallback) {
    if (error is PlatformException) {
      final message = error.message;
      return message == null || message.isEmpty
          ? '$fallback（${error.code}）'
          : '$fallback：$message';
    }
    if (error is ApiFailure) {
      final code = error.backendCode;
      if (code != null && code.isNotEmpty) return '$fallback（$code）';
      if (error.message.isNotEmpty) return error.message;
    }
    return fallback;
  }
}
