/// Thin MDD gateway client for mobile (auth + calls).
/// Existing app screens can switch to this without rewriting business UI.
library;
import 'dart:convert';
import 'dart:io';

import 'gateway_api.dart';

class GatewayClient {
  GatewayClient({
    required this.origin,
    HttpClient? httpClient,
  }) : _http = httpClient ?? HttpClient() {
    _http.badCertificateCallback = (cert, host, port) => true; // local gateway
    _http.connectionTimeout = const Duration(seconds: 12);
  }

  final String origin; // e.g. https://192.168.2.2:6699
  final HttpClient _http;
  String? _csrf;
  String? sessionToken;

  Uri _uri(String path) => Uri.parse(origin + path);

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final req = await _http.openUrl(method, _uri(path));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      req.headers.contentType = ContentType.json;
    }
    final bearer = sessionToken?.trim();
    final hasBearer = bearer != null && bearer.isNotEmpty;
    // WEB `requireWriteCSRF`: Bearer-only clients skip CSRF; cookie sessions need it.
    if (method != 'GET' && method != 'HEAD' && !hasBearer && _csrf != null) {
      req.headers.set(GatewayHeaders.csrf, _csrf!);
    }
    if (hasBearer) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    if (body != null) {
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final raw = await res.transform(utf8.decoder).join();
    final map = raw.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(raw) as Map).cast<String, dynamic>();
    if (res.statusCode >= 400) {
      final detail = map['detail'] ?? map['error'] ?? raw;
      throw HttpException('HTTP ${res.statusCode}: $detail', uri: _uri(path));
    }
    return map;
  }

  Future<void> login(String username, String password) async {
    final data = await request(
      GatewayApi.login,
      method: 'POST',
      body: {'username': username, 'password': password},
    );
    final payload = (data['data'] as Map?) ?? data;
    _csrf = (payload['csrf'] ?? payload['csrf_token']) as String?;
    sessionToken = payload['session_token'] as String?;
  }

  Future<List<dynamic>> fetchLines() async {
    final data = await request(GatewayApi.instances());
    return (data['instances'] as List?) ?? const [];
  }

  Future<Map<String, dynamic>> fetchLineStatus(String id) async {
    final data = await request(GatewayApi.status(id));
    return (data['data'] as Map?)?.cast<String, dynamic>() ?? data;
  }

  Future<Map<String, dynamic>> fetchSoftphone(String id) async {
    final data = await request(GatewayApi.softphone(id));
    return (data['data'] as Map?)?.cast<String, dynamic>() ?? data;
  }

  Future<Map<String, dynamic>> dial(String id, String number) async {
    final data = await request(
      GatewayApi.dial(id),
      method: 'POST',
      body: {'number': number},
    );
    return (data['data'] as Map?)?.cast<String, dynamic>() ?? data;
  }

  Future<Map<String, dynamic>> hangup(String id) async {
    final data = await request(
      GatewayApi.hangup(id),
      method: 'POST',
      body: const {},
    );
    return (data['data'] as Map?)?.cast<String, dynamic>() ?? data;
  }

  Uri softphoneWebsocket(String id) {
    final base = Uri.parse(origin);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: GatewayApi.softphoneWs(id),
    );
  }

  void close() => _http.close(force: true);
}
