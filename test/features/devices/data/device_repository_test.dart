import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/devices/data/device_api.dart';
import 'package:onewifi_android/features/devices/data/device_repository.dart';

import '../../../support/fakes.dart';

void main() {
  group('DeviceRepository.fetchDiscoveredDevices', () {
    test('maps DTOs to domain models correctly', () async {
      final repository = DefaultDeviceRepository(
        DeviceApi(
          _transport(
            FakeClient((_) async => _success(<String, Object?>{
                  'devices': <Object?>[
                    <String, Object?>{
                      'hardware_kind': 'modem',
                      'reader_name': 'Test Modem',
                      'device_type': 'wifi_410',
                      'discovery_key': 'key-123',
                      'control_path': '/dev/ttyUSB0',
                      'net_interface': 'eth0',
                      'usb_path': '1-1.1',
                      'vendor_id': 0x1234,
                      'product_id': 0x5678,
                      'driver_name': 'qmi_wwan',
                      'at_ports': <String>['ttyUSB1'],
                      'at_port': 'ttyUSB1',
                      'imei': '123456789012345',
                      'mode': 'LTE',
                      'network_capable': true,
                      'configured': false,
                      'configured_id': '',
                      'degraded': false,
                      'discovery_issue': '',
                    },
                  ],
                })),
          ),
        ),
      );

      final result = await repository.fetchDiscoveredDevices();

      expect(result, hasLength(1));
      expect(result.first.readerName, 'Test Modem');
      expect(result.first.isUnregistered, true);
      expect(result.first.networkCapable, true);
    });
  });

  group('DeviceRepository.rescanDevices', () {
    test('returns rescan result', () async {
      final repository = DefaultDeviceRepository(
        DeviceApi(
          _transport(
            FakeClient((_) async => _success(<String, Object?>{
                  'status': 'ok',
                  'devices': 3,
                })),
          ),
        ),
      );

      final result = await repository.rescanDevices();

      expect(result.status, 'ok');
      expect(result.devicesCount, 3);
    });
  });

  group('DeviceRepository.registerDevice', () {
    test('calls API with correct parameters', () async {
      http.BaseRequest? captured;
      final repository = DefaultDeviceRepository(
        DeviceApi(
          _transport(
            FakeClient((request) async {
              captured = request;
              return _success(<String, Object?>{});
            }),
          ),
        ),
      );

      await repository.registerDevice(
        deviceId: 'dev-123',
        discoveryKey: 'key-abc',
        deviceType: 'wifi_410',
        name: 'My Device',
        simPin: '1234',
      );

      expect(captured!.url.path, '/api/devices');
      final body = jsonDecode(
        utf8.decode(await captured!.finalize().toBytes()),
      ) as Map<String, Object?>;
      final config = body['config'] as Map<String, Object?>;
      expect(config['id'], 'dev-123');
      expect(config['discovery_key'], 'key-abc');
      expect(config['device_type'], 'wifi_410');
      expect(config['name'], 'My Device');
      expect(config['sim_pin'], '1234');
    });
  });
}

HttpTransport _transport(http.BaseClient client) => HttpTransport(
      client: client,
      originProvider: () async => Uri.parse('https://api.example.test'),
      tokenProvider: (_) async => 'test-token',
      requestIdGenerator: () => 'device-repo-test',
    );

http.StreamedResponse _success(Object? data) => http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(jsonEncode(<String, Object?>{'data': data})),
      ),
      200,
    );
