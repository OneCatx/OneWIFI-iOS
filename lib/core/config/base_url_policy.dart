final class BaseUrlPolicy {
  static final Uri defaultOrigin = Uri.parse('http://192.168.1.88:6699');
  static const String backendDefaultListen = '0.0.0.0:6688';

  static Uri parseAndValidate(String input) {
    final candidate = input.trim();
    if (candidate.isEmpty) {
      throw const FormatException('服务地址不能为空。');
    }

    final Uri parsed;
    try {
      parsed = Uri.parse(candidate);
    } on FormatException {
      throw const FormatException('服务地址无效。');
    }

    final scheme = parsed.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty) {
      throw const FormatException('服务地址必须是 http:// 或 https://。');
    }
    if (parsed.userInfo.isNotEmpty) {
      throw const FormatException('服务地址不能包含用户名或密码。');
    }
    if (parsed.path.isNotEmpty && parsed.path != '/') {
      throw const FormatException('服务地址不能包含路径。');
    }
    if (parsed.hasQuery || parsed.hasFragment) {
      throw const FormatException('服务地址不能包含查询参数或片段。');
    }

    final defaultPort = scheme == 'https' ? 443 : 80;
    return Uri(
      scheme: scheme,
      host: parsed.host.toLowerCase(),
      port: parsed.hasPort && parsed.port != defaultPort ? parsed.port : null,
    );
  }

  static bool _isLoopbackOrPrivateIpLiteral(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' || normalized.endsWith('.localhost')) {
      return true;
    }
    final ipv4 = _parseIpv4(host);
    if (ipv4 != null) {
      final first = ipv4[0];
      final second = ipv4[1];
      return first == 127 ||
          first == 10 ||
          (first == 172 && second >= 16 && second <= 31) ||
          (first == 192 && second == 168) ||
          (first == 169 && second == 254);
    }

    if (!normalized.contains(':')) return false;
    if (normalized == '::1') return true;
    if (normalized.startsWith('fc') || normalized.startsWith('fd')) {
      return true;
    }
    return _isIpv6LinkLocal(normalized);
  }

  static bool _isIpv6LinkLocal(String host) {
    final first = host.split(':').first;
    final nibble = int.tryParse(first.padRight(4, '0'), radix: 16);
    return nibble != null && nibble >= 0xfe80 && nibble <= 0xfebf;
  }

  static List<int>? _parseIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) {
      return null;
    }

    final octets = <int>[];
    for (final part in parts) {
      if (part.isEmpty || !RegExp(r'^\d{1,3}$').hasMatch(part)) {
        return null;
      }
      final octet = int.parse(part);
      if (octet > 255) {
        return null;
      }
      octets.add(octet);
    }
    return octets;
  }

  static Uri fromHostAndPort({
    required String host,
    required String port,
    bool https = false,
  }) {
    final trimmedHost = host.trim();
    final trimmedPort = port.trim();
    if (trimmedHost.isEmpty) {
      throw const FormatException('主机不能为空。');
    }
    if (trimmedPort.isEmpty) {
      throw const FormatException('端口不能为空。');
    }
    final parsedPort = int.tryParse(trimmedPort);
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      throw const FormatException('端口范围 1–65535。');
    }
    final scheme = https ? 'https' : 'http';
    final hostForUri = trimmedHost.contains(':') && !trimmedHost.startsWith('[')
        ? '[$trimmedHost]'
        : trimmedHost;
    return parseAndValidate('$scheme://$hostForUri:$parsedPort');
  }

  static ({String host, String port, bool https}) split(Uri origin) {
    final https = origin.scheme.toLowerCase() == 'https';
    final port = origin.hasPort ? origin.port : (https ? 443 : 80);
    return (host: origin.host, port: '$port', https: https);
  }

  static bool isPublicCleartext(Uri origin) {
    return origin.scheme.toLowerCase() == 'http' &&
        !_isLoopbackOrPrivateIpLiteral(origin.host);
  }
}
