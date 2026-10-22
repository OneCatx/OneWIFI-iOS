import 'dart:convert';

import '../../../core/config/gateway_api.dart';

final class RemoteOtpEndpoint {
  const RemoteOtpEndpoint({required this.baseUrl, required this.token});

  final Uri baseUrl;
  final String token;

  Uri get streamUrl => _join(GatewayApi.onetoolsSmsStream);

  Uri get pushEndpointUrl => _join(GatewayApi.onetoolsIosPushEndpoint);

  Uri get pushAckUrl => _join(GatewayApi.onetoolsIosPushEndpointAck);

  Uri _join(String apiPath) => baseUrl.replace(
    path: '${baseUrl.path.replaceFirst(RegExp(r'/$'), '')}$apiPath',
    query: null,
    fragment: null,
  );
}

final class RemoteOtpPairing {
  static RemoteOtpEndpoint parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) throw const FormatException('配对码为空。');
    if (text.startsWith('{')) return _fromJson(text);
    final uri = Uri.tryParse(text);
    if (uri == null) throw const FormatException('配对码无法解析。');
    if (uri.scheme.toLowerCase() == 'onetools') return _fromAppUri(uri);
    if (_isHttp(uri)) {
      return _endpoint(
        uri.replace(query: null, fragment: null),
        _token(uri.queryParameters),
      );
    }
    throw const FormatException('不支持的配对码。');
  }

  static Uri normalizeBaseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !_isHttp(uri) || !uri.hasAuthority || uri.host.isEmpty) {
      throw const FormatException('地址必须是 http:// 或 https://。');
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('地址不能包含凭据、查询参数或片段。');
    }
    return uri.replace(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      path: uri.path.replaceFirst(RegExp(r'/$'), ''),
    );
  }

  static RemoteOtpEndpoint _fromJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('配对码 JSON 格式错误。');
    return _endpoint(
      normalizeBaseUrl(_value(decoded, const ['u', 'url', 'baseUrl', 'base'])),
      _value(decoded, const ['t', 'token']),
    );
  }

  static RemoteOtpEndpoint _fromAppUri(Uri uri) {
    if (uri.host.toLowerCase() != 'onewifi') {
      throw const FormatException('不是 OneWifi 配对链接。');
    }
    return _endpoint(
      normalizeBaseUrl(_value(uri.queryParameters, const ['u', 'url', 'base'])),
      _token(uri.queryParameters),
    );
  }

  static RemoteOtpEndpoint _endpoint(Uri baseUrl, String token) {
    if (token.trim().isEmpty) throw const FormatException('配对码缺少令牌。');
    return RemoteOtpEndpoint(baseUrl: baseUrl, token: token.trim());
  }

  static String _token(Map<Object?, Object?> values) =>
      _value(values, const ['t', 'token']);

  static String _value(Map<Object?, Object?> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static bool _isHttp(Uri uri) =>
      uri.scheme.toLowerCase() == 'http' || uri.scheme.toLowerCase() == 'https';
}