import 'dart:convert';

import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/certificate.dart';
import 'certificate_api.dart';
import 'certificate_dto.dart';

/// Repository for certificate management.
abstract interface class CertificateRepository {
  Future<List<Certificate>> getCertificates({
    RequestCancellation? cancellation,
  });

  Future<String> downloadCertificatePem({
    RequestCancellation? cancellation,
  });

  Future<Certificate> uploadCertificate({
    required String certificatePem,
    required String privateKeyPem,
    RequestCancellation? cancellation,
  });

  Future<void> deleteCertificate(
    String certificateId, {
    RequestCancellation? cancellation,
  });
}

final class DefaultCertificateRepository implements CertificateRepository {
  const DefaultCertificateRepository(this._api);

  final CertificateApi _api;

  @override
  Future<List<Certificate>> getCertificates({
    RequestCancellation? cancellation,
  }) {
    return guardShape('local-certificate-response', () async {
      final state = await _api.getHttpsState(cancellation: cancellation);
      final cert = state.toCertificate();
      return cert != null ? <Certificate>[cert] : const <Certificate>[];
    });
  }

  @override
  Future<String> downloadCertificatePem({
    RequestCancellation? cancellation,
  }) async {
    try {
      final bytes = await _api.downloadCertificate(cancellation: cancellation);
      final pem = utf8.decode(bytes).trim();
      if (pem.isEmpty) {
        throw const CertificateRepositoryException(
          'Failed to download certificate: empty PEM body',
        );
      }
      return pem;
    } on CertificateRepositoryException {
      rethrow;
    } catch (e) {
      throw CertificateRepositoryException(
        'Failed to download certificate: $e',
      );
    }
  }

  @override
  Future<Certificate> uploadCertificate({
    required String certificatePem,
    required String privateKeyPem,
    RequestCancellation? cancellation,
  }) {
    return guardShape('local-certificate-response', () async {
      _validatePemFormat(certificatePem, 'certificate');
      _validatePemFormat(privateKeyPem, 'private key');

      final state = await _api.uploadCertificate(
        UploadCertificateDto(
          certificate: certificatePem,
          privateKey: privateKeyPem,
        ),
        cancellation: cancellation,
      );
      final cert = state.toCertificate();
      if (cert == null) {
        throw const CertificateRepositoryException(
          'Failed to parse uploaded certificate',
        );
      }
      return cert;
    });
  }

  @override
  Future<void> deleteCertificate(
    String certificateId, {
    RequestCancellation? cancellation,
  }) {
    return guardShape('local-certificate-response', () async {
      await _api.deleteCertificate(cancellation: cancellation);
    });
  }

  void _validatePemFormat(String pem, String type) {
    final trimmed = pem.trim();
    if (!trimmed.startsWith('-----BEGIN') || !trimmed.contains('-----END')) {
      throw CertificateRepositoryException(
        'Invalid $type format: must be in PEM format',
      );
    }
  }
}

/// Exception thrown by certificate repository operations.
final class CertificateRepositoryException implements Exception {
  const CertificateRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
