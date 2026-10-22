import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/sms/data/sms_api.dart';
import '../../../support/fakes.dart';

void main() {
  test('contacts and thread pagination keep phone identities opaque', () async {
    final rawPeer = _runtimeDigits(12, 3);
    final rawLocalPhone = _runtimeDigits(11, 7);
    final rawIccid = _runtimeDigits(20, 2);
    final requests = <http.BaseRequest>[];
    final api = SmsApi(
      _transport(
        FakeClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/contacts')) {
            return _response(200, <Object?>[
              _contact(
                peer: rawPeer,
                localPhone: rawLocalPhone,
                iccid: rawIccid,
              ),
            ]);
          }
          return _response(200, <Object?>[
            _message(id: 41, peer: rawPeer, body: 'Older message'),
            _message(id: 42, peer: rawPeer, body: 'Latest message'),
          ]);
        }),
      ),
    );

    final contacts = await api.fetchContacts();
    final contact = contacts.single;
    final page = await api.fetchThread(contact.target);
    await api.fetchThread(contact.target, cursor: page.nextCursor);

    expect(
      contact.peerDisplay,
      endsWith(rawPeer.substring(rawPeer.length - 4)),
    );
    expect(contact.localPhoneDisplay, endsWith(rawLocalPhone.substring(7)));
    expect(contact.iccidDisplay, endsWith(rawIccid.substring(16)));
    expect(contact.toString().contains(rawPeer), isFalse);
    expect(contact.target.toString().contains(rawPeer), isFalse);
    expect(contact.inboxKey.contains(rawPeer), isFalse);
    expect(page.messages.map((message) => message.body), <String>[
      'Older message',
      'Latest message',
    ]);
    expect(page.hasMore, isFalse);
    expect(requests.map((request) => request.url.toString()), <String>[
      'https://api.example.test/api/sms/contacts?limit=100',
      'https://api.example.test/api/sms/thread?device_id=device-a&peer=$rawPeer&iccid=$rawIccid&imsi=imsi-a&limit=100',
      'https://api.example.test/api/sms/thread?device_id=device-a&peer=$rawPeer&iccid=$rawIccid&imsi=imsi-a&before_id=41&limit=100',
    ]);
  });

  test(
    'send exposes complete multipart outcomes without automatic retry',
    () async {
      final rawPeer = _runtimeDigits(12, 4);
      final requests = <http.BaseRequest>[];
      var sendCount = 0;
      final api = SmsApi(
        _transport(
          FakeClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/contacts')) {
              return _response(200, <Object?>[_contact(peer: rawPeer)]);
            }
            sendCount += 1;
            return _response(
              502,
              _sendResult(outcome: 'failed', accepted: 0, retrySafe: false),
              errorCode: 'sms_submission_unconfirmed',
            );
          }),
        ),
      );
      final target = (await api.fetchContacts()).single.target;

      final result = await api.sendMessage(target, 'hello multipart');

      expect(sendCount, 1);
      expect(result.outcome.name, 'failed');
      expect(result.partsTotal, 2);
      expect(result.partsAccepted, 0);
      expect(result.retrySafe, isFalse);
      final request = requests.last;
      expect(request.method, 'POST');
      expect(request.headers['authorization'], startsWith('Bearer '));
      expect(request.headers.containsKey('cookie'), isFalse);
      expect(request.headers.containsKey('x-csrf-token'), isFalse);
      final body =
          jsonDecode(utf8.decode(await request.finalize().toBytes()))
              as Map<String, Object?>;
      expect(body, <String, Object?>{
        'device_id': 'device-a',
        'phone': rawPeer,
        'message': 'hello multipart',
      });
    },
  );

  test('delete thread uses DELETE and keeps identities in the query', () async {
    final rawPeer = _runtimeDigits(12, 5);
    final rawIccid = _runtimeDigits(20, 6);
    http.BaseRequest? deleteRequest;
    final api = SmsApi(
      _transport(
        FakeClient((request) async {
          if (request.url.path.endsWith('/contacts')) {
            return _response(200, <Object?>[
              _contact(peer: rawPeer, iccid: rawIccid),
            ]);
          }
          deleteRequest = request;
          return _response(200, <String, Object?>{'deleted': 4});
        }),
      ),
    );
    final target = (await api.fetchContacts()).single.target;
    final deleted = await api.deleteThread(target);
    expect(deleted, 4);
    expect(deleteRequest!.method, 'DELETE');
    expect(
      deleteRequest!.url.toString(),
      'https://api.example.test/api/sms/thread?device_id=device-a&peer=$rawPeer&iccid=$rawIccid&imsi=imsi-a',
    );
  });
}

Map<String, Object?> _contact({
  required String peer,
  String? localPhone,
  String? iccid,
}) => <String, Object?>{
  'device_id': 'device-a',
  'device_name': 'Travel modem',
  'modem_imei': 'opaque-imei',
  'iccid': iccid ?? '',
  'imsi': 'imsi-a',
  'local_phone': localPhone ?? '',
  'peer': peer,
  'display_name': '',
  'last_message': 'Latest message',
  'last_content': 'Latest message',
  'last_timestamp': '2026-09-02T08:30:00Z',
  'direction': 'inbound',
  'last_type': 'sms',
  'last_sms_id': 42,
  'unread_count': 1,
  'message_count': 2,
};

Map<String, Object?> _message({
  required int id,
  required String peer,
  required String body,
}) => <String, Object?>{
  'id': id,
  'message_id': 'message-$id',
  'device_id': 'device-a',
  'modem_imei': 'opaque-imei',
  'iccid': '',
  'imsi': 'imsi-a',
  'local_phone': '',
  'peer': peer,
  'direction': 'inbound',
  'body': body,
  'content': body,
  'sender': peer,
  'recipient': '',
  'type': 'sms',
  'timestamp': '2026-09-02T08:${id == 41 ? '20' : '30'}:00Z',
  'status': 'received',
  'source': 'ims',
  'parts_total': 1,
  'delivery_state': 'received',
};

Map<String, Object?> _sendResult({
  required String outcome,
  required int accepted,
  required bool retrySafe,
}) => <String, Object?>{
  'message_id': 'at-submit:safe',
  'id': 43,
  'parts_total': 2,
  'parts_attempted': 2,
  'parts_accepted': accepted,
  'all_parts_accepted': false,
  'concat_reference': 17,
  'part_results': <Object?>[],
  'delivery_state': 'unknown',
  'submission_state': 'unconfirmed',
  'message_reference': 0,
  'reference_known': false,
  'submission_accepted': false,
  'delivery_confirmed': false,
  'outcome': outcome,
  'transport': 'cellular_at',
  'retry_safe': retrySafe,
};

HttpTransport _transport(http.BaseClient client) => HttpTransport(
  client: client,
  originProvider: () async => Uri.parse('https://api.example.test'),
  tokenProvider: (_) async => _runtimeDigits(48, 9),
  requestIdGenerator: () => 'safe-sms-test',
);

http.StreamedResponse _response(
  int status,
  Object? data, {
  String? errorCode,
}) => http.StreamedResponse(
  Stream<List<int>>.value(
    utf8.encode(
      jsonEncode(<String, Object?>{
        if (errorCode != null)
          'error': <String, String>{
            'code': errorCode,
            'message': 'ignored backend detail',
          },
        'data': data,
      }),
    ),
  ),
  status,
);

String _runtimeDigits(int length, int offset) => List<String>.generate(
  length,
  (index) => ((index + offset) % 10).toString(),
).join();
