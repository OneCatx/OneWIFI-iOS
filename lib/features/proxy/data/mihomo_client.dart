import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/mihomo_backend.dart';
import '../domain/wifi_call_group.dart';

final class MihomoDtoException implements DtoShapeException {
  const MihomoDtoException();
}

const _shape = JsonShape(MihomoDtoException.new);

/// Clash Meta / Mihomo REST：`GET /proxies`、`GET /connections`、`PUT /proxies/{group}`。
///
/// 不走 OneWIFI `{data}` 信封，也不用网关 token；401 不得踢掉 OneWIFI 会话。
final class MihomoClient {
  factory MihomoClient({
    required http.BaseClient client,
    Future<Uri> Function()? originProvider,
    Future<String?> Function()? secretProvider,
    Future<MihomoBackend> Function()? backendProvider,
    String Function()? requestIdGenerator,
    DateTime Function()? clock,
  }) => MihomoClient._(
    client,
    originProvider,
    secretProvider,
    backendProvider,
    requestIdGenerator,
    clock ?? DateTime.now,
  );

  MihomoClient._(
    this._client,
    this._originProvider,
    this._secretProvider,
    this._backendProvider,
    this._requestIdGenerator,
    this._clock,
  );

  final http.BaseClient _client;
  final Future<Uri> Function()? _originProvider;
  final Future<String?> Function()? _secretProvider;
  final Future<MihomoBackend> Function()? _backendProvider;
  final String Function()? _requestIdGenerator;
  final DateTime Function() _clock;
  int _requestSequence = 0;

  Future<Map<String, Object?>> fetchProxies({
    RequestCancellation? cancellation,
    Uri? origin,
    String? secret,
  }) async {
    return guardShape('local-mihomo-response', () async {
      final data = await _send(
        method: 'GET',
        path: '/proxies',
        cancellation: cancellation,
        origin: origin,
        secret: secret,
      );
      final root = _shape.map(data);
      return _stringKeyed(_shape.map(root['proxies']));
    });
  }

  Future<Map<String, Object?>> fetchConnections({
    RequestCancellation? cancellation,
    Uri? origin,
    String? secret,
  }) async {
    return guardShape('local-mihomo-response', () async {
      final data = await _send(
        method: 'GET',
        path: '/connections',
        cancellation: cancellation,
        emptyOk: true,
        origin: origin,
        secret: secret,
      );
      if (data == null) return const <String, Object?>{};
      return _stringKeyed(_shape.map(data));
    });
  }

  Future<void> selectProxy({
    required String group,
    required String name,
    RequestCancellation? cancellation,
    Uri? origin,
    String? secret,
  }) async {
    final trimmedGroup = group.trim();
    final trimmedName = name.trim();
    if (trimmedGroup.isEmpty || trimmedName.isEmpty) {
      throw const MihomoDtoException();
    }
    await _send(
      method: 'PUT',
      path: '/proxies/${Uri.encodeComponent(trimmedGroup)}',
      body: <String, String>{'name': trimmedName},
      cancellation: cancellation,
      emptyOk: true,
      origin: origin,
      secret: secret,
    );
  }

