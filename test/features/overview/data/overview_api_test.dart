import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/overview/data/overview_api.dart';
import '../../../support/fakes.dart';

void main() {
  test('uses exactly the two authenticated dashboard GET routes', () async {
    final token = _runtimeSecret(71, 3);
    final requests = <http.BaseRequest>[];
    final client = FakeClient((request) async {
      requests.add(request);
      return _success(
        request.url.path == '/api/dashboard/host'
            ? _hostFixture()
            : _devicesFixture(),
      );
    });
    final api = _api(client, token);

    final results = await Future.wait<Object>(<Future<Object>>[
      api.fetchHost(),
      api.fetchDevices(),
    ]);

    expect(results, hasLength(2));
    expect(requests, hasLength(2));
    expect(requests.map((request) => request.url.path).toSet(), <String>{
      '/api/dashboard/host',
      '/api/dashboard/devices',
    });
    for (final request in requests) {
      expect(request.method, 'GET');
      expect(request.headers['authorization'], 'Bearer $token');
      expect(request.headers.containsKey('cookie'), isFalse);
      expect(request.headers.containsKey('x-csrf-token'), isFalse);
      expect(await request.finalize().toBytes(), isEmpty);
    }
  });

  test(
    'converts malformed dashboard data into sanitized protocol failures',
    () async {
      final sensitive = _runtimeSecret(83, 9);
      final malformed = <Object?>[
        <String, Object?>{
          ..._hostFixture(),
          'host': <String, Object?>{
            'cpu_model': sensitive,
            'board_model': 'Board',
            'disk_model': 'Disk',
          },
        },
        <String, Object?>{
          ..._hostFixture(),
          'perf': <String, Object?>{
            ...(_hostFixture()['perf']! as Map<String, Object?>),
            'cpu_percent': '42',
          },
        },
      ];
      var index = 0;
      final client = FakeClient((_) async => _success(malformed[index++]));
      final api = _api(client, _runtimeSecret(89, 11));

      for (var caseIndex = 0; caseIndex < malformed.length; caseIndex += 1) {
        final failure = await _failureOf(api.fetchHost());
        expect(failure.kind, ApiFailureKind.protocol);
        expect(failure.message.contains(sensitive), isFalse);
        expect(failure.requestId.contains(sensitive), isFalse);
      }
    },
  );

  test('sanitizes every malformed host number encoding', () async {
    final sensitive = _runtimeSecret(83, 21);
    final valid = _hostWithSentinel(sensitive);
    final perf = valid['perf']! as Map<String, Object?>;
    final decodedMalformed = <Object?>[
      <String, Object?>{
        ...valid,
        'perf': <String, Object?>{...perf, 'cpu_percent': '42'},
      },
      <String, Object?>{
        ...valid,
        'perf': <String, Object?>{...perf, 'cpu_percent': true},
      },
      <String, Object?>{
        ...valid,
        'perf': <String, Object?>{...perf, 'cpu_percent': null},
      },
      <String, Object?>{
        ...valid,
        'perf': <String, Object?>{...perf, 'cpu_percent': -0.1},
      },
      <String, Object?>{
        ...valid,
        'perf': <String, Object?>{...perf, 'memory_percent': 100.1},
      },
      <String, Object?>{
        ...valid,
        'perf': <String, Object?>{...perf, 'net_rx_bps': -0.1},
      },
    ];
    final rawNonFinite = <String>['NaN', 'Infinity', '-Infinity'];
    final responses = <(http.StreamedResponse, String)>[
      for (final value in decodedMalformed)
        (_success(value), 'local-overview-response'),
      for (final value in rawNonFinite)
        (
          _rawSuccess(
            jsonEncode(<String, Object?>{
              'data': valid,
            }).replaceFirst('"cpu_percent":12.5', '"cpu_percent":$value'),
          ),
          'local-overview-api-test',
        ),
    ];
    var index = 0;
    final api = _api(
      FakeClient((_) async => responses[index++].$1),
      _runtimeSecret(89, 23),
    );

    for (var caseIndex = 0; caseIndex < responses.length; caseIndex += 1) {
      final failure = await _failureOf(api.fetchHost());
      expect(failure.kind, ApiFailureKind.protocol);
      expect(failure.message, 'Request failed.');
      expect(failure.requestId, responses[caseIndex].$2);
      expect(failure.statusCode, isNull);
      expect(failure.backendCode, isNull);
      expect(failure.retryAfter, isNull);
      expect(failure.message.contains(sensitive), isFalse);
      expect(failure.requestId.contains(sensitive), isFalse);
    }
  });
}

