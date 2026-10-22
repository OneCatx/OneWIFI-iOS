import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/automation/data/automation_api.dart';
import 'package:onewifi_android/features/automation/data/automation_repository.dart';
import '../../../support/fakes.dart';

void main() {
  test('reads safe task and run models from the frozen routes', () async {
    final iccid = _digits(20, 3);
    final phone = _digits(12, 7);
    final requests = <_CapturedRequest>[];
    final api = AutomationApi(
      _transport(
        FakeClient((request) async {
          requests.add(await _capture(request));
          if (request.url.path.endsWith('/runs')) {
            return _success(<String, Object?>{
              'runs': <Object?>[
                _run(status: 'running', output: 'dialing $phone'),
              ],
              'total': 1,
            });
          }
          return _success(<String, Object?>{
            'tasks': <Object?>[_task(iccid: iccid, phone: phone)],
          });
        }),
      ),
    );

    final tasks = await api.fetchTasks();
    final page = await api.fetchRuns(limit: 20, offset: 0);

    expect(tasks.single.profileDisplay, endsWith(iccid.substring(16)));
    expect(tasks.single.toString(), isNot(contains(iccid)));
    expect(tasks.single.target.toString(), isNot(contains(iccid)));
    expect(page.runs.single.output, isNot(contains(phone)));
    expect(page.runs.single.output, contains(phone.substring(8)));
    expect(requests.map((item) => item.uri.toString()), <String>[
      'https://api.example.test/api/automatic-tasks',
      'https://api.example.test/api/automatic-tasks/runs?limit=20&offset=0',
    ]);
  });

  test('toggle PUT preserves the complete existing writable DTO', () async {
    final iccid = _digits(20, 2);
    final phone = _digits(12, 5);
    final requests = <_CapturedRequest>[];
    final api = AutomationApi(
      _transport(
        FakeClient((request) async {
          final captured = await _capture(request);
          requests.add(captured);
          if (request.method == 'GET') {
            return _success(<String, Object?>{
              'tasks': <Object?>[_task(iccid: iccid, phone: phone)],
            });
          }
          return _success(_task(iccid: iccid, phone: phone, enabled: false));
        }),
      ),
    );
    final task = (await api.fetchTasks()).single;

    final updated = await api.setEnabled(task.target, enabled: false);

    expect(updated.enabled, isFalse);
    expect(requests.last.method, 'PUT');
    expect(requests.last.uri.path, '/api/automatic-tasks/7');
    expect(requests.last.body, <String, Object?>{
      'name': 'Daily SMS',
      'enabled': false,
      'device_id': 'device-a',
      'profile_iccid': iccid,
      'profile_aid': 'AID0',
      'task_type': 'sms',
      'environment': 'vowifi',
      'interval_days': 1,
      'start_date': '2026-09-02',
      'run_time': '08:30',
      'timezone': 'Asia/Shanghai',
      'payload': <String, Object?>{
        'phone': phone,
        'message': 'keep alive',
        'duration_seconds': 30,
      },
      'retry_count': 1,
      'notify': true,
    });
  });

  test(
    'delete and run-now use their frozen routes and queued 202 body',
    () async {
      final requests = <_CapturedRequest>[];
      final api = AutomationApi(
        _transport(
          FakeClient((request) async {
            requests.add(await _capture(request));
            if (request.method == 'GET') {
              return _success(<String, Object?>{
                'tasks': <Object?>[
                  _task(iccid: _digits(20, 1), phone: _digits(12, 4)),
                ],
              });
            }
            if (request.method == 'DELETE') {
              return _success(<String, Object?>{'deleted': true});
            }
            return _success(_run(status: 'queued'), 202);
          }),
        ),
      );
      final task = (await api.fetchTasks()).single;

      await api.deleteTask(task.target);
      final run = await api.runNow(task.target);

      expect(run.status.name, 'queued');
      expect(
        requests.map((item) => '${item.method} ${item.uri.path}'),
        <String>[
          'GET /api/automatic-tasks',
          'DELETE /api/automatic-tasks/7',
          'POST /api/automatic-tasks/7/run',
        ],
      );
      expect(requests.last.body, <String, Object?>{});
    },
  );

  test(
    'tolerates backend zero times, null or string payloads, and empty ICCID',
    () async {
      final phone = _digits(12, 6);
      final requests = <_CapturedRequest>[];
      final api = AutomationApi(
        _transport(
          FakeClient((request) async {
            requests.add(await _capture(request));
            if (request.method == 'PUT') {
              return _success(_task(iccid: '', phone: phone));
            }
            return _success(<String, Object?>{
              'tasks': <Object?>[
                // 老数据：payload 是二次编码的 JSON 字串，还夹着后端不认的键。
                <String, Object?>{
                  ..._task(iccid: '', phone: phone),
                  'id': 1,
                  'payload': jsonEncode(<String, Object?>{
                    'phone': phone,
                    'message': 'legacy',
                    'legacy_key': 'drop me',
                  }),
                  'next_run_at': '0001-01-01T00:00:00Z',
                  'last_run_at': '0001-01-01T00:00:00Z',
                  'last_status': '',
                },
                // payload 为 null、时间字段缺省。
                <String, Object?>{
                  ..._task(iccid: _digits(20, 4), phone: phone),
                  'id': 2,
                  'payload': null,
                  'next_run_at': null,
                  'profile_aid': null,
                  'start_date': '',
                  'run_time': '',
                  'timezone': '',
                },
                // payload 是无法解析的垃圾字串。
                <String, Object?>{
                  ..._task(iccid: _digits(20, 5), phone: phone),
                  'id': 3,
                  'payload': 'not-json',
                },
              ],
            });
          }),
        ),
      );

      final tasks = await api.fetchTasks();

      expect(tasks.map((task) => task.id), <int>[1, 2, 3]);
      expect(tasks[0].profileDisplay, '—');
      expect(tasks[0].nextRunAt, isNull);
      expect(tasks[1].nextRunAt, isNull);
      expect(tasks[2].nextRunAt, isNotNull);

      await api.setEnabled(tasks[0].target, enabled: false);
      final body = requests.last.body!;
      expect(body['profile_iccid'], '');
      expect(body['profile_aid'], 'AID0');
      expect(body['payload'], <String, Object?>{
        'phone': phone,
        'message': 'legacy',
      });

      await api.setEnabled(tasks[1].target, enabled: true);
      expect(requests.last.body!['payload'], <String, Object?>{});
      expect(requests.last.body!['profile_aid'], '');
      expect(requests.last.body!['timezone'], '');

      await api.setEnabled(tasks[2].target, enabled: true);
      expect(requests.last.body!['payload'], <String, Object?>{});
    },
  );

  test(
    'repository translates malformed task data to protocol failure',
    () async {
      final repository = DefaultAutomationRepository(
        AutomationApi(
          _transport(
            FakeClient(
              (_) async => _success(<String, Object?>{
                'tasks': <Object?>[
                  <String, Object?>{'id': 7},
                ],
              }),
            ),
          ),
        ),
      );

      await expectLater(
        repository.fetchTasks(),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );
}

Map<String, Object?> _task({
  required String iccid,
  required String phone,
  bool enabled = true,
}) => <String, Object?>{
  'id': 7,
  'name': 'Daily SMS',
  'enabled': enabled,
  'device_id': 'device-a',
  'profile_iccid': iccid,
  'profile_aid': 'AID0',
  'task_type': 'sms',
  'environment': 'vowifi',
  'interval_days': 1,
  'start_date': '2026-09-02',
  'run_time': '08:30',
  'timezone': 'Asia/Shanghai',
  'payload': <String, Object?>{
    'phone': phone,
    'message': 'keep alive',
    'duration_seconds': 30,
  },
  'retry_count': 1,
  'notify': true,
  'next_run_at': '2026-09-03T00:30:00Z',
  'last_run_at': '2026-09-02T00:30:00Z',
  'last_status': 'success',
  'last_error': '',
  'created_at': '2026-09-01T00:00:00Z',
  'updated_at': '2026-09-02T00:00:00Z',
};

Map<String, Object?> _run({String status = 'queued', String output = ''}) =>
    <String, Object?>{
      'id': 91,
      'task_id': 7,
      'device_id': 'device-a',
      'scheduled_at': '2026-09-02T01:00:00Z',
      'started_at': status == 'queued'
          ? '0001-01-01T00:00:00Z'
          : '2026-09-02T01:00:02Z',
      'finished_at': status == 'success' || status == 'failed'
          ? '2026-09-02T01:01:00Z'
          : '0001-01-01T00:00:00Z',
      'status': status,
      'attempts': status == 'queued' ? 0 : 1,
      'output': output,
      'error': status == 'failed' ? 'failed safely' : '',
      'created_at': '2026-09-02T01:00:00Z',
      'updated_at': '2026-09-02T01:00:02Z',
    };

HttpTransport _transport(http.BaseClient client) => HttpTransport(
  client: client,
  originProvider: () async => Uri.parse('https://api.example.test'),
  tokenProvider: (_) async => _digits(48, 9),
  requestIdGenerator: () => 'safe-automation-test',
);

http.StreamedResponse _success(Object? data, [int status = 200]) =>
    http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(jsonEncode(<String, Object?>{'data': data})),
      ),
      status,
    );

Future<_CapturedRequest> _capture(http.BaseRequest request) async {
  final bytes = await request.finalize().toBytes();
  return _CapturedRequest(
    request.method,
    request.url,
    bytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(bytes)) as Map<String, Object?>,
  );
}

final class _CapturedRequest {
  const _CapturedRequest(this.method, this.uri, this.body);
  final String method;
  final Uri uri;
  final Map<String, Object?>? body;
}

String _digits(int length, int offset) => List<String>.generate(
  length,
  (index) => ((index + offset) % 10).toString(),
).join();
