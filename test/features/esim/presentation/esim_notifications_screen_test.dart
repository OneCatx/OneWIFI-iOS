import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/esim/data/esim_api.dart';
import 'package:onewifi_android/features/esim/domain/esim_notification.dart';
import 'package:onewifi_android/features/esim/presentation/esim_notifications_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('EsimNotificationsScreen', () {
    late _NotificationHttpClient client;
    late EsimApi api;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      client = _NotificationHttpClient();
      api = EsimApi(
        HttpTransport(
          client: client,
          originProvider: () async => Uri.parse('https://gateway.test'),
          tokenProvider: (_) async => 'test-token',
        ),
      );
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EsimNotificationsScreen(deviceId: 'test-device', api: api),
        ),
      );
    }

    testWidgets('shows empty state when no notifications', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.text('还没有设置通知规则'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      client.holdGet = Completer<void>();
      await pumpScreen(tester);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      client.holdGet!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('shows add button', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.text('新增规则'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('opens add dialog when FAB tapped', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('新增通知规则'), findsOneWidget);
      expect(find.text('通知类型'), findsOneWidget);
    });

    testWidgets('add dialog shows type options', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('流量阈值告警'), findsOneWidget);
      expect(find.text('到期提醒'), findsOneWidget);
    });

    testWidgets('add dialog shows threshold selector for traffic type',
        (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('流量阈值'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('90%'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('add dialog switches to days selector for expiry type',
        (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('到期提醒'));
      await tester.pumpAndSettle();

      expect(find.text('提前天数'), findsOneWidget);
      expect(find.text('7天前'), findsOneWidget);
      expect(find.text('3天前'), findsOneWidget);
      expect(find.text('1天前'), findsOneWidget);
    });

    testWidgets('can cancel add dialog', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('新增通知规则'), findsNothing);
    });

    testWidgets('creates notification when add confirmed', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('90%'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(find.text('新增通知规则'), findsNothing);
      expect(find.text('流量达到 90%'), findsOneWidget);
      expect(find.text('流量阈值告警'), findsOneWidget);
    });

    testWidgets('shows notification list', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('到期提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNWidgets(2));
    });

    testWidgets('can delete notification', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('确认删除'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('还没有设置通知规则'), findsOneWidget);
    });

    testWidgets('can toggle notification enabled', (tester) async {
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, true);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final updatedSwitch = tester.widget<Switch>(find.byType(Switch));
      expect(updatedSwitch.value, false);
    });
  });

  group('EsimNotification domain', () {
    test('displayTitle formats correctly for traffic threshold', () {
      final notification = EsimNotification(
        id: '1',
        type: EsimNotificationType.trafficThreshold,
        threshold: TrafficThreshold.percent80,
      );

      expect(notification.displayTitle, '流量达到 80%');
    });

    test('displayTitle formats correctly for expiry reminder', () {
      final notification = EsimNotification(
        id: '1',
        type: EsimNotificationType.expiryReminder,
        daysBeforeExpiry: ExpiryDays.days3,
      );

      expect(notification.displayTitle, '到期前 3天前');
    });

    test('copyWith creates new instance with updated fields', () {
      final original = EsimNotification(
        id: '1',
        type: EsimNotificationType.trafficThreshold,
        threshold: TrafficThreshold.percent80,
        enabled: true,
      );

      final updated = original.copyWith(enabled: false);

      expect(updated.id, original.id);
      expect(updated.type, original.type);
      expect(updated.threshold, original.threshold);
      expect(updated.enabled, false);
    });
  });
}

final class _NotificationHttpClient extends http.BaseClient {
  final Map<String, Map<String, Object?>> _items = <String, Map<String, Object?>>{};
  int _seq = 0;
  Completer<void>? holdGet;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final method = request.method.toUpperCase();

    if (method == 'GET' && path.endsWith('/esim/user-notifications')) {
      final gate = holdGet;
      if (gate != null) await gate.future;
      return _json(200, _items.values.toList(growable: false));
    }

    if (method == 'POST' && path.endsWith('/esim/user-notifications')) {
      final body = jsonDecode((request as http.Request).body);
      if (body is! Map) {
        return _json(400, <String, Object?>{'error': 'bad_request'});
      }
      final id = 'n-${++_seq}';
      final item = <String, Object?>{
        'id': id,
        'device_id': 'test-device',
        'type': body['type'],
        'threshold': body['threshold'],
        'days_before_expiry': body['days_before_expiry'],
        'enabled': body['enabled'] ?? true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      _items[id] = item;
      return _json(200, item);
    }

    final updateMatch = RegExp(
      r'/esim/user-notifications/([^/]+)$',
    ).firstMatch(path);
    if (updateMatch != null) {
      final id = updateMatch.group(1)!;
      final existing = _items[id];
      if (existing == null) {
        return _json(404, <String, Object?>{'error': 'not_found'});
      }
      if (method == 'PUT') {
        final body = jsonDecode((request as http.Request).body);
        if (body is Map && body['enabled'] is bool) {
          existing['enabled'] = body['enabled'];
        }
        return _json(200, existing);
      }
      if (method == 'DELETE') {
        _items.remove(id);
        return _json(200, <String, Object?>{'ok': true});
      }
    }

    return _json(404, <String, Object?>{'error': 'not_found'});
  }

  http.StreamedResponse _json(int status, Object? data) {
    final payload = jsonEncode(<String, Object?>{'data': data});
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(payload)),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}
