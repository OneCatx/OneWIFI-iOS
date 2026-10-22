import '../domain/call.dart';

/// Strict, versioned projection; no truthy coercion at this trust boundary.
final class NativeCallSnapshot {
  NativeCallSnapshot._(
    this.generation,
    this.revision,
    this.status,
    this.eventStatus,
    this.foreground,
    this.permissions,
    this.canReceiveCalls,
    this.devices,
    this.local,
    this.error,
    this.eventError,
    this.eventDiagnostic,
    this.systemDiagnostic,
    this.audioDiagnostic,
  );
  factory NativeCallSnapshot.decode(Object? value) {
    final m = _map(value);
    if (_integer(m['schemaVersion']) != 1) _bad();
    final status = _enum(m['status'], {
      'unconfigured',
      'configured',
      'unauthorized',
    });
    final events = _enum(m['eventStatus'], {
      'connecting',
      'connected',
      'offline',
      'stale',
      'unauthorized',
      'unavailable',
      'failed',
      'stopped',
    });
    final foreground = _boolean(m['foreground']);
    final permissions = _map(
      m['permissions'],
    ).map((k, v) => MapEntry(k, _boolean(v)));
    if (!permissions.containsKey('microphone')) _bad();
    final enabled = _boolean(m['canReceiveCalls']);
    final ids = <String>{};
    final devices = <NativeCallDevice>[];
    for (final raw in _list(m['devices'])) {
      final d = _map(raw);
      final id = _string(d['device_id'], nonEmpty: true);
      if (!ids.add(id)) _bad();
      final callIds = <String>{};
      final calls = <VoiceCall>[];
      for (final rawCall in _list(d['calls'])) {
        final c = _map(rawCall);
        final callId = _string(c['id'], nonEmpty: true);
        if (!callIds.add(callId)) _bad();
        final ended = _time(c['ended_at']);
        final state = _enum(c['state'], {
          'ringing',
          'dialing',
          'early_media',
          'answering',
          'active',
          'ended',
          'failed',
        });
        calls.add(
          VoiceCall(
            id: callId,
            deviceId: id,
            number: _string(c['number']),
            direction:
                _enum(c['direction'], {'incoming', 'outgoing'}) == 'incoming'
                ? CallDirection.incoming
                : CallDirection.outgoing,
            state: ended != null
                ? CallLifecycle.ended
                : switch (state) {
                    'ringing' => CallLifecycle.ringing,
                    'dialing' => CallLifecycle.dialing,
                    'early_media' => CallLifecycle.earlyMedia,
                    'active' => CallLifecycle.active,
                    'ended' => CallLifecycle.ended,
                    'failed' => CallLifecycle.failed,
                    _ => CallLifecycle.unknown,
                  },
            mediaReady: _boolean(c['media_ready']),
            startedAt: _time(c['started_at']),
            endedAt: ended,
          ),
        );
      }
      devices.add(
        NativeCallDevice(
          id,
          _string(d['label']),
          _boolean(d['ready']),
          List.unmodifiable(calls),
        ),
      );
    }
    return NativeCallSnapshot._(
      _integer(m['generation']),
      _integer(m['revision']),
      status,
      events,
      foreground,
      Map.unmodifiable(permissions),
      enabled &&
          foreground &&
          permissions['microphone'] == true &&
          status == 'configured' &&
          events == 'connected',
      List.unmodifiable(devices),
      m['local'] == null ? null : NativeLocalCall.decode(m['local']),
      _string(m['error']),
      m.containsKey('eventError') ? _string(m['eventError']) : '',
      m.containsKey('eventDiagnostic') ? _string(m['eventDiagnostic']) : '',
      m.containsKey('systemDiagnostic') ? _string(m['systemDiagnostic']) : '',
      m.containsKey('audioDiagnostic') ? _string(m['audioDiagnostic']) : '',
    );
  }
  final int generation, revision;
  final String status, eventStatus, error, eventError, eventDiagnostic, systemDiagnostic, audioDiagnostic;
  final bool foreground, canReceiveCalls;
  final Map<String, bool> permissions;
  final List<NativeCallDevice> devices;
  final NativeLocalCall? local;
  bool get isFresh => status == 'configured' && eventStatus == 'connected';
}

