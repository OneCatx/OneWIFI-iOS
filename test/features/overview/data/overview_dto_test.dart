import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/overview/data/overview_dto.dart';

void main() {
  test('parses the complete host fixture and retains only overview fields', () {
    final dto = HostOverviewDto.fromData(_hostFixture());

    expect(dto.cpuModel, 'Qualcomm X75');
    expect(dto.boardModel, 'One Board');
    expect(dto.cpuPercent, 12.5);
    expect(dto.memoryUsedBytes, 4294967296);
    expect(dto.netRxBps, 1024.5);
    expect(dto.cpuModel, isNot('Memory Vendor Secret'));
    expect(dto.boardModel, isNot('Disk Vendor Secret'));

    final domain = dto.toDomain();
    expect(domain.cpuModel, dto.cpuModel);
    expect(domain.boardModel, dto.boardModel);
    expect(domain.cpuPercent, dto.cpuPercent);
    expect(domain.memoryPercent, dto.memoryPercent);
    expect(domain.memoryUsedBytes, dto.memoryUsedBytes);
    expect(domain.memoryTotalBytes, dto.memoryTotalBytes);
    expect(domain.diskPercent, dto.diskPercent);
    expect(domain.diskUsedBytes, dto.diskUsedBytes);
    expect(domain.diskTotalBytes, dto.diskTotalBytes);
    expect(domain.netRxBps, dto.netRxBps);
    expect(domain.netTxBps, dto.netTxBps);
  });

  test(
    'parses complete devices while never retaining identity or raw runtime',
    () {
      final iccid = _runtimeSecret(20, 3);
      final imsi = _runtimeSecret(15, 5);
      final localPhone = _runtimeSecret(13, 7);
      final nestedSecret = _runtimeSecret(47, 9);

      final devices = DeviceOverviewDto.listFromData(
        _devicesFixture(
          iccid: iccid,
          imsi: imsi,
          localPhone: localPhone,
          nestedSecret: nestedSecret,
        ),
      );

      expect(devices, hasLength(1));
      final device = devices.single;
      expect(device.id, 'demo-modem');
      expect(device.signalDbm, -73);
      expect(device.runtime.phase.name, 'imsReady');
      expect(device.runtime.imsReady, isTrue);
      expect(device.runtime.smsReady, isFalse);
      final domain = device.toDomain();
      final approvedProjection = <Object?>[
        device.id,
        device.name,
        device.model,
        device.type,
        device.healthy,
        device.operatorName,
        device.signalDbm,
        device.networkMode,
        device.vowifiActive,
        device.networkConnected,
        device.runtime.phase,
        device.runtime.simReady,
        device.runtime.accessReady,
        device.runtime.tunnelReady,
        device.runtime.imsReady,
        device.runtime.smsReady,
        domain.id,
        domain.name,
        domain.model,
        domain.type,
        domain.healthy,
        domain.operatorName,
        domain.signalDbm,
        domain.networkMode,
        domain.vowifiActive,
        domain.networkConnected,
        domain.runtime.phase,
        domain.runtime.simReady,
        domain.runtime.accessReady,
        domain.runtime.tunnelReady,
        domain.runtime.imsReady,
        domain.runtime.smsReady,
      ];
      for (final secret in <String>[iccid, imsi, localPhone, nestedSecret]) {
        expect(approvedProjection.contains(secret), isFalse);
      }

      for (final path in _overviewPublicShapePaths) {
        expect(
          _declaresSensitiveProjection(File(path).readAsStringSync()),
          isFalse,
        );
      }
      for (final field in _forbiddenProjectionFields) {
        expect(_declaresSensitiveProjection('final String $field;'), isTrue);
      }
    },
  );

  test('rejects missing, mistyped and unknown required device fields', () {
    final valid =
        _devicesFixture(
              iccid: _runtimeSecret(20, 13),
              imsi: _runtimeSecret(15, 15),
              localPhone: _runtimeSecret(13, 17),
              nestedSecret: _runtimeSecret(41, 19),
            ).single
            as Map<String, Object?>;
    final runtime = valid['vowifi_runtime']! as Map<String, Object?>;
    final invalid = <Object?>[
      <String, Object?>{...valid}..remove('interface'),
      <String, Object?>{...valid, 'signal_dbm': -73.0},
      <String, Object?>{
        ...valid,
        'vowifi_runtime': <String, Object?>{...runtime}..remove('iccid'),
      },
      <String, Object?>{
        ...valid,
        'vowifi_runtime': <String, Object?>{
          ...runtime,
          'phase': 'invented_phase',
        },
      },
      <String, Object?>{
        ...valid,
        'vowifi_runtime': <String, Object?>{...runtime, 'sim_ready': 'true'},
      },
    ];

    for (final value in invalid) {
      expect(
        () => DeviceOverviewDto.listFromData(<Object?>[value]),
        throwsA(isA<OverviewDtoException>()),
      );
    }
  });

  test('accepts the exact empty devices fixture', () {
    expect(DeviceOverviewDto.listFromData(const <Object?>[]), isEmpty);
  });

  test('rejects host percentages and counters outside their contract', () {
    final valid = _hostFixture();
    final perf = valid['perf']! as Map<String, Object?>;
    final invalid = <Map<String, Object?>>[
      <String, Object?>{
        ...valid,
        'perf': <String, Object?>{...perf, 'cpu_percent': 100.1},
      },
      <String, Object?>{
        ...valid,
        'perf': <String, Object?>{...perf, 'memory_used_bytes': -1},
      },
      <String, Object?>{
        ...valid,
        'perf': <String, Object?>{...perf, 'net_rx_bps': -0.1},
      },
    ];

    for (final value in invalid) {
      expect(
        () => HostOverviewDto.fromData(value),
        throwsA(isA<OverviewDtoException>()),
      );
    }
  });

  test(
    'rejects every non-finite, non-numeric, and out-of-range host number',
    () {
      final valid = _hostFixture();
      final perf = valid['perf']! as Map<String, Object?>;
      final invalid = <(String, Object?)>[
        ('cpu_percent', '42'),
        ('cpu_percent', true),
        ('cpu_percent', null),
        ('cpu_percent', double.nan),
        ('cpu_percent', double.infinity),
        ('cpu_percent', double.negativeInfinity),
        ('cpu_percent', -0.1),
        ('memory_percent', 100.1),
        ('memory_used_bytes', -1),
        ('net_rx_bps', -0.1),
        ('net_tx_bps', -0.1),
      ];

      for (final entry in invalid) {
        expect(
          () => HostOverviewDto.fromData(<String, Object?>{
            ...valid,
            'perf': <String, Object?>{...perf, entry.$1: entry.$2},
          }),
          throwsA(isA<OverviewDtoException>()),
        );
      }
    },
  );

  test('accepts integer and fractional JSON number tokens for host rates', () {
    final decoded = jsonDecode('''
      {
        "host": {
          "cpu_model": "Qualcomm X75",
          "board_model": "One Board",
          "memory_model": "",
          "disk_model": ""
        },
        "perf": {
          "cpu_percent": 12,
          "memory_percent": 31.25,
          "memory_used_bytes": 4294967296,
          "memory_total_bytes": 8589934592,
          "disk_percent": 42,
          "disk_used_bytes": 12884901888,
          "disk_total_bytes": 34359738368,
          "net_rx_bps": 1024,
          "net_tx_bps": 512.25
        }
      }
    ''');

    final dto = HostOverviewDto.fromData(decoded);

    expect(dto.cpuPercent, 12.0);
    expect(dto.memoryPercent, 31.25);
    expect(dto.diskPercent, 42.0);
    expect(dto.netRxBps, 1024.0);
    expect(dto.netTxBps, 512.25);
  });
}

