import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:http/http.dart' as http;

import 'backend_error_codes.dart';
import 'sse_decoder.dart';

/// Authentication mode for HTTP requests.
enum AuthMode { 
  /// No authentication header.
  none, 
  /// Bearer token authentication (Authorization: Bearer <token>).
  bearer 
}

/// Categories of API request failures.
enum ApiFailureKind {
  /// Authentication or authorization failure (401, 403).
  authentication,
  /// Protocol-level error (malformed request/response).
  protocol,
  /// HTTP-level error (4xx, 5xx status codes).
  http,
  /// Unexpected redirect.
  redirect,
  /// Request timeout.
  timeout,
  /// Request cancelled by caller.
  cancelled,
  /// Network connectivity error.
  network,
}

/// Represents a failed API request with detailed error information.
final class ApiFailure implements Exception {
  /// Creates an [ApiFailure] with the specified kind and details.
  ///
  /// Parameters:
  /// - [kind]: Category of failure
  /// - [requestId]: Unique identifier for this request
  /// - [statusCode]: HTTP status code, if available
  /// - [backendCode]: Backend-specific error code, if available
  /// - [message]: Human-readable error message
  /// - [retryAfter]: Suggested retry delay (from Retry-After header)
  const ApiFailure(
    this.kind, {
    required this.requestId,
    this.statusCode,
    this.backendCode,
    this.message = 'Request failed.',
    this.retryAfter,
  });

  final ApiFailureKind kind;
  final int? statusCode;
  final String? backendCode;
  final String message;
  final Duration? retryAfter;
  final String requestId;
}

/// Allows cancelling in-flight HTTP requests.
final class RequestCancellation {
  final Completer<void> _completer = Completer<void>();

  /// Future that completes when [cancel] is called.
  Future<void> get whenCancelled => _completer.future;
  
  /// Whether this cancellation has been triggered.
  bool get isCancelled => _completer.isCompleted;

  /// Triggers cancellation of associated requests.
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// HTTP transport layer for gateway API communication.
///
/// This transport handles:
/// - JSON request/response serialization
/// - Server-Sent Events (SSE) streaming
/// - Bearer token authentication
/// - Request cancellation and timeouts
/// - Session expiration on 401 responses
/// - Retry-After header parsing
/// - Request ID generation and tracking
///
/// The transport is protocol-agnostic and delegates origin/token resolution
/// to injected providers, allowing it to work with any authentication system.
final class HttpTransport {
  /// Creates an [HttpTransport] with the specified dependencies.
  ///
  /// Parameters:
  /// - [client]: HTTP client for making requests
  /// - [originProvider]: Async function that returns the current gateway origin
  /// - [tokenProvider]: Async function that returns the auth token for an origin
  /// - [onUnauthorized]: Optional callback triggered on 401 responses
  /// - [sessionEpoch]: Optional function that returns current session epoch
  /// - [clock]: Optional clock function for time-based operations
  /// - [requestIdGenerator]: Optional function to generate request IDs
  factory HttpTransport({
    required http.BaseClient client,
    required Future<Uri> Function() originProvider,
    required Future<String?> Function(Uri origin) tokenProvider,
    FutureOr<void> Function(int capturedSessionEpoch)? onUnauthorized,
    int Function()? sessionEpoch,
    DateTime Function()? clock,
    String Function()? requestIdGenerator,
  }) => HttpTransport._(
    client,
    originProvider,
    tokenProvider,
    onUnauthorized,
    sessionEpoch ?? _zeroEpoch,
    clock ?? DateTime.now,
    requestIdGenerator,
  );

  HttpTransport._(
    this._client,
    this._originProvider,
    this._tokenProvider,
    this._onUnauthorized,
    this._sessionEpoch,
    this._clock,
    this._requestIdGenerator,
  );

