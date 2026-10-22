import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/devices/data/device_api.dart';

import '../../../support/fakes.dart';

void main() {
  group('DeviceApi.fetchDiscoveredDevices', () {
    test('fetches discovered devices successfully', () async {
      final api = DeviceApi(
        _transport(
          FakeClient((request) async {
            expect(request.url.path, '/api/devices/discovered');
            return _success(<String, Object?>{
              'devices': <Object?>[
                <String, Object?>{
                  'hardware_kind': 'modem',
                  'reader_name': 'Test Modem',
                  'device_type': 'wifi_410',
                  'discovery_key': 'test-key-123',
                  'control_path': '/dev/ttyUSB0',
                  'net_interface': 'eth0',
                  'usb_path': '1-1.1',
                  'vendor_id': 0x1234,
                  'product_id': 0x5678,
                  'driver_name': 'qmi_wwan',
                  'at_ports': <String>['ttyUSB1', 'ttyUSB2'],
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
            });
          }),
        ),
      );

      final result = await api.fetchDiscoveredDevices();

      expect(result.devices, hasLength(1));
      expect(result.devices.first.readerName, 'Test Modem');
      expect(result.devices.first.configured, false);
    });
  });

  group('DeviceApi.rescanDevices', () {
    test('triggers rescan successfully', () async {
      final api = DeviceApi(
        _transport(
          FakeClient((request) async {
            expect(request.url.path, '/api/devices/actions/rescan');
            expect(request.method, 'POST');
            return _success(<String, Object?>{
              'status': 'ok',
              'devices': 2,
            });
          }),
        ),
      );

      final result = await api.rescanDevices();

      expect(result.status, 'ok');
      expect(result.devicesCount, 2);
    });
  });

  group('DeviceApi.registerDevice', () {
    test('registers device successfully', () async {
      http.BaseRequest? captured;
      final api = DeviceApi(
        _transport(
          FakeClient((request) async {
            captured = request;
            return _success(<String, Object?>{});
          }),
        ),
      );

      await api.registerDevice(
        deviceId: 'dev-123',
        discoveryKey: 'key-abc',
        deviceType: 'wifi_410',
        name: 'Test Device',
      );

      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/api/devices');
      final body = jsonDecode(
        utf8.decode(await captured!.finalize().toBytes()),
      ) as Map<String, Object?>;
      final config = body['config'] as Map<String, Object?>;
      expect(config['id'], 'dev-123');
      expect(config['discovery_key'], 'key-abc');
      expect(config['device_type'], 'wifi_410');
      expect(config['name'], 'Test Device');
    });
  });

  group('DeviceApi WEB main-path routes', () {
    test('list uses GET /api/devices', () async {
      http.BaseRequest? captured;
      final api = DeviceApi(
        _transport(
          FakeClient((request) async {
            captured = request;
            return _success(<String, Object?>{
              'device_limit': 8,
              'devices': <Object?>[],
            });
          }),
        ),
      );

      await api.fetchDevices();

      expect(captured!.method, 'GET');
      expect(captured!.url.path, '/api/devices');
    });

    test('detail uses GET /api/devices/{id}/overview not bare id', () async {
      http.BaseRequest? captured;
      final api = DeviceApi(
        _transport(
          FakeClient((request) async {
            captured = request;
            return http.StreamedResponse(
              Stream<List<int>>.value(
                utf8.encode(
                  jsonEncode(<String, Object?>{
                    'error': <String, Object?>{
                      'code': 'device_not_found',
                      'message': 'missing',
                    },
                  }),
                ),
              ),
              404,
            );
          }),
        ),
      );

      await expectLater(
        () => api.fetchDeviceOverview('dev-1'),
        throwsA(isA<Object>()),
      );
      expect(captured!.method, 'GET');
      expect(captured!.url.path, '/api/devices/dev-1/overview');
    });

    test('refreshSnapshot posts actions/refresh', () async {
      http.BaseRequest? captured;
      final api = DeviceApi(
        _transport(
          FakeClient((request) async {
            captured = request;
            return _success(<String, Object?>{});
          }),
        ),
      );

      await api.refreshSnapshot('dev-9');

      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/api/devices/dev-9/actions/refresh');
    });
  });
}

HttpTransport _transport(http.BaseClient client) => HttpTransport(
      client: client,
      originProvider: () async => Uri.parse('https://api.example.test'),
      tokenProvider: (_) async => 'test-token',
      requestIdGenerator: () => 'device-api-test',
    );

http.StreamedResponse _success(Object? data) => http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(jsonEncode(<String, Object?>{'data': data})),
      ),
      200,
    );
