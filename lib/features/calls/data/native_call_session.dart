import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../core/security/session_resource.dart';
import 'native_call_snapshot.dart';

abstract interface class NativeCallView implements Listenable {
  NativeCallSnapshot? get snapshot;
  String get status;
  Future<void> execute(String method, Map<String, Object?> values);
}

abstract interface class NativeCallSession implements SessionResource {
  Future<void> configure({
    required Uri origin,
    required String token,
    required DateTime? expiresAt,
    required String? certificateFingerprint,
  });
  Stream<NativeCallSnapshot> get states;
  Future<NativeCallSnapshot> snapshot();
  Future<void> command(String method, Map<String, Object?> values);
}

final class IOSNativeCallSession implements NativeCallSession {
  const IOSNativeCallSession();
  static const channel = MethodChannel('com.oneims.onewifi/call_session');
  static const events = EventChannel('com.oneims.onewifi/call_session/events');
  @override
  Future<void> configure({
    required Uri origin,
    required String token,
    required DateTime? expiresAt,
    required String? certificateFingerprint,
  }) => channel.invokeMethod<void>('configure', {
    'origin': origin.toString(),
    'token': token,
    'expiresAt': expiresAt?.toUtc().millisecondsSinceEpoch,
    'certificateFingerprint': certificateFingerprint,
  });
  @override
  Future<void> clear() => channel.invokeMethod<void>('clear');
  @override
  Stream<NativeCallSnapshot> get states =>
      events.receiveBroadcastStream().map(NativeCallSnapshot.decode);
  @override
  Future<NativeCallSnapshot> snapshot() async => NativeCallSnapshot.decode(
    await channel.invokeMethod<Object?>('snapshot'),
  );
  @override
  Future<void> command(String method, Map<String, Object?> values) =>
      channel.invokeMethod<void>(method, values);
}