  final http.BaseClient _client;
  final Future<Uri> Function() _originProvider;
  final Future<String?> Function(Uri origin) _tokenProvider;
  final FutureOr<void> Function(int capturedSessionEpoch)? _onUnauthorized;
  final int Function() _sessionEpoch;
  final DateTime Function() _clock;
  final String Function()? _requestIdGenerator;
  int _requestSequence = 0;

  /// Sends a JSON request and returns the deserialized response.
  ///
  /// Parameters:
  /// - [method]: HTTP method (GET, POST, PUT, DELETE, etc.)
  /// - [routeTemplate]: Path template with {param} placeholders
  /// - [pathParameters]: Values to substitute into the route template
  /// - [queryParameters]: URL query parameters (null values are excluded)
  /// - [body]: Request body (serialized to JSON if non-null)
  /// - [authMode]: Authentication mode (bearer token or none)
  /// - [timeout]: Request timeout duration
  /// - [cancellation]: Optional cancellation token
  /// - [expireSessionOnUnauthorized]: Whether to trigger session expiration on 401
  /// - [acceptedDataStatusCodes]: Additional status codes to treat as success
  ///
  /// Returns the deserialized JSON response body.
  ///
  /// Throws [ApiFailure] on any error (network, protocol, HTTP status, timeout, etc.).
  Future<Object?> sendJson({
    required String method,
    required String routeTemplate,
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, String?> queryParameters = const <String, String?>{},
    Object? body,
    AuthMode authMode = AuthMode.bearer,
    Duration timeout = const Duration(seconds: 15),
    RequestCancellation? cancellation,
    bool expireSessionOnUnauthorized = true,
    Set<int> acceptedDataStatusCodes = const <int>{},
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
      if (cancellation?.isCancelled ?? false) throw const _RequestStopped();
      final capturedSessionEpoch = _sessionEpoch();
      final Uri origin;
      try {
        origin = await _awaitOrAbort(_originProvider(), abortTrigger);
      } on _RequestStopped {
        rethrow;
      } catch (_) {
        throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
      }
      String? token;
      if (authMode == AuthMode.bearer) {
        try {
          token = await _awaitOrAbort(_tokenProvider(origin), abortTrigger);
        } on _RequestStopped {
          rethrow;
        } catch (_) {
          throw ApiFailure(ApiFailureKind.authentication, requestId: requestId);
        }
        if (token == null || token.trim().isEmpty) {
          throw ApiFailure(ApiFailureKind.authentication, requestId: requestId);
        }
      }
      if (cancellation?.isCancelled ?? false) throw const _RequestStopped();

      final request =
          http.AbortableRequest(
              method,
              _buildUri(origin, routeTemplate, pathParameters, queryParameters),
              abortTrigger: abortTrigger,
            )
            ..followRedirects = false
            ..headers['accept'] = 'application/json';
      if (authMode == AuthMode.bearer) {
        request.headers['authorization'] = 'Bearer $token';
      }
      if (body != null) {
        request
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode(body);
      }

      final streamedResponse = await _awaitOrAbort(
        _client.send(request),
        abortTrigger,
      );
      final response = await _awaitOrAbort(
        http.Response.fromStream(streamedResponse),
        abortTrigger,
      );
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw ApiFailure(
          ApiFailureKind.redirect,
          requestId: requestId,
          statusCode: response.statusCode,
          message: 'The server returned an unexpected redirect.',
        );
      }
      if (response.statusCode == 204 || response.statusCode == 205) {
        if (_utf8Body(response).isNotEmpty) {
          throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
        }
        return null;
      }
      if (response.statusCode == 401 &&
          authMode == AuthMode.bearer &&
          expireSessionOnUnauthorized &&
          _onUnauthorized != null) {
        try {
          await _onUnauthorized(capturedSessionEpoch);
        } catch (_) {
          // Preserve the sanitized HTTP outcome when session cleanup fails.
        }
      }
      final hasAcceptedData =
          response.statusCode >= 200 && response.statusCode < 300 ||
          acceptedDataStatusCodes.contains(response.statusCode);
      if (!hasAcceptedData) {
        final decoded = jsonDecode(_utf8Body(response));
        if (decoded is! Map<Object?, Object?> ||
            decoded['error'] is! Map<Object?, Object?>) {
          throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
        }
        final error = decoded['error'] as Map<Object?, Object?>;
        if (error['code'] is! String || error['message'] is! String) {
          throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
        }
        throw ApiFailure(
          ApiFailureKind.http,
          requestId: requestId,
          statusCode: response.statusCode,
          backendCode: _safeBackendCode(error['code'] as String),
          message: _messageForHttpStatus(response.statusCode),
          retryAfter: _parseRetryAfter(response.headers['retry-after']),
        );
      }
      final decoded = jsonDecode(_utf8Body(response));
      if (decoded is! Map<Object?, Object?> || !decoded.containsKey('data')) {
        throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
      }
      return decoded['data'];
    } on ApiFailure {
      rethrow;
    } on _RequestStopped {
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
    } on FormatException {
      throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
    } catch (_) {
      throw ApiFailure(ApiFailureKind.network, requestId: requestId);
    } finally {
      timer.cancel();
    }
  }

