import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/app/app.dart';
import 'package:onewifi_android/app/app_dependencies.dart';
import 'package:onewifi_android/core/state/session_state.dart';
import 'package:onewifi_android/design/widgets/glass_dialog.dart';
import 'package:onewifi_android/design/widgets/glass_dock.dart';
import '../support/fakes.dart';

void main() {
  testWidgets(
    'production root reaches encoded device detail and both back paths cancel it',
    (tester) async {
      final origin = Uri.parse('https://api.example.test');
      final token = _runtimeSecret(61, 3);
      final tokenStore = MemoryTokenStore(<Uri, String>{origin: token});
      final esimIccid = _runtimeDigits(20, 5);
      final requests = <http.BaseRequest>[];
      final firstDetail = Completer<http.StreamedResponse>();
      final thirdDetail = Completer<http.StreamedResponse>();
      var detailRequests = 0;
      var firstDetailCancelled = false;
      var thirdDetailCancelled = false;
      var esimSwitched = false;
      final dependencies = AppDependencies(
        httpClient: FakeClient((request) async {
          requests.add(request);
          switch (request.url.path) {
            case '/api/auth/session':
              return _success(_sessionData(token));
            case '/api/dashboard/host':
            case '/api/dashboard/devices':
              return _failure(403);
            case '/api/devices':
              return _success(<String, Object?>{
                'device_limit': 4,
                'devices': <Object?>[
                  _deviceFixture(id: 'rack/a b?c#d', detail: false),
                ],
              });
            case '/api/devices/rack%2Fa%20b%3Fc%23d/overview':
              detailRequests += 1;
              if (detailRequests == 1) {
                final abortable = request as http.AbortableRequest;
                unawaited(
                  abortable.abortTrigger!.then(
                    (_) => firstDetailCancelled = true,
                  ),
                );
                return firstDetail.future;
              }
              if (detailRequests == 3) {
                final abortable = request as http.AbortableRequest;
                unawaited(
                  abortable.abortTrigger!.then(
                    (_) => thirdDetailCancelled = true,
                  ),
                );
                return thirdDetail.future;
              }
              return _success(<String, Object?>{
                'devices': <Object?>[
                  _deviceFixture(id: 'rack/a b?c#d', detail: true),
                ],
              });
            case '/api/devices/rack%2Fa%20b%3Fc%23d/esim/profiles':
              return _success(<Object?>[
                <String, Object?>{
                  'eid': '',
                  'aidHex': 'AID0',
                  'profiles': <Object?>[
                    <String, Object?>{
                      'iccid': esimIccid,
                      'name': 'Travel eSIM',
                      'serviceProviderName': 'One Carrier',
                      'state': esimSwitched ? 1 : 0,
                      'stateText': esimSwitched ? 'enabled' : 'disabled',
                      'classText': 'operational',
                    },
                  ],
                },
              ]);
            case '/api/devices/rack%2Fa%20b%3Fc%23d/esim':
              return _success(<String, Object?>{
                'chipInfo': <String, Object?>{
                  'eids': <Object?>[
                    <String, Object?>{
                      'eid': '89049032004008882600012345678901',
                      'aid': 'A0000005591010FFFFFFFF8900000100',
                      'freeNvram': '634.55 KB',
                      'freeNvramBytes': 649779,
                    },
                  ],
                },
                'profiles': <Object?>[],
              });
            case '/api/devices/rack%2Fa%20b%3Fc%23d/esim/actions/switch':
              esimSwitched = true;
              return _success(<String, Object?>{
                'status': 'switched',
                'iccid': esimIccid,
                'verified': true,
              });
            default:
              throw StateError('Unexpected route: ${request.url}');
          }
        }),
        baseUrlStore: MemoryBaseUrlStore(origin),
        tokenStore: tokenStore,
      );
      addTearDown(dependencies.dispose);

      await tester.pumpWidget(OneWifiApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GlassDock.targetKey(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lab modem'));
      await tester.pump();

      expect(
        requests.where(
          (request) =>
              request.url.path == '/api/devices/rack%2Fa%20b%3Fc%23d/overview',
        ),
        hasLength(1),
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(firstDetailCancelled, isTrue);
      expect(find.text('Lab modem'), findsOneWidget);

      await tester.tap(find.text('Lab modem'));
      await tester.pumpAndSettle();
      // 详情页的卡策略框带 TextField（自带 Scrollable），进了缓存区后
      // `Scrollable.last` 会指到它；这里钉死到详情页那条 ListView。
      final detailList = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('模组'),
        300,
        scrollable: detailList,
      );
      expect(find.text('模组'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('切卡'),
        300,
        scrollable: detailList,
      );
      expect(find.text('切卡'), findsOneWidget);
      // 切卡面板是懒构建的（滚入视口才 initState→load），先让 profiles 请求落地。
      await tester.pumpAndSettle();
      expect(find.text('Travel eSIM'), findsOneWidget);
      expect(find.text(esimIccid), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Travel eSIM'),
        150,
        scrollable: detailList,
      );
      await tester.ensureVisible(find.text('Travel eSIM'));
      await tester.pumpAndSettle();
      // 点整块 eSIM 瓷片即切卡（WEB 同款）。
      await tester.tap(find.text('Travel eSIM'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OneGlassDialog.confirmTargetKey));
      await tester.pumpAndSettle();
      expect(find.text('已切换 eSIM'), findsOneWidget);
      expect(find.text('当前'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      expect(find.text('模组'), findsNothing);
      expect(find.text('Lab modem'), findsOneWidget);

      await tester.tap(find.text('Lab modem'));
      await tester.pump();
      await tester.tap(find.byKey(GlassDock.targetKey(0)));
      await tester.pump();
      expect(thirdDetailCancelled, isTrue);
      expect(tester.widget<GlassDock>(find.byType(GlassDock)).selectedIndex, 0);
      expect(find.text('正在加载设备'), findsNothing);

      final deviceRequests = requests.where(
        (request) => request.url.path.startsWith('/api/devices'),
      );
      // 三次进详情各拉一次 overview，切卡结束后详情页再静默补拉一次，
      // 好让「切卡进度」小框收口到后端最终的 esim_switch 状态。
      expect(
        deviceRequests.where(
          (request) => request.url.path.endsWith('/overview'),
        ),
        hasLength(4),
      );
      for (final request in deviceRequests) {
        if (request.url.path.endsWith('/esim/actions/switch')) {
          expect(request.method, 'POST');
        } else {
          expect(request.method, 'GET');
        }
        expect(request.headers['authorization'], 'Bearer $token');
        expect(request.headers.containsKey('cookie'), isFalse);
        expect(request.headers.containsKey('x-csrf-token'), isFalse);
      }
      final switchRequest = requests.singleWhere(
        (request) => request.url.path.endsWith('/esim/actions/switch'),
      );
      final switchBody =
          jsonDecode(utf8.decode(await switchRequest.finalize().toBytes()))
              as Map<String, Object?>;
      expect(switchBody['iccid'] == esimIccid, isTrue);
      expect(switchBody['aid_hex'], 'AID0');
      if (!firstDetail.isCompleted) {
        firstDetail.complete(
          _success(<String, Object?>{
            'devices': <Object?>[
              _deviceFixture(id: 'rack/a b?c#d', detail: true),
            ],
          }),
        );
      }
      if (!thirdDetail.isCompleted) {
        thirdDetail.complete(
          _success(<String, Object?>{
            'devices': <Object?>[
              _deviceFixture(id: 'rack/a b?c#d', detail: true),
            ],
          }),
        );
      }
    },
  );

  testWidgets('current device 401 expires and clears only the active origin', (
    tester,
  ) async {
    final origin = Uri.parse('https://api.example.test');
    final otherOrigin = Uri.parse('https://other.example.test');
    final token = _runtimeSecret(59, 5);
    final otherToken = _runtimeSecret(57, 7);
    final tokenStore = MemoryTokenStore(<Uri, String>{
      origin: token,
      otherOrigin: otherToken,
    });
    final dependencies = AppDependencies(
      httpClient: FakeClient((request) async {
        return switch (request.url.path) {
          '/api/auth/session' => _success(_sessionData(token)),
          '/api/dashboard/host' || '/api/dashboard/devices' => _failure(403),
          '/api/devices' => _failure(401),
          _ => throw StateError('Unexpected route: ${request.url}'),
        };
      }),
      baseUrlStore: MemoryBaseUrlStore(origin),
      tokenStore: tokenStore,
    );
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(OneWifiApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(dependencies.sessionController.state.status, SessionStatus.signedIn);
    await tester.tap(find.byKey(GlassDock.targetKey(1)));
    await tester.pumpAndSettle();

    // Voice-call watching is gone, so login no longer hits `/api/devices`.
    // Opening the devices tab does, and a 401 expires the session there.
    expect(dependencies.sessionController.state.status, SessionStatus.expired);
    expect(tokenStore.tokens.containsKey(origin), isFalse);
    expect(tokenStore.tokens[otherOrigin], otherToken);
    expect(tokenStore.clearOrigins, <Uri>[origin]);
    expect(find.text('登录已过期，请重新登录'), findsOneWidget);
    expect(find.byType(GlassDock), findsNothing);
  });

  testWidgets('device 403 remains signed in and exposes only a safe failure', (
    tester,
  ) async {
    final origin = Uri.parse('https://api.example.test');
    final token = _runtimeSecret(53, 11);
    final backendSecret = _runtimeSecret(73, 13);
    final tokenStore = MemoryTokenStore(<Uri, String>{origin: token});
    final dependencies = AppDependencies(
      httpClient: FakeClient((request) async {
        return switch (request.url.path) {
          '/api/auth/session' => _success(_sessionData(token)),
          '/api/dashboard/host' || '/api/dashboard/devices' => _failure(403),
          '/api/devices' => _success(<String, Object?>{
            'device_limit': 4,
            'devices': <Object?>[
              _deviceFixture(id: 'forbidden-device', detail: false),
            ],
          }),
          '/api/devices/forbidden-device/overview' => _failure(
            403,
            message: backendSecret,
          ),
          '/api/devices/forbidden-device/esim/profiles' => _success(
            <Object?>[],
          ),
          _ => throw StateError('Unexpected route: ${request.url}'),
        };
      }),
      baseUrlStore: MemoryBaseUrlStore(origin),
      tokenStore: tokenStore,
    );
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(OneWifiApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GlassDock.targetKey(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lab modem'));
    await tester.pumpAndSettle();

    expect(dependencies.sessionController.state.status, SessionStatus.signedIn);
    expect(tokenStore.tokens[origin], token);
    expect(find.text('无权访问该设备'), findsOneWidget);
    expect(find.text(backendSecret), findsNothing);
    expect(find.byType(GlassDock), findsOneWidget);
  });
}

http.StreamedResponse _success(Object? data) =>
    _response(200, <String, Object?>{'data': data});

http.StreamedResponse _failure(int status, {String message = 'denied'}) =>
    _response(status, <String, Object?>{
      'error': <String, String>{'code': 'forbidden', 'message': message},
    });

http.StreamedResponse _response(int status, Object body) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    status,
  );
}

Map<String, Object?> _sessionData(String token) => <String, Object?>{
  'user': <String, Object?>{'username': 'admin'},
  'session_token': token,
  'expires_at': '2030-01-02T03:04:05Z',
  'authenticated': true,
};

Map<String, Object?> _deviceFixture({
  required String id,
  required bool detail,
}) {
  final imei = _runtimeSecret(15, 19);
  final iccid = _runtimeSecret(20, 23);
  final imsi = _runtimeSecret(15, 29);
  final phone = _runtimeSecret(13, 31);
  final rawSecret = _runtimeSecret(67, 37);
  return <String, Object?>{
    'id': id,
    'name': 'Lab modem',
    'device_type': 'pcie_ec20_ec25',
    'running': true,
    'healthy': true,
    'control_online': true,
    'physical_present': true,
    'worker_running': true,
    'data_connected': true,
    'radio_registered': true,
    'lifecycle_phase': 'ready',
    'lifecycle_reason': '',
    'public_ip': '',
    'private_ip': '',
    'interface': 'wwan0',
    'proxy_port': 1080,
    'esim_transport': 'qmi',
    'sms_enabled': true,
    'network_enabled': true,
    'developer_enabled': true,
    'network_connected': true,
    'vowifi_enabled': true,
    'vowifi_active': true,
    'flight_mode': false,
    'local_phone': phone,
    'phone_number_source': 'network',
    'registration_state_label': 'registered',
    'modem': <String, Object?>{
      'operator': 'One Carrier',
      'native_mcc': '001',
      'native_mnc': '01',
      'native_spn': 'One',
      'operator_country_code': 'ZZ',
      'card_mcc': '001',
      'card_mnc': '01',
      'card_country': 'Test',
      'home_carrier_name': 'One Carrier',
      'home_carrier_plmn': '00101',
      'home_carrier_country_code': 'ZZ',
      'service_blocked': false,
      'blocked_reason': '',
      'network_mode': 'LTE',
      'network_duplex': 'FDD',
      'radio_band': 'B3',
      'radio_channel': 1300,
      'signal_dbm': -73,
      'signal_rsrp': -96,
      'signal_rsrq': -11,
      'signal_sinr': 18,
      'imei': imei,
      'iccid': iccid,
      'imsi': imsi,
      'firmware': 'EC25EFAR06A11M4G',
      'model': 'EC25',
      'reg_status': 1,
      'reg_status_text': 'registered',
      'ps_attached': true,
      'sim_inserted': true,
      'operating_mode': 1,
      'phone_number': phone,
      'phone_number_source': 'network',
    },
    'vowifi_runtime': <String, Object?>{
      'device_id': id,
      'phase': 'ims_ready',
      'enabled': true,
      'active': true,
      'carrier_profile': <String, Object?>{'secret': rawSecret},
      'carrier_profile_from': 'runtime',
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
      'local_phone': phone,
      'phone_number_source': 'network',
      'last_error_class': '',
      'last_error': rawSecret,
      'last_reason': 'ready',
      'updated_at': '2026-09-01T00:00:00Z',
      'tunnel': <String, Object?>{'path': rawSecret},
      'imscore': <String, Object?>{'opaque': rawSecret},
      'smsip': <String, Object?>{'opaque': rawSecret},
    },
    'esim_switch': <String, Object?>{'status': rawSecret},
    if (detail) ...<String, Object?>{
      'at_port': rawSecret,
      'audio_device': rawSecret,
      'backend_mode': 'qmi',
      'control_device': rawSecret,
      'radio_live_ok': true,
      'traffic': <String, Object?>{
        'rx': '1 KB',
        'tx': '2 KB',
        'rate': '3 KB/s',
        'rate_tx': '4 KB/s',
      },
      'traffic_raw': <String, Object?>{
        'rx': 1024,
        'tx': 2048,
        'rate': 3072,
        'rate_tx': 4096,
      },
      'traffic_meta': <String, Object?>{'status': ''},
    },
  };
}

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}

String _runtimeDigits(int length, int offset) => List<String>.generate(
  length,
  (index) => ((index + offset) % 10).toString(),
).join();
