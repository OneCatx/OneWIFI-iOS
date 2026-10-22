/// Certificate domain model representing an HTTPS certificate.
class Certificate {
  final String id;
  final String commonName;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;
  final String fingerprint;
  final CertificateSource source;
  final List<String> subjectAlternativeNames;
  final bool coversHost;

  const Certificate({
    required this.id,
    required this.commonName,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.fingerprint,
    required this.source,
    required this.subjectAlternativeNames,
    required this.coversHost,
  });

  /// Returns true if the certificate expires within 30 days.
  bool get isExpiringSoon {
    final now = DateTime.now();
    final daysUntilExpiry = validTo.difference(now).inDays;
    return daysUntilExpiry <= 30 && daysUntilExpiry > 0;
  }

  /// Returns true if the certificate has already expired.
  bool get isExpired {
    return DateTime.now().isAfter(validTo);
  }

  /// Returns the number of days until expiry (negative if expired).
  int get daysUntilExpiry {
    return validTo.difference(DateTime.now()).inDays;
  }

  Certificate copyWith({
    String? id,
    String? commonName,
    String? issuer,
    DateTime? validFrom,
    DateTime? validTo,
    String? fingerprint,
    CertificateSource? source,
    List<String>? subjectAlternativeNames,
    bool? coversHost,
  }) {
    return Certificate(
      id: id ?? this.id,
      commonName: commonName ?? this.commonName,
      issuer: issuer ?? this.issuer,
      validFrom: validFrom ?? this.validFrom,
      validTo: validTo ?? this.validTo,
      fingerprint: fingerprint ?? this.fingerprint,
      source: source ?? this.source,
      subjectAlternativeNames:
          subjectAlternativeNames ?? this.subjectAlternativeNames,
      coversHost: coversHost ?? this.coversHost,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Certificate && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Certificate(id: $id, cn: $commonName, expires: $validTo)';
  }
}

/// Source of the certificate.
enum CertificateSource {
  selfSigned,
  custom;

  String get displayName {
    switch (this) {
      case CertificateSource.selfSigned:
        return 'Self-Signed';
      case CertificateSource.custom:
        return 'Custom';
    }
  }
}
