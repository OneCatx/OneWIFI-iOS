import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/features/calls/data/calls_repository.dart';
import 'package:onewifi_android/features/calls/domain/call.dart';
import 'package:onewifi_android/features/calls/state/calls_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'iOS never polls the legacy call repository when selecting a device',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final repository = _Legacy();
      final controller = CallsController(
        repository: repository,
        originProvider: () async => Uri.parse('https://example.test'),
        tokenProvider: (_) async => 'token',
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);
      controller.selectDevice('A');
      await controller.refresh();
      expect(repository.reads, 0);
    },
  );
}

class _Legacy implements CallsRepository {
  int reads = 0;
  @override
  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    reads++;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Legacy call operation must not run');
}
