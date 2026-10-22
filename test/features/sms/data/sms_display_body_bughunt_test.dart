import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/sms/data/sms_api.dart';
import '../../../support/fakes.dart';

// B2-04：`_displayBody` 把「≥16、偶数、全是 0-9A-F」当成 PDU 转储藏成「系统短信」。
// 纯数字也满足该字符集，快递单号 / 卡密会被误藏。
//
// 产品裁定：必须含 A–F 才替换；纯数字原样显示。含 A–F 的 PDU 转储仍替换。
void main() {
  test('20 位纯数字正文应原样显示', () async {
    const trackingNumber = '78123456789012345678';
    final api = SmsApi(
      _transport(
        FakeClient((request) async {
          if (request.url.path.endsWith('/contacts')) {
            return _response(<Object?>[_contact()]);
          }
          return _response(<Object?>[_message(trackingNumber)]);
        }),
      ),
    );

    final target = (await api.fetchContacts()).single.target;
    final page = await api.fetchThread(target);
    expect(page.messages.single.body, trackingNumber);
  });

  test('联系人预览的 16 位纯数字应原样显示', () async {
    const code = '1234567890123456';
    final api = SmsApi(
      _transport(
        FakeClient(
          (_) async => _response(<Object?>[_contact(lastContent: code)]),
        ),
      ),
    );

    expect((await api.fetchContacts()).single.preview, code);
  });

  test('含 A–F 的 PDU 十六进制转储仍显示为系统短信', () async {
    const pdu =
        '0791448720003023240DD0E474D81C0EBB010000111011315214000BE8329BFD06DDDF723619';
    final api = SmsApi(
      _transport(
        FakeClient(
          (_) async => _response(<Object?>[_contact(lastContent: pdu)]),
        ),
      ),
    );

    expect((await api.fetchContacts()).single.preview, '收到一条系统短信');
  });
}

Map<String, Object?> _contact({String lastContent = 'Latest message'}) =>
    <String, Object?>{
      'device_id': 'device-a',
      'device_name': 'Travel modem',
      'iccid': '',
      'imsi': 'imsi-a',
      'local_phone': '',
      'peer': '13800001234',
      'last_content': lastContent,
      'last_timestamp': '2026-09-02T08:30:00Z',
      'unread_count': 1,
      'message_count': 2,
    };

Map<String, Object?> _message(String body) => <String, Object?>{
  'id': 1,
  'message_id': 'message-1',
  'device_id': 'device-a',
  'iccid': '',
  'imsi': 'imsi-a',
  'local_phone': '',
  'peer': '13800001234',
  'direction': 'inbound',
  'content': body,
  'timestamp': '2026-09-02T08:30:00Z',
};

HttpTransport _transport(http.BaseClient client) => HttpTransport(
  client: client,
  originProvider: () async => Uri.parse('https://api.example.test'),
  tokenProvider: (_) async => 'bughunt-token',
  requestIdGenerator: () => 'bughunt-sms',
);

http.StreamedResponse _response(Object? data) => http.StreamedResponse(
  Stream<List<int>>.value(
    utf8.encode(jsonEncode(<String, Object?>{'data': data})),
  ),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);