OverviewApi _api(http.BaseClient client, String token) {
  return OverviewApi(
    HttpTransport(
      client: client,
      originProvider: () async => Uri.parse('https://api.example.test'),
      tokenProvider: (_) async => token,
      requestIdGenerator: () => 'local-overview-api-test',
    ),
  );
}

Future<ApiFailure> _failureOf(Future<Object?> pending) async {
  try {
    await pending;
  } on ApiFailure catch (failure) {
    return failure;
  }
  throw StateError('Expected a sanitized API failure.');
}

http.StreamedResponse _success(Object? data) {
  return http.StreamedResponse(
    Stream<List<int>>.value(
      utf8.encode(jsonEncode(<String, Object?>{'data': data})),
    ),
    200,
  );
}

http.StreamedResponse _rawSuccess(String body) =>
    http.StreamedResponse(Stream<List<int>>.value(utf8.encode(body)), 200);

Map<String, Object?> _hostFixture() => <String, Object?>{
  'host': <String, Object?>{
    'cpu_model': 'Qualcomm X75',
    'board_model': 'One Board',
    'memory_model': '',
    'disk_model': '',
  },
  'perf': <String, Object?>{
    'cpu_percent': 12.5,
    'memory_percent': 31.25,
    'memory_used_bytes': 4294967296,
    'memory_total_bytes': 8589934592,
    'disk_percent': 42.75,
    'disk_used_bytes': 12884901888,
    'disk_total_bytes': 34359738368,
    'net_rx_bps': 1024.5,
    'net_tx_bps': 512.25,
  },
};

Map<String, Object?> _hostWithSentinel(String sentinel) => <String, Object?>{
  ..._hostFixture(),
  'host': <String, Object?>{
    ...(_hostFixture()['host']! as Map<String, Object?>),
    'cpu_model': sentinel,
  },
};

List<Object?> _devicesFixture() => <Object?>[
  <String, Object?>{
    'id': 'demo-modem',
    'name': 'Demo modem',
    'device_type': 'pcie_ec20_ec25',
    'interface': '',
    'proxy_port': 0,
    'public_ip': '',
    'healthy': true,
    'operator': 'One Carrier',
    'signal_dbm': -73,
    'network_mode': 'LTE',
    'network_duplex': 'FDD',
    'vowifi_active': true,
    'vowifi_runtime': _runtimeFixture(),
    'network_connected': true,
    'model': 'EC25',
  },
];

Map<String, Object?> _runtimeFixture() => <String, Object?>{
  'device_id': 'demo-modem',
  'phase': 'ims_ready',
  'enabled': true,
  'active': true,
  'dataplane_mode': 'cellular',
  'iccid': _runtimeSecret(20, 5),
  'imsi': _runtimeSecret(15, 7),
  'sim_ready': true,
  'access_ready': true,
  'tunnel_ready': true,
  'ims_ready': true,
  'sms_ready': false,
  'reg_status': 1,
  'reg_status_text': 'registered',
  'network_mode': 'LTE',
  'local_phone': _runtimeSecret(13, 11),
  'phone_number_source': 'network',
  'last_error_class': '',
  'last_error': '',
  'last_reason': 'ready',
  'updated_at': '2026-01-01T00:00:00Z',
};

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}
