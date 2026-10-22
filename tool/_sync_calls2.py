import pathlib
root = pathlib.Path(r'E:\GQ\Ultra\ONEWIFI\android')

def write(rel, text):
    p = root/rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8', newline='\n')
    print('WROTE', rel)

# Fix openMediaSocket in calls_api
api = (root/'lib/features/calls/data/calls_api.dart').read_text(encoding='utf-8')
old = '''  Future<WebSocket> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  }) async {
    final path =
        '/api/devices/${Uri.encodeComponent(deviceId)}/calls/media'
        '?id=${Uri.encodeComponent(callId)}';
    final wsScheme = origin.scheme == 'https' ? 'wss' : 'ws';
    final ws = origin.replace(scheme: wsScheme, path: '', query: '');
    final base = Uri.parse('$ws$path');
    final uri = accessToken == null || accessToken.isEmpty
        ? base
        : base.replace(
            queryParameters: <String, String>{
              ...base.queryParameters,
              'access_token': accessToken,
            },
          );
    return WebSocket.connect(uri.toString());
  }
}'''
new = '''  Future<WebSocket> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  }) async {
    final scheme = origin.scheme == 'https' ? 'wss' : 'ws';
    final query = <String, String>{'id': callId};
    if (accessToken != null && accessToken.isNotEmpty) {
      query['access_token'] = accessToken;
    }
    final uri = Uri(
      scheme: scheme,
      host: origin.host,
      port: origin.hasPort ? origin.port : null,
      path: '/api/devices/${Uri.encodeComponent(deviceId)}/calls/media',
      queryParameters: query,
    );
    return WebSocket.connect(uri.toString());
  }
}'''
if old in api:
    api = api.replace(old, new)
    write('lib/features/calls/data/calls_api.dart', api)
else:
    print('WARN openMediaSocket block not found exact')

