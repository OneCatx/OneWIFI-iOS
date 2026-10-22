import 'dart:async';
import 'package:flutter/services.dart';

final class OtpActivitySnapshot {
  const OtpActivitySnapshot({
    required this.scopeId,
    required this.activityId,
    required this.updateToken,
    required this.revision,
    required this.startedAt,
    required this.expiresAt,
    required this.state,
  });
  final String scopeId, activityId, updateToken, state;
  final int revision, startedAt, expiresAt;
  bool get active =>
      state == 'active' &&
      activityId.isNotEmpty &&
      RegExp(r'^(?:[0-9a-f]{2})+$').hasMatch(updateToken) &&
      revision > 0;
  Map<String, Object> get payload => {
    'activity_id': activityId,
    'update_token': updateToken,
    'revision': revision,
    'started_at': startedAt,
    'expires_at': expiresAt,
    'state': state,
  };
  String get identity => '$scopeId/$activityId/$revision/$state/$updateToken';
  OtpActivitySnapshot withExpiry(int expiry) => OtpActivitySnapshot(
    scopeId: scopeId,
    activityId: activityId,
    updateToken: updateToken,
    revision: revision,
    startedAt: startedAt,
    expiresAt: expiry,
    state: state,
  );
  static OtpActivitySnapshot? parse(Object? raw) {
    if (raw is! Map ||
        raw['scope_id'] is! String ||
        raw['activity_id'] is! String ||
        raw['update_token'] is! String ||
        raw['revision'] is! int ||
        raw['started_at'] is! int ||
        raw['expires_at'] is! int ||
        raw['state'] is! String) {
      return null;
    }
    return OtpActivitySnapshot(
      scopeId: raw['scope_id'] as String,
      activityId: raw['activity_id'] as String,
      updateToken: raw['update_token'] as String,
      revision: raw['revision'] as int,
      startedAt: raw['started_at'] as int,
      expiresAt: raw['expires_at'] as int,
      state: raw['state'] as String,
    );
  }
}

final class OtpActivityBridge {
  OtpActivityBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.oneims.onewifi/otp') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'activityState') {
        final value = OtpActivitySnapshot.parse(call.arguments);
        if (!_disposed && value != null) _changes.add(value);
      }
    });
  }
  final MethodChannel _channel;
  final _changes = StreamController<OtpActivitySnapshot>.broadcast();
  bool _disposed = false;
  Stream<OtpActivitySnapshot> get changes => _changes.stream;
  Future<String> scopeIdentifier(String digest) async =>
      await _channel.invokeMethod<String>('scopeIdentifier', {
        'scope_key': digest,
      }) ??
      '';
  Future<OtpActivitySnapshot?> prepare(String scope) async =>
      OtpActivitySnapshot.parse(
        await _channel.invokeMethod<Object?>('prepareActivity', {
          'scope_id': scope,
        }),
      );
  Future<OtpActivitySnapshot?> snapshot() async => OtpActivitySnapshot.parse(
    await _channel.invokeMethod<Object?>('activityState'),
  );
  Future<List<OtpActivitySnapshot>> pendingEnds(String scope) async {
    final values = await _channel.invokeMethod<Object?>('pendingActivityEnds', {
      'scope_id': scope,
    });
    if (values is! List) return [];
    return values
        .map(OtpActivitySnapshot.parse)
        .whereType<OtpActivitySnapshot>()
        .where(
          (value) =>
              value.scopeId == scope &&
              {'ended', 'dismissed'}.contains(value.state),
        )
        .toList();
  }

  Future<void> acknowledgeEnd(OtpActivitySnapshot value) =>
      _channel.invokeMethod<void>('acknowledgeActivityEnd', {
        'scope_id': value.scopeId,
        'activity_id': value.activityId,
        'revision': value.revision,
      });
  Future<OtpActivitySnapshot?> end(String scope) async =>
      OtpActivitySnapshot.parse(
        await _channel.invokeMethod<Object?>('endActivity', {
          'scope_id': scope,
        }),
      );
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_changes.close());
  }
}
