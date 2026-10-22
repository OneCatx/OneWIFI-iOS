import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/app/android_oneims_shell.dart';
import 'package:onewifi_android/app/app.dart';
import 'package:onewifi_android/app/app_dependencies.dart';
import 'package:onewifi_android/app/session_gate.dart';
import 'package:onewifi_android/core/state/session_state.dart';
import '../support/fakes.dart';

void main() {
  testWidgets('changing appearance does not rebuild signed-in controllers', (
    tester,
  ) async {
    final origin = Uri.parse('https://api.example.test');
    final token = 'session-token-appearance';
    final dependencies = AppDependencies(
      httpClient: FakeClient((request) async {
        switch (request.url.path) {
          case '/api/auth/session':
            return _success(<String, Object?>{
              'user': <String, Object?>{'username': 'admin'},
              'session_token': token,
              'expires_at': '2030-01-02T03:04:05Z',
              'authenticated': true,
            });
          case '/api/dashboard/host':
            return _success(<String, Object?>{
              'host': <String, Object?>{
                'cpu_model': 'x',
                'board_model': 'x',
                'memory_model': '',
                'disk_model': '',
              },
              'perf': <String, Object?>{
                'cpu_percent': 1,
                'memory_percent': 1,
                'memory_used_bytes': 1,
                'memory_total_bytes': 2,
                'disk_percent': 1,
                'disk_used_bytes': 1,
                'disk_total_bytes': 2,
              },
            });
          case '/api/dashboard/devices':
            return _success(<String, Object?>{
              'device_limit': 4,
              'devices': <Object>[],
            });
          default:
            return _success(<String, Object?>{});
        }
      }),
      baseUrlStore: MemoryBaseUrlStore(origin),
      tokenStore: MemoryTokenStore(<Uri, String>{origin: token}),
    );
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(OneWifiApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    expect(dependencies.sessionController.state.status, SessionStatus.signedIn);

    final before = tester
        .widget<AndroidOneImsShell>(find.byType(AndroidOneImsShell))
        .overviewController;
    tester
        .widget<SessionGate>(find.byType(SessionGate))
        .appearance
        .setMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    final after = tester
        .widget<AndroidOneImsShell>(find.byType(AndroidOneImsShell))
        .overviewController;
    expect(identical(before, after), isTrue);
  });
}

http.StreamedResponse _success(Object? data) {
  return http.StreamedResponse(
    Stream<List<int>>.value(
      utf8.encode(jsonEncode(<String, Object?>{'data': data})),
    ),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
