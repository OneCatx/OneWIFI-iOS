import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/esim/data/esim_api.dart';
import 'package:onewifi_android/features/esim/data/esim_notification_dto.dart';
import 'package:onewifi_android/features/esim/data/esim_notification_repository.dart';
import 'package:onewifi_android/features/esim/domain/esim_notification.dart';

import '../../../support/fakes.dart';

void main() {
  group('EsimNotificationRepository', () {
    test('getAll returns empty list initially', () async {
      final repository = EsimNotificationRepository(
        deviceId: 'test-device',
        api: EsimApi(
          _transport(
            FakeClient((_) async => _success(<Object?>[])),
          ),
        ),
      );

      final result = await repository.getAll();
      expect(result, isEmpty);
    });

    test('create calls backend api', () async {
      http.BaseRequest? captured;
      final repository = EsimNotificationRepository(
        deviceId: 'test-device',
        api: EsimApi(
          _transport(
            FakeClient((request) async {
              captured = request;
              return _success(<String, Object?>{
                'id': '1',
                'device_id': 'test-device',
                'type': 'traffic_threshold',
                'threshold': 0.8,
                'enabled': true,
                'created_at': '2026-10-19T00:00:00.000Z',
              });
            }),
          ),
        ),
      );

      await repository.create(
        const EsimNotification(
          id: '1',
          type: EsimNotificationType.trafficThreshold,
          threshold: TrafficThreshold.percent80,
          enabled: true,
        ),
      );

      expect(captured!.method, 'POST');
      expect(
        captured!.url.path,
        '/api/devices/test-device/esim/user-notifications',
      );
      final body = jsonDecode(
        utf8.decode(await captured!.finalize().toBytes()),
      ) as Map<String, Object?>;
      expect(body['type'], 'traffic_threshold');
      expect(body['threshold'], 0.8);
      expect(body['enabled'], true);
    });

    test('update toggles enabled via backend api', () async {
      http.BaseRequest? captured;
      final repository = EsimNotificationRepository(
        deviceId: 'test-device',
        api: EsimApi(
          _transport(
            FakeClient((request) async {
              captured = request;
              return _success(<String, Object?>{
                'id': '1',
                'device_id': 'test-device',
                'type': 'traffic_threshold',
                'threshold': 0.8,
                'enabled': false,
              });
            }),
          ),
        ),
      );

      await repository.update(
        const EsimNotification(
          id: '1',
          type: EsimNotificationType.trafficThreshold,
          threshold: TrafficThreshold.percent80,
          enabled: false,
        ),
      );

      expect(captured!.method, 'PUT');
      expect(
        captured!.url.path,
        '/api/devices/test-device/esim/user-notifications/1',
      );
    });

    test('delete calls backend api', () async {
      http.BaseRequest? captured;
      final repository = EsimNotificationRepository(
        deviceId: 'test-device',
        api: EsimApi(
          _transport(
            FakeClient((request) async {
              captured = request;
              return _success(<String, Object?>{});
            }),
          ),
        ),
      );

      await repository.delete('1');

      expect(captured!.method, 'DELETE');
      expect(
        captured!.url.path,
        '/api/devices/test-device/esim/user-notifications/1',
      );
    });

    test('deleteAll deletes every fetched notification', () async {
      final deleted = <String>[];
      final repository = EsimNotificationRepository(
        deviceId: 'test-device',
        api: EsimApi(
          _transport(
            FakeClient((request) async {
              if (request.method == 'GET') {
                return _success(<Object?>[
                  <String, Object?>{
                    'id': '1',
                    'device_id': 'test-device',
                    'type': 'traffic_threshold',
                    'threshold': 0.8,
                    'enabled': true,
                  },
                  <String, Object?>{
                    'id': '2',
                    'device_id': 'test-device',
                    'type': 'expiry_reminder',
                    'days_before_expiry': 7,
                    'enabled': true,
                  },
                ]);
              }
              deleted.add(request.url.pathSegments.last);
              return _success(<String, Object?>{});
            }),
          ),
        ),
      );

      await repository.deleteAll();
      expect(deleted, <String>['1', '2']);
    });
  });

  group('EsimNotificationDto', () {
    test('fromDomain and toDomain roundtrip for traffic threshold', () {
      const domain = EsimNotification(
        id: '1',
        type: EsimNotificationType.trafficThreshold,
        threshold: TrafficThreshold.percent90,
        enabled: true,
      );

      final mapped = EsimNotificationDto.fromDomain(domain, 'test-device');
      final result = mapped.toDomain();

      expect(result.id, domain.id);
      expect(result.type, domain.type);
      expect(result.threshold, domain.threshold);
      expect(result.enabled, domain.enabled);
    });

    test('fromDomain and toDomain roundtrip for expiry reminder', () {
      const domain = EsimNotification(
        id: '2',
        type: EsimNotificationType.expiryReminder,
        daysBeforeExpiry: ExpiryDays.days1,
        enabled: false,
      );

      final mapped = EsimNotificationDto.fromDomain(domain, 'test-device');
      final result = mapped.toDomain();

      expect(result.id, domain.id);
      expect(result.type, domain.type);
      expect(result.daysBeforeExpiry, domain.daysBeforeExpiry);
      expect(result.enabled, domain.enabled);
    });

    test('local json roundtrip', () {
      final mapped = EsimNotificationDto(
        id: '3',
        deviceId: 'test-device',
        type: 'traffic_threshold',
        threshold: 0.8,
        daysBeforeExpiry: null,
        enabled: true,
      );

      final json = mapped.toLocalJson();
      final result = EsimNotificationDto.fromLocalJson(json);

      expect(result.id, mapped.id);
      expect(result.deviceId, mapped.deviceId);
      expect(result.type, mapped.type);
      expect(result.threshold, mapped.threshold);
      expect(result.enabled, mapped.enabled);
    });

    test('backend json parse', () {
      final result = EsimNotificationDto.fromBackendJson({
        'id': '4',
        'device_id': 'modem-1',
        'type': 'expiry_reminder',
        'days_before_expiry': 3,
        'enabled': true,
        'created_at': '2026-10-19T00:00:00.000Z',
      });

      expect(result.id, '4');
      expect(result.deviceId, 'modem-1');
      expect(result.daysBeforeExpiry, 3);
      expect(result.createdAt, isNotNull);
    });
  });
}

HttpTransport _transport(http.BaseClient client) => HttpTransport(
      client: client,
      originProvider: () async => Uri.parse('https://api.example.test'),
      tokenProvider: (_) async => 'test-token',
      requestIdGenerator: () => 'esim-notification-test',
    );

http.StreamedResponse _success(Object? data) => http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(jsonEncode(<String, Object?>{'data': data})),
      ),
      200,
    );
