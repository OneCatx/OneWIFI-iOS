import 'dart:io';

import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/call.dart';
import 'calls_api.dart';

abstract interface class CallsRepository {
  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  });

  Future<VoiceCall> dial(
    String deviceId,
    String number, {
    RequestCancellation? cancellation,
  });

  Future<VoiceCall> answer(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  });

  Future<void> hangup(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  });

  Future<CallMediaMeta> fetchMediaMeta(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  });

  Future<void> sendDtmf(
    String deviceId,
    String callId, {
    String? digit,
    String? digits,
    RequestCancellation? cancellation,
  });

  Future<CallMediaTicket> createMediaTicket(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  });

  Future<List<CallHistoryEntry>> fetchHistory(
    String deviceId, {
    RequestCancellation? cancellation,
  });

  Future<CallMediaCapabilities> fetchMediaCapabilities({
    RequestCancellation? cancellation,
  });

  Future<WebSocket> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  });
}

final class DefaultCallsRepository implements CallsRepository {
  const DefaultCallsRepository(this._api);
  final CallsApi _api;

  @override
  Future<List<VoiceCall>> fetchCalls(
    String deviceId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.fetchCalls(deviceId, cancellation: cancellation),
    );
  }

  @override
  Future<VoiceCall> dial(
    String deviceId,
    String number, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.dial(deviceId, number, cancellation: cancellation),
    );
  }

  @override
  Future<VoiceCall> answer(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.answer(deviceId, callId, cancellation: cancellation),
    );
  }

  @override
  Future<void> hangup(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.hangup(deviceId, callId, cancellation: cancellation),
    );
  }

  @override
  Future<CallMediaMeta> fetchMediaMeta(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.fetchMediaMeta(deviceId, callId, cancellation: cancellation),
    );
  }

  @override
  Future<void> sendDtmf(
    String deviceId,
    String callId, {
    String? digit,
    String? digits,
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.sendDtmf(
        deviceId,
        callId,
        digit: digit,
        digits: digits,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<CallMediaTicket> createMediaTicket(
    String deviceId,
    String callId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.createMediaTicket(
        deviceId,
        callId,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<List<CallHistoryEntry>> fetchHistory(
    String deviceId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.fetchHistory(deviceId, cancellation: cancellation),
    );
  }

  @override
  Future<CallMediaCapabilities> fetchMediaCapabilities({
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-calls-response',
      () => _api.fetchMediaCapabilities(cancellation: cancellation),
    );
  }

  @override
  Future<WebSocket> openMediaSocket({
    required Uri origin,
    required String deviceId,
    required String callId,
    required String? accessToken,
  }) {
    return _api.openMediaSocket(
      origin: origin,
      deviceId: deviceId,
      callId: callId,
      accessToken: accessToken,
    );
  }
}