  Future<WifiDelay> fetchProxyDelay({
    required String name,
    RequestCancellation? cancellation,
    Uri? origin,
    String? secret,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const WifiDelay.unknown();
    try {
      final data = await _send(
        method: 'GET',
        path: '',
        pathSegments: <String>['proxies', trimmed, 'delay'],
        query: const <String, String>{
          'timeout': '5000',
          'url': 'https://www.gstatic.com/generate_204',
        },
        cancellation: cancellation,
        emptyOk: true,
        origin: origin,
        secret: secret,
        timeout: const Duration(seconds: 12),
      );
      if (data is Map<Object?, Object?>) {
        return _delayResult(_delayValue(data['delay']));
      }
      if (data is Map) {
        return _delayResult(_delayValue(data['delay']));
      }
      return const WifiDelay.unknown();
    } on ApiFailure catch (failure) {
      return _delayFailure(failure);
    }
  }

  /// Clash Verge 同款：一次测完整组，结果是 `{节点名: ms}`，名字不进 URL。
  ///
  /// 返回 `null` 表示这不是组（404），调用方再退回逐叶子探测。
  Future<Map<String, WifiDelay>?> fetchGroupDelay({
    required String name,
    RequestCancellation? cancellation,
    Uri? origin,
    String? secret,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    try {
      final data = await _send(
        method: 'GET',
        path: '',
        pathSegments: <String>['group', trimmed, 'delay'],
        query: const <String, String>{
          'timeout': '5000',
          'url': 'https://www.gstatic.com/generate_204',
        },
        cancellation: cancellation,
        emptyOk: true,
        origin: origin,
        secret: secret,
        timeout: const Duration(seconds: 20),
      );
      return _groupDelayMap(data);
    } on ApiFailure catch (failure) {
      if (failure.statusCode == 404) return null;
      if (failure.kind == ApiFailureKind.authentication ||
          failure.kind == ApiFailureKind.cancelled) {
        return null;
      }
      return const <String, WifiDelay>{};
    }
  }

  static WifiDelay _delayResult(int ms) {
    if (ms > 0) return WifiDelay.measured(ms);
    return const WifiDelay.timedOut();
  }

  static WifiDelay _delayFailure(ApiFailure failure) {
    if (failure.kind == ApiFailureKind.timeout) {
      return const WifiDelay.timedOut();
    }
    final status = failure.statusCode;
    if (status == 408 || status == 502 || status == 503 || status == 504) {
      return const WifiDelay.timedOut();
    }
    return const WifiDelay.unknown();
  }

  static Map<String, WifiDelay> _groupDelayMap(Object? data) {
    if (data is! Map) return const <String, WifiDelay>{};
    final out = <String, WifiDelay>{};
    for (final entry in data.entries) {
      final key = entry.key;
      if (key is! String || key.isEmpty) continue;
      if (key == 'message') continue;
      out[key] = _delayResult(_delayValue(entry.value));
    }
    return out;
  }

  static int _delayValue(Object? value) {
    if (value is int) return value < 0 ? 0 : value;
    if (value is double && value.isFinite) {
      final rounded = value.round();
      return rounded < 0 ? 0 : rounded;
    }
    return 0;
  }

  Future<Object?> _send({
    required String method,
    required String path,
    Object? body,
    RequestCancellation? cancellation,
    bool emptyOk = false,
    Duration timeout = const Duration(seconds: 15),
    Uri? origin,
    String? secret,
    List<String>? pathSegments,
    Map<String, String>? query,
  }) async {
    final requestId = _newRequestId();
    final timeoutCompleter = Completer<void>();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      timeoutCompleter.complete();
    });
    final abortTrigger = cancellation == null
        ? timeoutCompleter.future
        : Future.any<void>(<Future<void>>[
            timeoutCompleter.future,
            cancellation.whenCancelled,
          ]);
    try {
      if (cancellation?.isCancelled ?? false) throw const _Stopped();
      final Uri resolvedOrigin;
      MihomoBackend? backend;
      try {
        if (origin == null && _backendProvider != null) {
          backend = await _awaitOrAbort(_backendProvider(), abortTrigger);
        }
        resolvedOrigin =
            origin ??
            backend?.origin ??
            await _awaitOrAbort(_originProvider!(), abortTrigger);
      } on _Stopped {
        rethrow;
      } catch (_) {
        throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
      }
      if (cancellation?.isCancelled ?? false) throw const _Stopped();

      String? resolvedSecret = secret ?? backend?.secret;
      final secrets = _secretProvider;
      if (resolvedSecret == null && secrets != null) {
        try {
          resolvedSecret = await _awaitOrAbort(secrets(), abortTrigger);
        } on _Stopped {
          rethrow;
        } catch (_) {
          throw ApiFailure(ApiFailureKind.authentication, requestId: requestId);
        }
      }

      if (cancellation?.isCancelled ?? false) throw const _Stopped();
      final request =
          http.AbortableRequest(
              method,
              _requestUri(
                origin: resolvedOrigin,
                path: path,
                pathSegments: pathSegments,
                query: query,
              ),
              abortTrigger: abortTrigger,
            )
            ..followRedirects = false
            ..headers['accept'] = 'application/json';
      final trimmedSecret = resolvedSecret?.trim();
      if (trimmedSecret != null && trimmedSecret.isNotEmpty) {
        request.headers['authorization'] = 'Bearer $trimmedSecret';
      }
      if (body != null) {
        request
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode(body);
      }

      final streamed = await _awaitOrAbort(_client.send(request), abortTrigger);
      final response = await _awaitOrAbort(
        http.Response.fromStream(streamed),
        abortTrigger,
      );
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw ApiFailure(
          ApiFailureKind.redirect,
          requestId: requestId,
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 204 || response.statusCode == 205) {
        return null;
      }
      if (response.statusCode == 401) {
        throw ApiFailure(
          ApiFailureKind.authentication,
          requestId: requestId,
          statusCode: 401,
        );
      }
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      if (!ok) {
        throw ApiFailure(
          ApiFailureKind.http,
          requestId: requestId,
          statusCode: response.statusCode,
        );
      }
      final text = _utf8Body(response);
      if (text.isEmpty) {
        if (emptyOk) return null;
        throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
      }
      try {
        return jsonDecode(text);
      } on FormatException {
        throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
      }
    } on ApiFailure {
      rethrow;
    } on _Stopped {
      throw ApiFailure(
        cancellation?.isCancelled ?? false
            ? ApiFailureKind.cancelled
            : timedOut
            ? ApiFailureKind.timeout
            : ApiFailureKind.cancelled,
        requestId: requestId,
      );
    } on http.RequestAbortedException {
      throw ApiFailure(
        cancellation?.isCancelled ?? false
            ? ApiFailureKind.cancelled
            : timedOut
            ? ApiFailureKind.timeout
            : ApiFailureKind.cancelled,
        requestId: requestId,
      );
    } catch (_) {
      throw ApiFailure(ApiFailureKind.network, requestId: requestId);
    } finally {
      timer.cancel();
    }
  }

