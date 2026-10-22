/// 授权码本地格式校验：镜像原生 `CodeValidator`。
/// 权威校验仍在原生 `ActivationManager.activate`。
abstract final class LicenseCode {
  static final RegExp _base = RegExp(r'^[A-Z0-9]{16}$');
  static final RegExp _edition = RegExp(r'^(PRO|ULTRA)$');

  /// 带连字符可输入的最长形态：`XXXX-XXXX-XXXX-XXXX-ULTRA`。
  static const int maxInputLength = 25;

  static String? normalize(String raw) {
    final compact = raw
        .trim()
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .toUpperCase();
    final String? edition;
    if (compact.length == 16) {
      edition = null;
    } else if (compact.length > 16) {
      final suffix = compact.substring(16);
      if (!_edition.hasMatch(suffix)) return null;
      edition = suffix;
    } else {
      return null;
    }
    final base = compact.substring(0, 16);
    if (!_base.hasMatch(base)) return null;
    final groups = <String>[
      for (var i = 0; i < 16; i += 4) base.substring(i, i + 4),
    ];
    final normalizedBase = groups.join('-');
    return edition == null ? normalizedBase : '$normalizedBase-$edition';
  }

  static CodeValidation validate(String raw) {
    if (raw.trim().isEmpty) {
      return const CodeValidation(ok: false, error: CodeError.empty);
    }
    final normalized = normalize(raw);
    if (normalized == null) {
      return const CodeValidation(ok: false, error: CodeError.format);
    }
    return CodeValidation(ok: true, normalized: normalized);
  }

  static String? localError(String raw) {
    if (raw.trim().isEmpty) return null;
    return validate(raw).ok ? null : '格式应为 XXXX-XXXX-XXXX-XXXX';
  }
}

enum CodeError { none, empty, format }

final class CodeValidation {
  const CodeValidation({
    required this.ok,
    this.normalized = '',
    this.error = CodeError.none,
  });

  final bool ok;
  final String normalized;
  final CodeError error;
}
