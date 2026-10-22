import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/logs/data/logs_api.dart';
import 'package:onewifi_android/features/logs/domain/log_entry.dart';
import '../../../support/fakes.dart';

void main() {
  test('history query sends level and hides empty search', () async {
    http.BaseRequest? seen;
    final api = LogsApi(
      HttpTransport(
        client: FakeClient((request) async {
          seen = request;
          return http.StreamedResponse(
            Stream<List<int>>.value(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'data': <String, Object?>{
                    'logs': <Object?>[
                      <String, Object?>{
                        'time': '2026-09-02T04:00:00Z',
                        'level': 'warn',
                        'message': 'probe failed',
                      },
                    ],
                  },
                }),
              ),
            ),
            200,
          );
        }),
        originProvider: () async => Uri.parse('https://api.example.test'),
        tokenProvider: (_) async => 'token-token-token-token-token-token',
        requestIdGenerator: () => 'logs-test',
      ),
    );

    final logs = await api.fetchHistory(level: 'warn', search: '  ');
    expect(logs.single.message, 'probe failed');
    expect(
      seen!.url.toString(),
      'https://api.example.test/api/logs/history?lines=500&level=warn',
    );
  });

  test('watchStream hits logsStream, drops keepalive, yields log events', () async {
    http.BaseRequest? seen;
    final api = LogsApi(
      HttpTransport(
        client: FakeClient((request) async {
          seen = request;
          final body = <String>[
            'event: connected',
            'data: {}',
            '',
            ': keepalive',
            '',
            'event: log',
            'data: {"time":"2026-09-02T04:00:00Z","level":"warn","message":"live"}',
            '',
          ].join('\n');
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(body)),
            200,
            headers: <String, String>{'content-type': 'text/event-stream'},
          );
        }),
        originProvider: () async => Uri.parse('https://api.example.test'),
        tokenProvider: (_) async => 'token-token-token-token-token-token',
        requestIdGenerator: () => 'logs-sse-test',
      ),
    );

    final seenEntries = <LogEntry>[];
    await api.watchStream(
      level: 'warn',
      onEntry: (entry) {
        seenEntries.add(entry);
        return true;
      },
    );

    expect(seenEntries, hasLength(1));
    expect(seenEntries.single.message, 'live');
    expect(
      seen!.url.toString(),
      'https://api.example.test/api/logs/stream?level=warn',
    );
  });
}