const _overviewPublicShapePaths = <String>[
  'lib/features/overview/data/overview_dto.dart',
  'lib/features/overview/domain/overview.dart',
  'lib/features/overview/data/overview_api.dart',
  'lib/features/overview/data/overview_repository.dart',
  'lib/features/overview/state/overview_controller.dart',
];

const _forbiddenProjectionFields = <String>{
  'imei',
  'iccid',
  'imsi',
  'msisdn',
  'localPhone',
  'phoneNumber',
  'local_phone',
  'tunnel',
  'imscore',
  'smsip',
};

final _forbiddenProjectionPattern = RegExp(
  '^\\s*final\\s+[A-Za-z_][A-Za-z0-9_<>,? ]*\\s+(${_forbiddenProjectionFields.join('|')})\\s*;',
  multiLine: true,
);

bool _declaresSensitiveProjection(String source) {
  return _forbiddenProjectionPattern.hasMatch(source);
}

Map<String, Object?> _hostFixture() => <String, Object?>{
  'host': <String, Object?>{
    'cpu_model': 'Qualcomm X75',
    'board_model': 'One Board',
    'memory_model': 'Memory Vendor Secret',
    'disk_model': 'Disk Vendor Secret',
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

List<Object?> _devicesFixture({
  required String iccid,
  required String imsi,
  required String localPhone,
  required String nestedSecret,
}) => <Object?>[
  <String, Object?>{
    'id': 'demo-modem',
    'name': 'Demo modem',
    'device_type': 'pcie_ec20_ec25',
    'interface': 'wwan0',
    'proxy_port': 1080,
    'public_ip': '198.51.100.12',
    'healthy': true,
    'operator': 'One Carrier',
    'signal_dbm': -73,
    'network_mode': 'LTE',
    'network_duplex': 'FDD',
    'vowifi_active': true,
    'vowifi_runtime': <String, Object?>{
      'device_id': 'demo-modem',
      'phase': 'ims_ready',
      'enabled': true,
      'active': true,
      'dataplane_mode': 'cellular',
      'iccid': iccid,
      'imsi': imsi,
      'sim_ready': true,
      'access_ready': true,
      'tunnel_ready': true,
      'ims_ready': true,
      'sms_ready': false,
      'reg_status': 1,
      'reg_status_text': 'registered',
      'network_mode': 'LTE',
      'local_phone': localPhone,
      'phone_number_source': 'network',
      'last_error_class': '',
      'last_error': '',
      'last_reason': 'ready',
      'updated_at': '2026-01-01T00:00:00Z',
      'tunnel': <String, Object?>{'credential': nestedSecret},
      'imscore': <String, Object?>{'opaque': nestedSecret},
      'smsip': <String, Object?>{'opaque': nestedSecret},
    },
    'network_connected': true,
    'model': 'EC25',
  },
];

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}
