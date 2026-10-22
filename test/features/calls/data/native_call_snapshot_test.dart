import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/calls/data/native_call_snapshot.dart';

Map<String, Object?> snapshotWire({
  int generation = 2,
  int revision = 4,
  Map<String, Object?>? local,
}) => {
  'schemaVersion': 1,
  'generation': generation,
  'revision': revision,
  'status': 'configured',
  'eventStatus': 'connected',
  'canReceiveCalls': true,
  'foreground': true,
  'permissions': {'microphone': true},
  'devices': [deviceWire()],
  'local': local,
  'error': '',
};
Map<String, Object?> deviceWire() => {
  'device_id': 'A',
  'label': 'Device A',
  'ready': true,
  'calls': [
    {
      'id': 'c1',
      'number': '10086',
      'direction': 'incoming',
      'state': 'ringing',
      'media_ready': false,
    },
  ],
};
Map<String, Object?> localWire() => {
  'deviceId': 'A',
  'id': 'c1',
  'number': '10086',
  'label': 'Device A',
  'direction': 'incoming',
  'phase': 'active',
  'error': '',
  'muted': false,
  'systemMuted': false,
  'audioReady': true,
  'dtmfSupported': false,
  'sentFrames': 0,
  'receivedFrames': 0,
  'endpoint': 'receiver',
  'endpoints': [
    {'id': 'receiver', 'name': '听筒'},
    {'id': 'speaker', 'name': '扬声器'},
  ],
  'uuid': 'uuid-1',
  'owned': true,
  'actionPending': false,
  'startedAt': null,
};
void main() {
  test('audio diagnostic is optional and strictly typed', () {
    expect(NativeCallSnapshot.decode(snapshotWire()).audioDiagnostic, '');
    const detail = 'AUDIO-D1 txQueued=19 txDropped=4 rxQueued=0 rxDropped=0';
    expect(NativeCallSnapshot.decode(snapshotWire()..['audioDiagnostic'] = detail).audioDiagnostic, detail);
    for (final invalid in [null, 42, true, <Object?>[], <String, Object?>{}]) {
      expect(() => NativeCallSnapshot.decode(snapshotWire()..['audioDiagnostic'] = invalid), throwsFormatException);
    }
  });
  test('system diagnostic is optional and strictly typed', () {
    expect(NativeCallSnapshot.decode(snapshotWire()).systemDiagnostic, '');
    const detail = 'CK-D1\nstage=transaction action=start\n'
        'error domain=com.apple.CallKit.error.requesttransaction code=2';
    expect(
      NativeCallSnapshot.decode(snapshotWire()..['systemDiagnostic'] = detail)
          .systemDiagnostic,
      detail,
    );
    for (final invalid in [null, 42, true, <Object?>[], <String, Object?>{}]) {
      expect(
        () => NativeCallSnapshot.decode(snapshotWire()..['systemDiagnostic'] = invalid),
        throwsFormatException,
      );
    }
  });
  test('TLS diagnostic is optional and strictly typed', () {
    expect(NativeCallSnapshot.decode(snapshotWire()).eventDiagnostic, '');
    const detail = 'TLS-D1\npinConfigured=true sessionStage=accepted\nSSE URL:-1200';
    expect(
      NativeCallSnapshot.decode(
        snapshotWire()..['eventDiagnostic'] = detail,
      ).eventDiagnostic,
      detail,
    );
    expect(
      () => NativeCallSnapshot.decode(
        snapshotWire()..['eventDiagnostic'] = 42,
      ),
      throwsFormatException,
    );
  });
  test(
    'event error is optional for schema one and strictly typed when present',
    () {
      expect(NativeCallSnapshot.decode(snapshotWire()).eventError, '');
      expect(
        NativeCallSnapshot.decode(
          snapshotWire()..['eventError'] = 'call_trust',
        ).eventError,
        'call_trust',
      );
      for (final invalid in [
        null,
        42,
        true,
        <Object?>[],
        <String, Object?>{},
      ]) {
        expect(
          () => NativeCallSnapshot.decode(
            snapshotWire()..['eventError'] = invalid,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('native schema projects ready devices and local owner', () {
    final state = NativeCallSnapshot.decode(snapshotWire(local: localWire()));
    expect(state.devices.single.calls.single.id, 'c1');
    expect(state.local!.owned, isTrue);
    expect(state.canReceiveCalls, isTrue);
  });
  for (final field in [
    'schemaVersion',
    'generation',
    'revision',
    'foreground',
    'canReceiveCalls',
  ]) {
    test('rejects invalid $field type', () {
      final wire = snapshotWire()..[field] = '1';
      expect(() => NativeCallSnapshot.decode(wire), throwsFormatException);
    });
  }
  test('rejects schema drift and malformed permission', () {
    expect(
      () => NativeCallSnapshot.decode(snapshotWire()..['schemaVersion'] = 2),
      throwsFormatException,
    );
    expect(
      () => NativeCallSnapshot.decode(
        snapshotWire()..['permissions'] = {'microphone': 'true'},
      ),
      throwsFormatException,
    );
  });
  test('rejects duplicate device, call and audio endpoint ids', () {
    expect(
      () => NativeCallSnapshot.decode(
        snapshotWire()..['devices'] = [deviceWire(), deviceWire()],
      ),
      throwsFormatException,
    );
    final device = deviceWire();
    device['calls'] = [...device['calls'] as List, ...device['calls'] as List];
    expect(
      () => NativeCallSnapshot.decode(snapshotWire()..['devices'] = [device]),
      throwsFormatException,
    );
    final local = localWire()
      ..['endpoints'] = [
        {'id': 'speaker', 'name': 'a'},
        {'id': 'speaker', 'name': 'b'},
      ];
    expect(
      () => NativeCallSnapshot.decode(snapshotWire(local: local)),
      throwsFormatException,
    );
  });
  test('rejects truthy local audio and gateway media flags', () {
    expect(
      () => NativeCallSnapshot.decode(
        snapshotWire(local: localWire()..['audioReady'] = 1),
      ),
      throwsFormatException,
    );
    final device = deviceWire();
    (device['calls'] as List).first['media_ready'] = 'true';
    expect(
      () => NativeCallSnapshot.decode(snapshotWire()..['devices'] = [device]),
      throwsFormatException,
    );
  });
  test(
    'readiness requires foreground and microphone independently of native flag',
    () {
      expect(
        NativeCallSnapshot.decode(
          snapshotWire()..['permissions'] = {'microphone': false},
        ).canReceiveCalls,
        isFalse,
      );
      expect(
        NativeCallSnapshot.decode(
          snapshotWire()..['foreground'] = false,
        ).canReceiveCalls,
        isFalse,
      );
    },
  );
}
