import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/settings/data/settings_api.dart';
import '../../../support/fakes.dart';

/// B2-03 · 通知设置往返不得丢掉网关上已有的副 URL。
///
/// 期望来源：
/// - 同文件对 `to_addresses` 用 `_joinAddresses` / `splitAddressList` 完整往返
///   （`settings_dto.dart`），列表字段往返不丢。
/// - `PUT /api/settings/notifications` 是整体替换（`docs/http-api.md`）。
void main() {
  group('SettingsApi · 通知设置往返不丢数据', () {
    test('网关返回多条 webhook urls 时，回写必须把每一条都带回去', () async {
      const urls = <String>[
        'https://hooks.example.test/primary',
        'https://hooks.example.test/secondary',
      ];
      http.BaseRequest? put;
      final api = SettingsApi(
        _transport(
          FakeClient((request) async {
            if (request.method == 'PUT') put = request;
            return _success(<String, Object?>{
              'telegram': <String, Object?>{'enabled': false},
              'webhook': <String, Object?>{
                'enabled': true,
                'urls': urls,
                'secret': '',
                'timeout_ms': 5000,
              },
            });
          }),
        ),
      );

      final fetched = await api.fetchNotifications();
      await api.saveNotifications(fetched);

      final body =
          jsonDecode(utf8.decode(await put!.finalize().toBytes()))
              as Map<String, Object?>;
      final webhook = body['webhook']! as Map<String, Object?>;
      expect(
        webhook['urls'],
        urls,
        reason: '回写体里的 webhook.urls 少了网关原有的地址（数据丢失）',
      );
    });

    test('bark / wecom 的多条 urls 同样必须完整往返', () async {
      const urls = <String>[
        'https://api.day.app/key-one',
        'https://api.day.app/key-two',
      ];
      http.BaseRequest? put;
      final api = SettingsApi(
        _transport(
          FakeClient((request) async {
            if (request.method == 'PUT') put = request;
            return _success(<String, Object?>{
              'bark': <String, Object?>{'enabled': true, 'urls': urls},
              'wecom': <String, Object?>{'enabled': true, 'urls': urls},
            });
          }),
        ),
      );

      final fetched = await api.fetchNotifications();
      await api.saveNotifications(fetched);

      final body =
          jsonDecode(utf8.decode(await put!.finalize().toBytes()))
              as Map<String, Object?>;
      expect((body['bark']! as Map<String, Object?>)['urls'], urls);
      expect((body['wecom']! as Map<String, Object?>)['urls'], urls);
    });
  });
}

HttpTransport _transport(http.BaseClient client) => HttpTransport(
  client: client,
  originProvider: () async => Uri.parse('https://api.example.test'),
  tokenProvider: (_) async => 'bughunt-token',
  requestIdGenerator: () => 'bughunt-settings',
);

http.StreamedResponse _success(Object? data) => http.StreamedResponse(
  Stream<List<int>>.value(
    utf8.encode(jsonEncode(<String, Object?>{'data': data})),
  ),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);
