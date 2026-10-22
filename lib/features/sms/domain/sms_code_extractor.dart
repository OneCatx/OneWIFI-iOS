/// 从短信正文抽验证码。规则对齐 OneTools `SmsCodeExtractor`：先要有验证码类
/// 关键词，再在 4–8 位候选里挑离关键词最近的那个；没有关键词宁可漏、不可误抽。
abstract final class SmsCodeExtractor {
  static const int _maxGap = 50;

  static const List<String> _cnKeywords = <String>[
    '验证码',
    '校验码',
    '检验码',
    '确认码',
    '激活码',
    '动态码',
    '动态密码',
    '短信密码',
    '随机码',
    '授权码',
    '登录码',
    '取件码',
  ];

  static final List<RegExp> _enKeywords = <RegExp>[
    for (final word in <String>[
      'verification code',
      'verify code',
      'security code',
      'one-time',
      'otp',
      'code',
      'pin',
    ])
      RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false),
  ];

  static final RegExp _tokenPattern = RegExp(
    r'(?<![A-Za-z0-9])[A-Za-z0-9]{4,8}(?![A-Za-z0-9])',
  );

  static final RegExp _bracketPattern = RegExp(r'【[^】]*】');

  static String? extract(String body) {
    if (body.trim().isEmpty) return null;

    final keywordSpans = _keywordSpans(body);
    if (keywordSpans.isEmpty) return null;

    final brackets = _bracketPattern.allMatches(body).toList(growable: false);

    Match? best;
    var bestGap = 1 << 30;
    var bestAfter = false;
    for (final match in _tokenPattern.allMatches(body)) {
      if (!_isCandidate(body, match)) continue;
      if (brackets.any(
        (span) => match.start >= span.start && match.start < span.end,
      )) {
        continue;
      }

      for (final span in keywordSpans) {
        final int gap;
        final bool after;
        if (match.start >= span.end) {
          gap = match.start - span.end;
          after = true;
        } else if (span.start >= match.end) {
          gap = span.start - match.end;
          after = false;
        } else {
          gap = 0;
          after = true;
        }
        if (gap > _maxGap) continue;
        if (gap < bestGap || (gap == bestGap && after && !bestAfter)) {
          best = match;
          bestGap = gap;
          bestAfter = after;
        }
      }
    }
    return best?.group(0);
  }

  static List<({int start, int end})> _keywordSpans(String body) {
    final spans = <({int start, int end})>[];
    for (final keyword in _cnKeywords) {
      var from = 0;
      while (true) {
        final at = body.indexOf(keyword, from);
        if (at < 0) break;
        spans.add((start: at, end: at + keyword.length));
        from = at + keyword.length;
      }
    }
    for (final regex in _enKeywords) {
      for (final match in regex.allMatches(body)) {
        spans.add((start: match.start, end: match.end));
      }
    }
    return spans;
  }

  static bool _isCandidate(String body, Match match) {
    final value = match.group(0)!;
    final hasDigit = value.runes.any(_isAsciiDigit);
    if (!hasDigit) return false;
    final allDigits = value.runes.every(_isAsciiDigit);
    final hasLetter = value.runes.any(_isAsciiLetter);
    if (!allDigits && !hasLetter) return false;

    const separators = <int>[0x2D, 0x2F, 0x3A, 0x2E]; // - / : .
    final before = match.start - 1;
    if (before >= 0 && separators.contains(body.codeUnitAt(before))) {
      final beyond = before - 1;
      if (beyond >= 0 && _isAsciiDigit(body.codeUnitAt(beyond))) return false;
    }
    final after = match.end;
    if (after < body.length && separators.contains(body.codeUnitAt(after))) {
      final beyond = after + 1;
      if (beyond < body.length && _isAsciiDigit(body.codeUnitAt(beyond))) {
        return false;
      }
    }
    return true;
  }

  static bool _isAsciiDigit(int code) => code >= 0x30 && code <= 0x39;

  static bool _isAsciiLetter(int code) =>
      (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
}
