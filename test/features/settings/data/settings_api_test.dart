import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/settings/data/settings_api.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';
import '../../../support/fakes.dart';

void main() {
  test('loads preferences, system info, notifications and security', () async {
    final requests = <http.BaseRequest>[];
    final api = SettingsApi(
      _transport(
        FakeClient((request) async {
          requests.add(request);
          return switch (request.url.path) {
            '/api/settings/preferences' => _success(<String, Object?>{
              'language': 'zh',
            }),
            '/api/system/info' => _success(<String, Object?>{
              'version': 'v1.2.3',
              'build_time': '2026-09-03',
              'developer': true,
            }),
            '/api/settings/notifications' => _success(<String, Object?>{
              'telegram': <String, Object?>{
                'enabled': true,
                'bot_token': '',
                'chat_id': '1',
              },
              'webhook': <String, Object?>{
                'enabled': false,
                'urls': <Object?>['https://hooks.example.test/a'],
              },
            }),
            '/api/settings/security' => _success(<String, Object?>{
              'mode': 'internal',
              'allowed_cidrs': <Object?>['10.0.0.0/8'],
              'trust_proxy_headers': false,
              'trusted_proxy_cidrs': <Object?>[],
              'client_ip': '10.0.0.2',
              'client_allowed': true,
            }),
            _ => throw StateError(request.url.path),
          };
        }),
      ),
    );

    expect(await api.fetchPreferences(), UiLanguage.zh);
    final info = await api.fetchSystemInfo();
    expect(info.version, 'v1.2.3');
    expect(info.developer, isTrue);
    final notify = await api.fetchNotifications();
    expect(notify.telegram.enabled, isTrue);
    expect(notify.webhook.url, 'https://hooks.example.test/a');
    final security = await api.fetchSecurity();
    expect(security.allowedCidrs, <String>['10.0.0.0/8']);
    expect(requests.map((request) => request.url.path), <String>[
      '/api/settings/preferences',
      '/api/system/info',
      '/api/settings/notifications',
      '/api/settings/security',
    ]);
  });

  test('saves language, notifications and password', () async {
    http.BaseRequest? password;
    http.BaseRequest? notify;
    final api = SettingsApi(
      _transport(
        FakeClient((request) async {
          switch (request.url.path) {
            case '/api/settings/preferences':
              return _success(<String, Object?>{'language': 'en'});
            case '/api/settings/notifications':
              notify = request;
              return _success(<String, Object?>{
                'telegram': <String, Object?>{'enabled': true},
              });
            case '/api/settings/password':
              password = request;
              return _success(<String, Object?>{
                'changed': true,
                'reauthentication_required': true,
              });
            default:
              throw StateError(request.url.path);
          }
        }),
      ),
    );

    expect(await api.savePreferences(UiLanguage.en), UiLanguage.en);
    await api.saveNotifications(
      const NotificationSettings(
        telegram: NotifyChannelSettings(
          enabled: true,
          botToken: 't',
          chatId: '1',
        ),
      ),
    );
    await api.changePassword(
      oldPassword: 'old-password',
      newPassword: 'new-password-1',
      confirmPassword: 'new-password-1',
    );
    final pwd =
        jsonDecode(utf8.decode(await password!.finalize().toBytes()))
            as Map<String, Object?>;
    expect(pwd['old_password'], 'old-password');
    expect(pwd['new_password'], 'new-password-1');
    final body =
        jsonDecode(utf8.decode(await notify!.finalize().toBytes()))
            as Map<String, Object?>;
    expect((body['telegram'] as Map)['enabled'], isTrue);
  });

  test('telegram test posts WEB body; pushplus is rejected locally', () async {
    http.BaseRequest? seen;
    final api = SettingsApi(
      _transport(
        FakeClient((request) async {
          seen = request;
          return _success(<String, Object?>{'ok': true});
        }),
      ),
    );
    await api.testNotification(
      NotifyChannel.telegram,
      const NotifyChannelSettings(botToken: 'token', chatId: '9'),
    );
    expect(seen!.url.path, '/api/settings/notifications/telegram/test');
    final body =
        jsonDecode(utf8.decode(await seen!.finalize().toBytes()))
            as Map<String, Object?>;
    expect(body['enabled'], isTrue);
    expect(body['bot_token'], 'token');
    expect(body['chat_id'], '9');
    await expectLater(
      api.testNotification(
        NotifyChannel.pushplus,
        const NotifyChannelSettings(),
      ),
      throwsA(isA<SettingsDtoException>()),
    );
  });

  test('bark test posts urls without a stray url field', () async {
    http.BaseRequest? seen;
    final api = SettingsApi(
      _transport(
        FakeClient((request) async {
          seen = request;
          return _success(<String, Object?>{'ok': true});
        }),
      ),
    );
    await api.testNotification(
      NotifyChannel.bark,
      const NotifyChannelSettings(
        url: 'https://api.day.app/key/',
        group: 'onewifi',
        icon: 'https://icon.test/a.png',
        level: 'timeSensitive',
      ),
    );
    expect(seen!.url.path, '/api/settings/notifications/bark/test');
    final body =
        jsonDecode(utf8.decode(await seen!.finalize().toBytes()))
            as Map<String, Object?>;
    expect(body.containsKey('url'), isFalse);
    expect(body['urls'], <Object?>['https://api.day.app/key/']);
    expect(body['group'], 'onewifi');
    expect(body['level'], 'timeSensitive');
  });

  test('wrong password 401 does not expire the session', () async {
    var unauthorized = 0;
    final api = SettingsApi(
      HttpTransport(
        client: FakeClient((request) async {
          return http.StreamedResponse(
            Stream<List<int>>.value(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'error': <String, String>{
                    'code': 'UNAUTHORIZED',
                    'message': 'bad password',
                  },
                }),
              ),
            ),
            401,
          );
        }),
        originProvider: () async => Uri.parse('https://api.example.test'),
        tokenProvider: (_) async => 'token-token-token-token-token-token',
        requestIdGenerator: () => 'pwd-401',
        onUnauthorized: (_) {
          unauthorized += 1;
        },
      ),
    );
    await expectLater(
      api.changePassword(
        oldPassword: 'wrong-old-password',
        newPassword: 'new-password-1',
        confirmPassword: 'new-password-1',
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(unauthorized, 0);
  });

  test(
    'reads and writes VoWiFi MTU compatibility on /api/settings/vowifi',
    () async {
      http.BaseRequest? saved;
      final api = SettingsApi(
        _transport(
          FakeClient((request) async {
            if (request.method == 'PUT') saved = request;
            return _success(<String, Object?>{'mtu_compatibility': true});
          }),
        ),
      );
      expect((await api.fetchVowifiSettings()).mtuCompatibility, isTrue);
      final written = await api.saveVowifiSettings(true);
      expect(written.mtuCompatibility, isTrue);
      expect(saved!.url.path, '/api/settings/vowifi');
      final body =
          jsonDecode(utf8.decode(await saved!.finalize().toBytes()))
              as Map<String, Object?>;
      expect(body['mtu_compatibility'], isTrue);
    },
  );
}

HttpTransport _transport(http.BaseClient client) => HttpTransport(
  client: client,
  originProvider: () async => Uri.parse('https://api.example.test'),
  tokenProvider: (_) async => 'token-token-token-token-token-token',
  requestIdGenerator: () => 'settings-test',
);

http.StreamedResponse _success(Object? data) => http.StreamedResponse(
  Stream<List<int>>.value(
    utf8.encode(jsonEncode(<String, Object?>{'data': data})),
  ),
  200,
);
