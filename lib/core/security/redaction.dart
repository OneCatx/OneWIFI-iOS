abstract final class Redaction {
  static final RegExp _uriPattern = RegExp(
    r'\b(?:https?|wss?)://[^\s<>]+',
    caseSensitive: false,
  );
  static final RegExp _bearerPattern = RegExp(
    r'\bBearer\s+\S+',
    caseSensitive: false,
  );
  static final RegExp _namedCredentialPattern = RegExp(
    r'''(^|[^A-Za-z0-9_-])(?:"|')?(password|passwd|passcode|pwd|access[_-]?token|refresh[_-]?token|session[_-]?token|id[_-]?token|api[_-]?key|client[_-]?secret|csrf[_-]?token|secret|token)(?:"|')?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;&}\]]+)''',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _sensitiveDigitsPattern = RegExp(r'\d{7,}');

  static String maskTail4(String value) {
    if (value.isEmpty) {
      return '••••';
    }

    final tailStart = value.length > 4 ? value.length - 4 : 0;
    return '•••• ${value.substring(tailStart)}';
  }

  static String redactResponseBody(Object? _) => '<redacted-body>';

  static String sanitizeText(String value) {
    final withoutUris = value.replaceAll(_uriPattern, '<redacted-uri>');
    final withoutBearer = withoutUris.replaceAllMapped(
      _bearerPattern,
      (_) => 'Bearer <redacted>',
    );
    final withoutNamedCredentials = withoutBearer.replaceAllMapped(
      _namedCredentialPattern,
      (match) => '${match.group(1)}${match.group(2)}=<redacted>',
    );
    return withoutNamedCredentials.replaceAllMapped(
      _sensitiveDigitsPattern,
      (match) => maskTail4(match.group(0)!),
    );
  }
}
