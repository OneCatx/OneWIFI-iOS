import pathlib
root = pathlib.Path(r"E:\GQ\Ultra\ONEWIFI\android")
sgt = root/"test/app/session_gate_test.dart"
t = sgt.read_text(encoding="utf-8")

if "calls/state/calls_controller.dart" not in t:
    t = t.replace(
        "import 'package:onewifi_android/features/sms/state/sms_controller.dart';\n",
        "import 'package:onewifi_android/features/sms/state/sms_controller.dart';\n"
        "import 'package:onewifi_android/features/calls/data/calls_repository.dart';\n"
        "import 'package:onewifi_android/features/calls/domain/call.dart';\n"
        "import 'package:onewifi_android/features/calls/state/calls_controller.dart';\n",
    )

t = t.replace(
    "callsControllerFactory: () => throw UnimplementedError('calls'),\n",
    """callsControllerFactory: () => CallsController(
        repository: const _CallsRepository(),
        originProvider: () async => Uri.parse('http://127.0.0.1:6688'),
        tokenProvider: (_) async => null,
        requestRegistry: registry,
      ),
""",
)

if "class _CallsRepository" not in t:
    fake = '''
class _CallsRepository implements CallsRepository {
  const _CallsRepository();

  @override
  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async =>
      const <VoiceCall>[];

  @override
  Future<VoiceCall> dial(
    String deviceId,
    String number, {
    RequestCancellation? cancellation,
  }) async =>
      VoiceCall(
        id: '1',
        deviceId: deviceId,
        number: number,
        direction: CallDirection.outgoing,
        state: CallLifecycle.dialing,
      );

  @override
  Future<VoiceCall> answer(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async =>
      VoiceCall(
        id: callId,
        deviceId: deviceId,
        number: '',
        direction: CallDirection.incoming,
        state: CallLifecycle.active,
      );

  @override
  Future<void> hangup(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<CallMediaMeta> fetchMediaMeta(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) async =>
      CallMediaMeta(id: callId, codec: '', format: 'pcm_s16le_8000_mono', stream: '');

  @override
  Future<dynamic> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  }) async {
    throw UnsupportedError('no media in test');
  }
}

'''
    # Fix return type - should be Future<WebSocket> - use dart:io
    # Better import dart:io and WebSocket - for test throw is fine if signature matches
    # Change to proper signature with WebSocket from dart:io
    fake = fake.replace("Future<dynamic> openMediaSocket", "Future<WebSocket> openMediaSocket")
    if "import 'dart:io';" not in t:
        t = t.replace("import 'dart:async';\n", "import 'dart:async';\nimport 'dart:io';\n")
    t = t.replace("class _SmsRepository implements SmsRepository {", fake + "class _SmsRepository implements SmsRepository {")

sgt.write_text(t, encoding="utf-8", newline="\n")
print("session gate test updated")

# Ensure fake settings tests import SmsModemSettings - check one file
sample = root/"test/features/settings/state/settings_controller_test.dart"
s = sample.read_text(encoding="utf-8")
print("has gateway_settings import", "gateway_settings.dart" in s)
print("has SmsModemSettings", "SmsModemSettings" in s)
# check if RequestCancellation imported
print("RequestCancellation", "RequestCancellation" in s)