  /// Sends a request and returns the raw response body bytes.
  ///
  /// Use this for non-JSON payloads (for example PEM certificate download).
  /// Error responses still expect the standard JSON `{ "error": { ... } }`
  /// envelope used by the gateway.
  Future<List<int>> sendBytes({
    required String method,
    required String routeTemplate,
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, String?> queryParameters = const <String, String?>{},
    Object? body,
    AuthMode authMode = AuthMode.bearer,
    Duration timeout = const Duration(seconds: 15),
    RequestCancellation? cancellation,
    bool expireSessionOnUnauthorized = true,
    String accept =
        'application/octet-stream, application/x-pem-file, */*',
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
      if (cancellation?.isCancelled ?? false) throw const _RequestStopped();
      final capturedSessionEpoch = _sessionEpoch();
      final Uri origin;
      try {
        origin = await _awaitOrAbort(_originProvider(), abortTrigger);
      } on _RequestStopped {
        rethrow;
      } catch (_) {
        throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
      }
      String? token;
      if (authMode == AuthMode.bearer) {
        try {
          token = await _awaitOrAbort(_tokenProvider(origin), abortTrigger);
        } on _RequestStopped {
          rethrow;
        } catch (_) {
          throw ApiFailure(ApiFailureKind.authentication, requestId: requestId);
        }
        if (token == null || token.trim().isEmpty) {
          throw ApiFailure(ApiFailureKind.authentication, requestId: requestId);
        }
      }
      if (cancellation?.isCancelled ?? false) throw const _RequestStopped();

      final request =
          http.AbortableRequest(
              method,
              _buildUri(origin, routeTemplate, pathParameters, queryParameters),
              abortTrigger: abortTrigger,
            )
            ..followRedirects = false
            ..headers['accept'] = accept;
      if (authMode == AuthMode.bearer) {
        request.headers['authorization'] = 'Bearer $token';
      }
      if (body != null) {
        request
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode(body);
      }

      final streamedResponse = await _awaitOrAbort(
        _client.send(request),
        abortTrigger,
      );
      final response = await _awaitOrAbort(
        http.Response.fromStream(streamedResponse),
        abortTrigger,
      );
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw ApiFailure(
          ApiFailureKind.redirect,
          requestId: requestId,
          statusCode: response.statusCode,
          message: 'The server returned an unexpected redirect.',
        );
      }
      if (response.statusCode == 401 &&
          authMode == AuthMode.bearer &&
          expireSessionOnUnauthorized &&
          _onUnauthorized != null) {
        try {
          await _onUnauthorized(capturedSessionEpoch);
        } catch (_) {
          // Preserve the sanitized HTTP outcome when session cleanup fails.
        }
      }
      final ok =
          response.statusCode >= 200 && response.statusCode < 300;
      if (!ok) {
        final decoded = jsonDecode(_utf8Body(response));
        if (decoded is! Map<Object?, Object?> ||
            decoded['error'] is! Map<Object?, Object?>) {
          throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
        }
        final error = decoded['error'] as Map<Object?, Object?>;
        if (error['code'] is! String || error['message'] is! String) {
          throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
        }
        throw ApiFailure(
          ApiFailureKind.http,
          requestId: requestId,
          statusCode: response.statusCode,
          backendCode: _safeBackendCode(error['code'] as String),
          message: _messageForHttpStatus(response.statusCode),
          retryAfter: _parseRetryAfter(response.headers['retry-after']),
        );
      }
      return response.bodyBytes;
    } on ApiFailure {
      rethrow;
    } on _RequestStopped {
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
    } on FormatException {
      throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
    } catch (_) {
      throw ApiFailure(ApiFailureKind.network, requestId: requestId);
    } finally {
      timer.cancel();
    }
  }

  /// Reads one Server-Sent Event stream. [onEvent] returning `false` stops
  /// reading without treating the request as cancelled. There is no automatic
  /// retry; a broken stream surfaces as [ApiFailureKind.network] or timeout.
  Future<void> sendSse({
    required String method,
    required String routeTemplate,
    required bool Function(SseEvent event) onEvent,
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, String?> queryParameters = const <String, String?>{},
    Object? body,
    AuthMode authMode = AuthMode.bearer,
    Duration timeout = const Duration(minutes: 10),
    RequestCancellation? cancellation,
    bool expireSessionOnUnauthorized = true,
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
      if (cancellation?.isCancelled ?? false) throw const _RequestStopped();
      final capturedSessionEpoch = _sessionEpoch();
      final Uri origin;
      try {
        origin = await _awaitOrAbort(_originProvider(), abortTrigger);
      } on _RequestStopped {
        rethrow;
      } catch (_) {
        throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
      }
      String? token;
      if (authMode == AuthMode.bearer) {
        try {
          token = await _awaitOrAbort(_tokenProvider(origin), abortTrigger);
        } on _RequestStopped {
          rethrow;
        } catch (_) {
          throw ApiFailure(ApiFailureKind.authentication, requestId: requestId);
        }
        if (token == null || token.trim().isEmpty) {
          throw ApiFailure(ApiFailureKind.authentication, requestId: requestId);
        }
      }
      if (cancellation?.isCancelled ?? false) throw const _RequestStopped();

      final request =
          http.AbortableRequest(
              method,
              _buildUri(origin, routeTemplate, pathParameters, queryParameters),
              abortTrigger: abortTrigger,
            )
            ..followRedirects = false
            ..headers['accept'] = 'text/event-stream, application/json';
      if (authMode == AuthMode.bearer) {
        request.headers['authorization'] = 'Bearer $token';
      }
      if (body != null) {
        request
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode(body);
      }

      final streamedResponse = await _awaitOrAbort(
        _client.send(request),
        abortTrigger,
      );
      if (streamedResponse.statusCode >= 300 &&
          streamedResponse.statusCode < 400) {
        throw ApiFailure(
          ApiFailureKind.redirect,
          requestId: requestId,
          statusCode: streamedResponse.statusCode,
          message: 'The server returned an unexpected redirect.',
        );
      }
      final contentType =
          streamedResponse.headers['content-type']?.toLowerCase() ?? '';
      final isSse = contentType.contains('text/event-stream');
      final ok =
          streamedResponse.statusCode >= 200 &&
          streamedResponse.statusCode < 300;
      if (streamedResponse.statusCode == 401 &&
          authMode == AuthMode.bearer &&
          expireSessionOnUnauthorized &&
          _onUnauthorized != null) {
        try {
          await _onUnauthorized(capturedSessionEpoch);
        } catch (_) {}
      }
      if (!ok || !isSse) {
        final response = await _awaitOrAbort(
          http.Response.fromStream(streamedResponse),
          abortTrigger,
        );
        if (!ok) {
          final decoded = jsonDecode(_utf8Body(response));
          if (decoded is! Map<Object?, Object?> ||
              decoded['error'] is! Map<Object?, Object?>) {
            throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
          }
          final error = decoded['error'] as Map<Object?, Object?>;
          if (error['code'] is! String || error['message'] is! String) {
            throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
          }
          throw ApiFailure(
            ApiFailureKind.http,
            requestId: requestId,
            statusCode: response.statusCode,
            backendCode: _safeBackendCode(error['code'] as String),
            message: _messageForHttpStatus(response.statusCode),
            retryAfter: _parseRetryAfter(response.headers['retry-after']),
          );
        }
        throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
      }

      final decoder = SseDecoder();
      await for (final chunk in streamedResponse.stream.transform(
        utf8.decoder,
      )) {
        if (cancellation?.isCancelled ?? false) throw const _RequestStopped();
        if (timedOut) throw const _RequestStopped();
        for (final event in decoder.add(chunk)) {
          if (!onEvent(event)) return;
        }
      }
      for (final event in decoder.flush()) {
        if (!onEvent(event)) return;
      }
    } on ApiFailure {
      rethrow;
    } on _RequestStopped {
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
    } on FormatException {
      throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
    } catch (_) {
      throw ApiFailure(ApiFailureKind.network, requestId: requestId);
    } finally {
      timer.cancel();
    }
  }

  Uri _buildUri(
    Uri origin,
    String routeTemplate,
    Map<String, String> pathParameters,
    Map<String, String?> queryParameters,
  ) {
    if (origin.scheme.isEmpty ||
        origin.host.isEmpty ||
        origin.path.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        !routeTemplate.startsWith('/') ||
        routeTemplate.startsWith('//') ||
        routeTemplate.contains('?') ||
        routeTemplate.contains('#')) {
      throw const FormatException();
    }
    var path = routeTemplate;
    for (final entry in pathParameters.entries) {
      path = path.replaceAll(
        '{${entry.key}}',
        Uri.encodeComponent(entry.value),
      );
    }
    if (path.contains('{') || path.contains('}')) {
      throw const FormatException();
    }
    final query = <String, String>{
      for (final entry in queryParameters.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return Uri.parse('${origin.toString()}$path$suffix');
  }

  static String _utf8Body(http.Response response) {
    if (response.bodyBytes.isEmpty) return '';
    return utf8.decode(response.bodyBytes);
  }

  static int _zeroEpoch() => 0;

  static Future<T> _awaitOrAbort<T>(
    Future<T> pending,
    Future<void> abortTrigger,
  ) {
    return Future.any<T>(<Future<T>>[pending, _abortAs<T>(abortTrigger)]);
  }

  static Future<T> _abortAs<T>(Future<void> abortTrigger) async {
    await abortTrigger;
    throw const _RequestStopped();
  }

  String _newRequestId() {
    final generator = _requestIdGenerator;
    if (generator != null) return generator();
    _requestSequence += 1;
    return 'local-${_clock().microsecondsSinceEpoch.toRadixString(36)}-${_requestSequence.toRadixString(36)}';
  }

  static String? _safeBackendCode(String value) =>
      BackendErrorCodes.allow(value);

  static String _messageForHttpStatus(int statusCode) {
    return switch (statusCode) {
      401 => 'Authentication failed.',
      403 => 'The request was not permitted.',
      404 => 'The requested resource was not found.',
      409 => 'The request conflicted with the current state.',
      429 => 'The service is busy. Try again later.',
      >= 500 => 'The service is temporarily unavailable.',
      _ => 'The server rejected the request.',
    };
  }

  Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return seconds < 0 ? null : Duration(seconds: seconds);
    try {
      final delay = HttpDate.parse(value).toUtc().difference(_clock().toUtc());
      return delay.isNegative ? null : delay;
    } catch (_) {
      return null;
    }
  }
}

final class _RequestStopped implements Exception {
  const _RequestStopped();
}