write('lib/features/calls/state/calls_controller.dart', r'''import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/http/http_transport.dart';
import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../../devices/domain/device.dart';
import '../data/calls_repository.dart';
import '../domain/call.dart';

final class CallsController extends RequestNotifier {
  CallsController({
    required this.repository,
    required this.originProvider,
    required this.tokenProvider,
    required RequestRegistry requestRegistry,
  }) : _read = RequestSlot(requestRegistry, 'calls.load'),
       _dial = RequestSlot(requestRegistry, 'calls.dial'),
       _answer = RequestSlot(requestRegistry, 'calls.answer'),
       _hangup = RequestSlot(requestRegistry, 'calls.hangup');

  final CallsRepository repository;
  final Future<Uri> Function() originProvider;
  final Future<String?> Function(Uri origin) tokenProvider;
  final RequestSlot _read;
  final RequestSlot _dial;
  final RequestSlot _answer;
  final RequestSlot _hangup;

  QueryState<List<VoiceCall>> _calls =
      const QueryState<List<VoiceCall>>.initial(key: 'calls.load');
  ActionState _dialAction = const ActionState.idle();
  ActionState _answerAction = const ActionState.idle();
  ActionState _hangupAction = const ActionState.idle();
  String? _deviceId;
  String _dialNumber = '';
  String _notice = '';
  bool _noticeError = false;
  WebSocket? _mediaSocket;
  String? _mediaCallId;
  int _pcmBytes = 0;
  CallMediaMeta? _mediaMeta;
  Timer? _poll;

  QueryState<List<VoiceCall>> get calls => _calls;
  List<VoiceCall> get items => _calls.lastGoodData ?? const <VoiceCall>[];
  ActionState get dialAction => _dialAction;
  ActionState get answerAction => _answerAction;
  ActionState get hangupAction => _hangupAction;
  String? get deviceId => _deviceId;
  String get dialNumber => _dialNumber;
  String get notice => _notice;
  bool get noticeError => _noticeError;
  CallMediaMeta? get mediaMeta => _mediaMeta;
  int get pcmBytes => _pcmBytes;
  bool get mediaConnected => _mediaSocket != null;

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
  List<RequestSlot> get slots => <RequestSlot>[_read, _dial, _answer, _hangup];

  void selectDevice(String? id) {
    if (_deviceId == id) return;
    _deviceId = id;
    _dialNumber = '';
    _notice = '';
    unawaited(_closeMedia());
    publish(() {});
    if (id != null && id.isNotEmpty) {
      unawaited(refresh());
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(refresh(quiet: true));
      });
    } else {
      _poll?.cancel();
      _poll = null;
    }
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

  Future<void> refresh({bool quiet = false}) async {
    final id = _deviceId;
    if (id == null || id.isEmpty || isDisposed) return;
    final ticket = _read.begin();
    final previous = _calls.lastGoodData;
    if (!quiet) {
      _setCalls(QueryState.pending(previous: previous, key: _read.key));
    }
    try {
      final list = await repository.fetchCalls(
        id,
        cancellation: ticket.cancellation,
      );
      if (!ticket.isCurrent) return;
      _setCalls(QueryState<List<VoiceCall>>.data(data: list, key: _read.key));
      final handset = handsetCall;
      if (handset != null && handset.mediaReady) {
        unawaited(ensureMedia(handset));
      }
    } catch (error) {
      if (!ticket.isCurrent) return;
      if (!quiet) {
        _setCalls(
          QueryState.failedAfter(error, previous: previous, key: _read.key),
        );
        _setNotice(_errorMessage(error, '无法拉取通话列表'), error: true);
      }
    } finally {
      ticket.finish();
    }
  }

  Future<void> dial() async {
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
    await _runAction<VoiceCall>(
      slot: _dial,
      current: () => _dialAction,
      set: _setDialAction,
      request: (_) => repository.dial(id, number),
      onSuccess: (_) {
        unawaited(refresh());
      },
      okNotice: (_) => '已拨出',
      failNotice: '拨号失败',
    );
  }

  Future<void> answer(VoiceCall call) async {
    final id = _deviceId;
    if (id == null) return;
    await _runAction<VoiceCall>(
      slot: _answer,
      current: () => _answerAction,
      set: _setAnswerAction,
      request: (_) => repository.answer(id, call.id),
      onSuccess: (_) => unawaited(refresh()),
      okNotice: (_) => '已接听',
      failNotice: '接听失败',
    );
  }

  Future<void> hangup(VoiceCall call) async {
    final id = _deviceId;
    if (id == null) return;
    await _runAction<void>(
      slot: _hangup,
      current: () => _hangupAction,
      set: _setHangupAction,
      request: (_) async {
        try {
          await repository.hangup(id, call.id);
        } on ApiFailure catch (error) {
          // Ended hangup counts as success per contract.
          if (error.backendCode == 'call_not_found' ||
              error.backendCode == 'call_state') {
            return;
          }
          rethrow;
        }
      },
      onSuccess: (_) {
        unawaited(_closeMedia());
        unawaited(refresh());
      },
      okNotice: (_) => '已挂断',
      failNotice: '挂断失败',
    );
  }

  Future<void> ensureMedia(VoiceCall call) async {
    if (_mediaCallId == call.id && _mediaSocket != null) return;
    final id = _deviceId;
    if (id == null) return;
    try {
      final meta = await repository.fetchMediaMeta(id, call.id);
      final origin = await originProvider();
      final token = await tokenProvider(origin);
      await _closeMedia();
      final socket = await repository.openMediaSocket(
        origin: origin,
        deviceId: id,
        callId: call.id,
        accessToken: token,
      );
      publish(() {
        _mediaMeta = meta;
        _mediaCallId = call.id;
        _mediaSocket = socket;
        _pcmBytes = 0;
      });
      socket.listen(
        (dynamic event) {
          if (event is List<int>) {
            publish(() => _pcmBytes += event.length);
          } else if (event is ByteBuffer) {
            publish(() => _pcmBytes += event.lengthInBytes);
          }
        },
        onDone: () {
          if (_mediaCallId == call.id) {
            publish(() {
              _mediaSocket = null;
              _mediaCallId = null;
            });
          }
        },
        onError: (_) {
          if (_mediaCallId == call.id) {
            publish(() {
              _mediaSocket = null;
              _mediaCallId = null;
            });
          }
        },
        cancelOnError: true,
      );
    } catch (error) {
      _setNotice(_errorMessage(error, '媒体通道未接通'), error: true);
    }
  }

  void syncDevices(List<DeviceSnapshot> devices) {
    if (_deviceId != null &&
        devices.any((device) => device.id == _deviceId)) {
      return;
    }
    final next = devices.isEmpty ? null : devices.first.id;
    selectDevice(next);
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_closeMedia());
    super.dispose();
  }

  Future<void> _closeMedia() async {
    final socket = _mediaSocket;
    _mediaSocket = null;
    _mediaCallId = null;
    _pcmBytes = 0;
    _mediaMeta = null;
    await socket?.close();
  }

  void _setCalls(QueryState<List<VoiceCall>> next) =>
      publish(() => _calls = next);

  void _setDialAction(ActionState next) => publish(() => _dialAction = next);

  void _setAnswerAction(ActionState next) =>
      publish(() => _answerAction = next);

  void _setHangupAction(ActionState next) =>
      publish(() => _hangupAction = next);

  void _setNotice(String text, {bool error = false}) => publish(() {
    _notice = text;
    _noticeError = error;
  });

  String _errorMessage(Object error, String fallback) {
    if (error is ApiFailure) {
      final code = error.backendCode;
      if (code != null && code.isNotEmpty) return '$fallback（$code）';
      if (error.message.isNotEmpty) return error.message;
    }
    return fallback;
  }
}
''')

