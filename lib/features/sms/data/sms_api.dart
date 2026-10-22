import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../../../core/security/redaction.dart';
import '../domain/sms.dart';

part 'sms_dto.dart';

final class SmsApi {
  const SmsApi(this._transport);

  static const int _pageSize = 100;
  static const Duration _sendTimeout = Duration(minutes: 2);
  final HttpTransport _transport;

  Future<List<SmsContactDto>> fetchContacts({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.smsContacts,
      queryParameters: const <String, String?>{'limit': '$_pageSize'},
      cancellation: cancellation,
    );
    return List<SmsContactDto>.unmodifiable(
      _shape.list(data).map(_parseContact),
    );
  }

  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) async {
    final rawTarget = _target(target);
    final rawCursor = switch (cursor) {
      null => null,
      final _SmsThreadCursor value => value,
      _ => throw StateError('Invalid SMS thread cursor.'),
    };
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.smsThread,
      queryParameters: <String, String?>{
        'device_id': rawTarget._deviceId,
        'peer': rawTarget._peer,
        'iccid': rawTarget._iccid.isEmpty ? null : rawTarget._iccid,
        'imsi': rawTarget._imsi.isEmpty ? null : rawTarget._imsi,
        'before_id': rawCursor?._beforeId.toString(),
        'limit': '$_pageSize',
      },
      cancellation: cancellation,
    );
    final messages = _shape.list(data).map(_parseMessage).toList();
    messages.sort((left, right) {
      final leftTime = left.timestamp?.millisecondsSinceEpoch ?? 0;
      final rightTime = right.timestamp?.millisecondsSinceEpoch ?? 0;
      final byTime = leftTime.compareTo(rightTime);
      return byTime != 0 ? byTime : left.numericId.compareTo(right.numericId);
    });
    final oldestId = messages
        .map((message) => message.numericId)
        .where((id) => id > 0)
        .fold<int?>(
          null,
          (oldest, id) => oldest == null || id < oldest ? id : oldest,
        );
    final hasMore = messages.length == _pageSize && oldestId != null;
    return SmsThreadPage(
      messages: messages,
      nextCursor: oldestId == null ? null : _SmsThreadCursor(oldestId),
      hasMore: hasMore,
    );
  }

  Future<int> deleteThread(
    SmsContactTarget target, {
    RequestCancellation? cancellation,
  }) async {
    final rawTarget = _target(target);
    final data = await _transport.sendJson(
      method: 'DELETE',
      routeTemplate: GatewayApi.smsThread,
      queryParameters: <String, String?>{
        'device_id': rawTarget._deviceId,
        'peer': rawTarget._peer,
        'iccid': rawTarget._iccid.isEmpty ? null : rawTarget._iccid,
        'imsi': rawTarget._imsi.isEmpty ? null : rawTarget._imsi,
      },
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return _shape.nonNegativeInt(map['deleted']);
  }

  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) async {
    final rawTarget = _target(target);
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.smsSendGlobal,
      body: <String, String>{
        'device_id': rawTarget._deviceId,
        'phone': rawTarget._peer,
        'message': message,
      },
      timeout: _sendTimeout,
      cancellation: cancellation,
      acceptedDataStatusCodes: const <int>{502},
    );
    final map = _shape.map(data);
    final outcome = switch (_shape.string(map['outcome'])) {
      'delivered' => SmsSendOutcome.delivered,
      'accepted_unconfirmed' => SmsSendOutcome.acceptedUnconfirmed,
      'partial' => SmsSendOutcome.partial,
      'failed' => SmsSendOutcome.failed,
      _ => throw const SmsDtoException(),
    };
    final partsTotal = _shape.nonNegativeInt(map['parts_total']);
    final partsAccepted = _shape.nonNegativeInt(map['parts_accepted']);
    if (partsAccepted > partsTotal) throw const SmsDtoException();
    final retrySafe = map['retry_safe'];
    if (retrySafe != null && retrySafe is! bool) {
      throw const SmsDtoException();
    }
    return SmsSendResult(
      outcome: outcome,
      partsTotal: partsTotal,
      partsAccepted: partsAccepted,
      retrySafe: retrySafe == true,
    );
  }

  Future<bool> deleteMessage(
    int messageId, {
    RequestCancellation? cancellation,
  }) async {
    if (messageId < 1) throw const SmsDtoException();
    final data = await _transport.sendJson(
      method: 'DELETE',
      routeTemplate: GatewayApi.smsMessage,
      pathParameters: <String, String>{'id': '$messageId'},
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return map['deleted'] == true;
  }

  static _SmsContactTarget _target(SmsContactTarget target) {
    if (target is! _SmsContactTarget) {
      throw StateError('Invalid SMS contact target.');
    }
    return target;
  }
}
