import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/sms.dart';
import 'sms_api.dart';

abstract interface class SmsRepository {
  Future<List<SmsContact>> fetchContacts({RequestCancellation? cancellation});

  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  });

  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  });

  Future<int> deleteThread(
    SmsContactTarget target, {
    RequestCancellation? cancellation,
  });

  Future<bool> deleteMessage(
    int messageId, {
    RequestCancellation? cancellation,
  });
}

final class DefaultSmsRepository implements SmsRepository {
  const DefaultSmsRepository(this._api);
  final SmsApi _api;

  @override
  Future<List<SmsContact>> fetchContacts({
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-sms-response', () async {
      final contacts = await _api.fetchContacts(cancellation: cancellation);
      return List<SmsContact>.unmodifiable(
        contacts.map(
          (contact) => SmsContact(
            peerDisplay: contact.peerDisplay,
            localPhoneDisplay: contact.localPhoneDisplay,
            iccidDisplay: contact.iccidDisplay,
            deviceName: contact.deviceName,
            preview: contact.preview,
            messageCount: contact.messageCount,
            unreadCount: contact.unreadCount,
            lastTimestamp: contact.lastTimestamp,
            target: contact.target,
            inboxKey: contact.inboxKey,
            direction: contact.direction,
            lastSmsId: contact.lastSmsId,
          ),
        ),
      );
    });
  }

  @override
  Future<SmsThreadPage> fetchThread(
    SmsContactTarget target, {
    SmsThreadCursor? cursor,
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-sms-response', () async {
      final page = await _api.fetchThread(
        target,
        cursor: cursor,
        cancellation: cancellation,
      );
      return SmsThreadPage(
        messages: page.messages,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    });
  }

  @override
  Future<SmsSendResult> sendMessage(
    SmsContactTarget target,
    String message, {
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-sms-response', () async {
      return await _api.sendMessage(
        target,
        message,
        cancellation: cancellation,
      );
    });
  }

  @override
  Future<int> deleteThread(
    SmsContactTarget target, {
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-sms-response', () async {
      return await _api.deleteThread(target, cancellation: cancellation);
    });
  }

  @override
  Future<bool> deleteMessage(
    int messageId, {
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-sms-response', () async {
      return await _api.deleteMessage(messageId, cancellation: cancellation);
    });
  }
}