write('lib/features/calls/presentation/calls_screen.dart', r'''import 'package:flutter/material.dart';

import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../../devices/domain/device.dart';
import '../../devices/state/device_list_controller.dart';
import '../domain/call.dart';
import '../state/calls_controller.dart';

final class CallsScreen extends StatefulWidget {
  const CallsScreen({
    required this.calls,
    required this.devices,
    super.key,
  });

  static const Key rootKey = Key('calls-screen');

  final CallsController calls;
  final DeviceListController devices;

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

final class _CallsScreenState extends State<CallsScreen> {
  @override
  void initState() {
    super.initState();
    widget.calls.addListener(_onChanged);
    widget.devices.addListener(_onDevices);
    _onDevices();
  }

  @override
  void dispose() {
    widget.calls.removeListener(_onChanged);
    widget.devices.removeListener(_onDevices);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onDevices() {
    final fleet = widget.devices.snapshot.lastGoodData;
    final list = fleet?.devices ?? const <DeviceSnapshot>[];
    widget.calls.syncDevices(list);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final calls = widget.calls;
    final fleet = widget.devices.snapshot.lastGoodData;
    final devices = fleet?.devices ?? const <DeviceSnapshot>[];
    final theme = Theme.of(context);

    return ListView(
      key: CallsScreen.rootKey,
      padding: OneInsets.scroll(context),
      children: <Widget>[
        const OwPageHead(title: '通话', desc: 'Bearer 下的 VoWiFi 拨号 / 接听 / 挂断与媒体通道'),
        const SizedBox(height: OneSpacing.item),
        if (calls.notice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: OneSpacing.item),
            child: Text(
              calls.notice,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: calls.noticeError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        OwSection(
          title: '设备',
          icon: Icons.devices_other_outlined,
          tone: PlateTone.blue,
          child: devices.isEmpty
              ? const Text('还没有设备，先去设备页确认在线。')
              : Wrap(
                  spacing: OneSpacing.item,
                  runSpacing: OneSpacing.item,
                  children: [
                    for (final device in devices)
                      ChoiceChip(
                        label: Text(device.name),
                        selected: calls.deviceId == device.id,
                        onSelected: (_) => calls.selectDevice(device.id),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: OneSpacing.medium),
        OwSection(
          title: '拨号盘',
          icon: Icons.dialpad_outlined,
          tone: PlateTone.blue,
          child: Column(
            children: <Widget>[
              TextField(
                key: const Key('calls-dial-field'),
                controller: TextEditingController(text: calls.dialNumber)
                  ..selection = TextSelection.collapsed(
                    offset: calls.dialNumber.length,
                  ),
                onChanged: calls.setDialNumber,
                decoration: const InputDecoration(
                  labelText: '号码',
                  hintText: '+4477…',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: OneSpacing.item),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                childAspectRatio: 2.2,
                children: [
                  for (final key in const [
                    '1','2','3','4','5','6','7','8','9','*','0','#',
                  ])
                    TextButton(
                      onPressed: () => calls.appendKey(key),
                      child: Text(key, style: theme.textTheme.titleLarge),
                    ),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: GlassActionButton(
                      icon: Icons.backspace_outlined,
                      label: '退格',
                      onPressed: calls.backspace,
                    ),
                  ),
                  const SizedBox(width: OneSpacing.item),
                  Expanded(
                    child: GlassActionButton(
                      key: const Key('calls-dial-button'),
                      icon: Icons.call,
                      label: calls.dialAction.status == ActionStatus.submitting
                          ? '拨号中…'
                          : '拨出',
                      busy: calls.dialAction.status == ActionStatus.submitting,
                      onPressed: calls.deviceId == null ? null : calls.dial,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: OneSpacing.medium),
        if (calls.calls.status == QueryStatus.pending && calls.items.isEmpty)
          const OneStatusHero(
            tone: OneStatusTone.attention,
            title: '加载通话',
            message: '正在拉取通话列表…',
            showStages: false,
          )
        else if (calls.calls.status == QueryStatus.failed && calls.items.isEmpty)
          OneStatusHero(
            tone: OneStatusTone.danger,
            title: '通话列表失败',
            message: calls.notice.isEmpty ? '稍后重试' : calls.notice,
            showStages: false,
          )
        else ...<Widget>[
          OwSection(
            title: '进行中',
            icon: Icons.phone_in_talk_outlined,
            tone: PlateTone.blue,
            actions: GlassActionButton(
              icon: Icons.refresh,
              label: '刷新',
              onPressed: () => calls.refresh(),
            ),
            child: calls.liveCalls.isEmpty
                ? const Text('没有进行中的通话')
                : Column(
                    children: [
                      for (final call in calls.liveCalls)
                        _CallTile(call: call, controller: calls),
                    ],
                  ),
          ),
          const SizedBox(height: OneSpacing.medium),
          OwSection(
            title: '历史',
            icon: Icons.history,
            tone: PlateTone.blue,
            child: calls.historyCalls.isEmpty
                ? const Text('还没有历史通话')
                : Column(
                    children: [
                      for (final call in calls.historyCalls.take(20))
                        _CallTile(call: call, controller: calls, history: true),
                    ],
                  ),
          ),
          if (calls.mediaMeta != null || calls.mediaConnected) ...<Widget>[
            const SizedBox(height: OneSpacing.medium),
            OwSection(
              title: '媒体',
              icon: Icons.graphic_eq,
              tone: PlateTone.blue,
              child: Text(
                [
                  if (calls.mediaMeta case final meta?)
                    '格式 ${meta.format.isEmpty ? meta.codec : meta.format}'
                        '${meta.stream.isEmpty ? '' : ' · ${meta.stream}'}',
                  calls.mediaConnected ? 'WebSocket 已连接' : 'WebSocket 未连接',
                  if (calls.pcmBytes > 0) '已收 PCM ${calls.pcmBytes} bytes',
                ].join('\n'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

final class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.call,
    required this.controller,
    this.history = false,
  });

  final VoiceCall call;
  final CallsController controller;
  final bool history;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${call.directionLabel} ${call.number}'.trim()),
      subtitle: Text(
        [
          call.stateLabel,
          if (call.mediaReady) 'media_ready',
          if (call.startedAt != null) call.startedAt!.toLocal().toString(),
        ].join(' · '),
      ),
      trailing: history
          ? null
          : Wrap(
              spacing: 8,
              children: [
                if (call.isRingingIncoming)
                  IconButton(
                    tooltip: '接听',
                    onPressed: () => controller.answer(call),
                    icon: const Icon(Icons.call),
                  ),
                IconButton(
                  tooltip: '挂断',
                  onPressed: () => controller.hangup(call),
                  icon: const Icon(Icons.call_end),
                ),
                if (call.mediaReady)
                  IconButton(
                    tooltip: '媒体',
                    onPressed: () => controller.ensureMedia(call),
                    icon: const Icon(Icons.hearing),
                  ),
              ],
            ),
    );
  }
}
''')

print('controller+screen ok')
