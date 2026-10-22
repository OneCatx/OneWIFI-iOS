final class LpaActivation {
  const LpaActivation({
    required this.smdp,
    required this.matchingId,
    required this.confirmationCode,
  });

  final String smdp;
  final String matchingId;
  final String confirmationCode;

  bool get hasSmdp => smdp.isNotEmpty;
}

/// GSMA SGP.22 activation: `[LPA:]1$<SM-DP+>$<MatchingID>[$<CC>]`.
/// Operators often omit the `LPA:` prefix.
LpaActivation parseLpaActivationCode(String raw) {
  final text = raw.trim().replaceAll(RegExp(r'[\s\u200b]+'), '');
  if (text.isEmpty) {
    return const LpaActivation(smdp: '', matchingId: '', confirmationCode: '');
  }
  final withoutScheme = text.replaceFirst(
    RegExp(r'^LPA:', caseSensitive: false),
    '',
  );
  final parts = withoutScheme.split(r'$');
  if (parts.isNotEmpty && parts[0] == '1' && parts.length >= 2) {
    return LpaActivation(
      smdp: _smdpHost(parts[1]),
      matchingId: parts.length > 2 ? parts[2].trim() : '',
      confirmationCode: parts.length > 3 ? parts[3].trim() : '',
    );
  }
  return LpaActivation(
    smdp: _smdpHost(parts.isEmpty ? '' : parts[0]),
    matchingId: parts.length > 1 ? parts[1].trim() : '',
    confirmationCode: parts.length > 2 ? parts[2].trim() : '',
  );
}

String _smdpHost(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  if (RegExp(r'^https?:\/\/', caseSensitive: false).hasMatch(text)) {
    return Uri.tryParse(text)?.host ?? '';
  }
  return text.split('/').first.trim();
}