  static Uri _requestUri({
    required Uri origin,
    required String path,
    List<String>? pathSegments,
    Map<String, String>? query,
  }) {
    if (pathSegments != null) {
      return origin.replace(
        pathSegments: <String>[
          ...origin.pathSegments.where((part) => part.isNotEmpty),
          ...pathSegments,
        ],
        queryParameters: query,
      );
    }
    final parsed = Uri.parse('${origin.toString()}$path');
    if (query == null || query.isEmpty) return parsed;
    return parsed.replace(
      queryParameters: <String, String>{...parsed.queryParameters, ...query},
    );
  }

  Map<String, Object?> _stringKeyed(Map<Object?, Object?> raw) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) throw const MihomoDtoException();
      out[key] = entry.value;
    }
    return out;
  }

  String _newRequestId() {
    final generator = _requestIdGenerator;
    if (generator != null) return generator();
    _requestSequence += 1;
    return 'local-${_clock().microsecondsSinceEpoch.toRadixString(36)}-${_requestSequence.toRadixString(36)}';
  }

  static String _utf8Body(http.Response response) {
    if (response.bodyBytes.isEmpty) return '';
    return utf8.decode(response.bodyBytes);
  }

  static Future<T> _awaitOrAbort<T>(
    Future<T> pending,
    Future<void> abortTrigger,
  ) {
    return Future.any<T>(<Future<T>>[pending, _abortAs<T>(abortTrigger)]);
  }

  static Future<T> _abortAs<T>(Future<void> abortTrigger) async {
    await abortTrigger;
    throw const _Stopped();
  }
}

final class _Stopped implements Exception {
  const _Stopped();
}
