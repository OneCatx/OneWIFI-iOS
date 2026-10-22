import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/base_url_policy.dart';

abstract interface class GatewayTrustStore {
  Future<String?> readFingerprint(Uri origin);
  Future<void> writeFingerprint(Uri origin, String fingerprint);
  Future<void> clearFingerprint(Uri origin);
}

String normalizeCertificateFingerprint(String value) {
  final normalized = value.replaceAll(RegExp(r'[:\s]'), '').toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
    throw const FormatException('请输入完整的 SHA-256 证书指纹（64 位十六进制）。');
  }
  return normalized;
}

final class SecureGatewayTrustStore implements GatewayTrustStore {
  SecureGatewayTrustStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  String _key(Uri origin) {
    final normalized = BaseUrlPolicy.parseAndValidate(origin.toString());
    if (normalized.scheme != 'https') {
      throw const FormatException('证书指纹仅用于 HTTPS。');
    }
    return 'tls_leaf_sha256.v1.${base64Url.encode(utf8.encode(normalized.toString()))}';
  }

  @override
  Future<String?> readFingerprint(Uri origin) async {
    final value = await _storage.read(key: _key(origin));
    return value == null ? null : normalizeCertificateFingerprint(value);
  }

  @override
  Future<void> writeFingerprint(Uri origin, String fingerprint) =>
      _storage.write(
        key: _key(origin),
        value: normalizeCertificateFingerprint(fingerprint),
      );
  @override
  Future<void> clearFingerprint(Uri origin) =>
      _storage.delete(key: _key(origin));
}
