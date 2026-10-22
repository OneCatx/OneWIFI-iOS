import '../../../core/http/json_shape.dart';
import '../domain/certificate.dart';

/// DTO shape failure for certificate JSON parsing.
final class CertificateDtoException implements DtoShapeException {
  const CertificateDtoException();
}

const _shape = JsonShape(CertificateDtoException.new);

/// Data Transfer Object for HTTPS settings state from the backend.
final class HttpsStateDto {
  const HttpsStateDto({
    required this.enabled,
    required this.httpUrl,
    required this.httpsUrl,
    this.fingerprint,
    this.notAfter,
    this.source,
    this.names,
    required this.coversHost,
    this.host,
  });

  final bool enabled;
  final String httpUrl;
  final String httpsUrl;
  final String? fingerprint;
  final DateTime? notAfter;
  final String? source;
  final List<String>? names;
  final bool coversHost;
  final String? host;

  factory HttpsStateDto.fromJson(Object? value) {
    final map = _shape.map(value);
    final fingerprint = _optionalNonEmpty(map['fingerprint']);
    final source = _optionalNonEmpty(map['source']);
    final host = _optionalNonEmpty(map['host']);
    return HttpsStateDto(
      enabled: map['enabled'] == true,
      httpUrl: _shape.optionalString(map['http_url']),
      httpsUrl: _shape.optionalString(map['https_url']),
      fingerprint: fingerprint,
      notAfter: _parseDateTime(map['not_after']),
      source: source,
      names: _stringList(map['names']),
      coversHost: map['covers_host'] == true,
      host: host,
    );
  }

  /// Converts DTO to domain Certificate model.
  /// Returns null if certificate data is incomplete.
  Certificate? toCertificate() {
    final fingerprint = this.fingerprint;
    final notAfter = this.notAfter;
    final source = this.source;
    if (fingerprint == null || notAfter == null || source == null) {
      return null;
    }

    final certSource = source == 'custom'
        ? CertificateSource.custom
        : CertificateSource.selfSigned;

    final names = this.names;
    final cn = (names != null && names.isNotEmpty)
        ? names.first
        : (host ?? 'Unknown');

    return Certificate(
      id: fingerprint,
      commonName: cn,
      issuer: certSource == CertificateSource.selfSigned
          ? 'OneWIFI Self-Signed'
          : 'Custom CA',
      validFrom: notAfter.subtract(const Duration(days: 365 * 5)),
      validTo: notAfter,
      fingerprint: fingerprint,
      source: certSource,
      subjectAlternativeNames: names ?? const <String>[],
      coversHost: coversHost,
    );
  }
}

/// DTO for uploading a custom certificate.
final class UploadCertificateDto {
  const UploadCertificateDto({
    required this.certificate,
    required this.privateKey,
  });

  final String certificate;
  final String privateKey;

  Map<String, String> toJson() => <String, String>{
        'certificate': certificate,
        'private_key': privateKey,
      };
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) return null;
  final raw = _shape.optionalString(value);
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

String? _optionalNonEmpty(Object? value) {
  if (value == null) return null;
  final raw = _shape.string(value).trim();
  return raw.isEmpty ? null : raw;
}

List<String>? _stringList(Object? value) {
  if (value == null) return null;
  final list = _shape.list(value);
  final cleaned = <String>[
    for (final item in list)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
  return cleaned;
}