final class NativeCallDevice {
  const NativeCallDevice(this.id, this.label, this.ready, this.calls);
  final String id, label;
  final bool ready;
  final List<VoiceCall> calls;
}

final class NativeLocalCall {
  NativeLocalCall.decode(Object? value) : this._(_map(value));
  NativeLocalCall._(Map<String, Object?> m)
    : deviceId = _string(m['deviceId']),
      id = _string(m['id']),
      number = _string(m['number']),
      label = _string(m['label']),
      direction = _enum(m['direction'], {'incoming', 'outgoing'}),
      phase = _enum(m['phase'], {
        'ringing',
        'dialing',
        'early_media',
        'answering',
        'connecting_audio',
        'active',
        'disconnecting',
        'failed',
      }),
      error = _string(m['error']),
      muted = _boolean(m['muted']),
      systemMuted = _boolean(m['systemMuted']),
      audioReady = _boolean(m['audioReady']),
      dtmfSupported = _boolean(m['dtmfSupported']),
      owned = _boolean(m['owned']),
      actionPending = _boolean(m['actionPending']),
      uuid = _string(m['uuid']),
      sentFrames = _integer(m['sentFrames']),
      receivedFrames = _integer(m['receivedFrames']),
      endpoint = _string(m['endpoint']),
      endpoints = _endpoints(m['endpoints']),
      startedAt = _time(m['startedAt']);
  final String deviceId,
      id,
      number,
      label,
      direction,
      phase,
      error,
      endpoint,
      uuid;
  final bool muted,
      systemMuted,
      audioReady,
      dtmfSupported,
      owned,
      actionPending;
  final int sentFrames, receivedFrames;
  final List<NativeAudioEndpoint> endpoints;
  final DateTime? startedAt;
  bool get hasCall => phase != 'failed';
  bool get canControlAudio =>
      owned && audioReady && phase == 'active' && !actionPending;
  String get phaseLabel => switch (phase) {
    'ringing' => '来电',
    'dialing' => '正在拨号…',
    'early_media' => '等待对方接听',
    'answering' => '正在接听…',
    'connecting_audio' => '正在连接声音…',
    'active' => audioReady ? '通话中' : '声音尚未连接',
    'disconnecting' => '正在挂断…',
    _ => '通话失败',
  };
  VoiceCall get call => VoiceCall(
    id: id,
    deviceId: deviceId,
    number: number,
    direction: direction == 'incoming'
        ? CallDirection.incoming
        : CallDirection.outgoing,
    state: phase == 'ringing' ? CallLifecycle.ringing : CallLifecycle.active,
  );
}

final class NativeAudioEndpoint {
  const NativeAudioEndpoint(this.id, this.name);
  final String id, name;
}

List<NativeAudioEndpoint> _endpoints(Object? value) {
  final ids = <String>{};
  return List.unmodifiable(
    _list(value).map((raw) {
      final m = _map(raw);
      final id = _string(m['id'], nonEmpty: true);
      if (!ids.add(id)) _bad();
      return NativeAudioEndpoint(id, _string(m['name'], nonEmpty: true));
    }),
  );
}

Never _bad() => throw const FormatException('Invalid native call snapshot');
Map<String, Object?> _map(Object? v) {
  if (v is! Map || v.keys.any((k) => k is! String)) _bad();
  return Map<String, Object?>.from(v);
}

List<Object?> _list(Object? v) => v is List ? v : _bad();
String _string(Object? v, {bool nonEmpty = false}) =>
    v is String && (!nonEmpty || v.isNotEmpty) ? v : _bad();
bool _boolean(Object? v) => v is bool ? v : _bad();
int _integer(Object? v) => v is int && v >= 0 ? v : _bad();
String _enum(Object? v, Set<String> values) =>
    v is String && values.contains(v) ? v : _bad();
DateTime? _time(Object? v) {
  if (v == null || v == '') return null;
  final raw = _string(v);
  if (raw.startsWith('0001-')) return null;
  return DateTime.tryParse(raw) ?? _bad();
}
