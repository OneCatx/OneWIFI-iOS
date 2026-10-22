import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/certificates/data/certificate_api.dart';
import 'package:onewifi_android/features/certificates/data/certificate_repository.dart';
import 'package:onewifi_android/features/certificates/domain/certificate.dart';

import '../../../support/fakes.dart';

void main() {
  group('CertificateRepository', () {
    test('getCertificates returns list of certificates', () async {
      final repository = DefaultCertificateRepository(
        CertificateApi(
          _transport(
            FakeClient((_) async => _success(<String, Object?>{
                  'enabled': true,
                  'fingerprint': 'AA:BB:CC',
                  'not_after': '2027-01-01T00:00:00.000Z',
                  'source': 'custom',
                  'names': <String>['localhost', '127.0.0.1'],
                  'covers_host': true,
                  'http_url': 'http://localhost',
                  'https_url': 'https://localhost',
                  'host': 'localhost',
                })),
          ),
        ),
      );

      final certificates = await repository.getCertificates();

      expect(certificates, hasLength(1));
      final cert = certificates.first;
      expect(cert.fingerprint, 'AA:BB:CC');
      expect(cert.commonName, 'localhost');
      expect(cert.subjectAlternativeNames, ['localhost', '127.0.0.1']);
      expect(cert.source, CertificateSource.custom);
    });

    test('getCertificates returns empty list when certificate incomplete', () async {
      final repository = DefaultCertificateRepository(
        CertificateApi(
          _transport(
            FakeClient((_) async => _success(<String, Object?>{
                  'enabled': false,
                  'http_url': 'http://localhost',
                  'https_url': 'https://localhost',
                  'covers_host': false,
                })),
          ),
        ),
      );

      final certificates = await repository.getCertificates();
      expect(certificates, isEmpty);
    });

    test('uploadCertificate validates PEM format', () async {
      final repository = DefaultCertificateRepository(
        CertificateApi(
          _transport(FakeClient((_) async => _success(<String, Object?>{}))),
        ),
      );

      expect(
        () => repository.uploadCertificate(
          certificatePem: 'invalid',
          privateKeyPem:
              '-----BEGIN PRIVATE KEY-----\nx\n-----END PRIVATE KEY-----',
        ),
        throwsA(isA<CertificateRepositoryException>()),
      );
    });

    test('uploadCertificate returns domain certificate', () async {
      final repository = DefaultCertificateRepository(
        CertificateApi(
          _transport(
            FakeClient((_) async => _success(<String, Object?>{
                  'enabled': true,
                  'fingerprint': 'NEW:FP',
                  'not_after': '2027-01-01T00:00:00.000Z',
                  'source': 'custom',
                  'names': <String>['localhost'],
                  'covers_host': true,
                  'http_url': 'http://localhost',
                  'https_url': 'https://localhost',
                  'host': 'localhost',
                })),
          ),
        ),
      );

      final cert = await repository.uploadCertificate(
        certificatePem:
            '-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----',
        privateKeyPem:
            '-----BEGIN PRIVATE KEY-----\nxyz\n-----END PRIVATE KEY-----',
      );

      expect(cert.fingerprint, 'NEW:FP');
      expect(cert.source, CertificateSource.custom);
    });

    test('deleteCertificate calls api', () async {
      var deleted = false;
      final repository = DefaultCertificateRepository(
        CertificateApi(
          _transport(
            FakeClient((request) async {
              if (request.method == 'DELETE') deleted = true;
              return _success(<String, Object?>{
                'enabled': true,
                'fingerprint': 'SELF:SIGNED',
                'not_after': '2027-01-01T00:00:00.000Z',
                'source': 'self_signed',
                'names': <String>['localhost'],
                'covers_host': true,
                'http_url': 'http://localhost',
                'https_url': 'https://localhost',
                'host': 'localhost',
              });
            }),
          ),
        ),
      );

      await repository.deleteCertificate('AA:BB:CC');
      expect(deleted, isTrue);
    });

    test('downloadCertificatePem returns UTF-8 PEM text', () async {
      const pem =
          '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----';
      final repository = DefaultCertificateRepository(
        CertificateApi(
          _transport(
            FakeClient((request) async {
              expect(request.url.path, '/api/settings/https/certificate');
              return http.StreamedResponse(
                Stream<List<int>>.value(utf8.encode('$pem\n')),
                200,
                headers: const <String, String>{
                  'content-type': 'application/x-pem-file',
                },
              );
            }),
          ),
        ),
      );

      final text = await repository.downloadCertificatePem();
      expect(text, pem);
    });

    test('downloadCertificatePem wraps API failures', () async {
      final repository = DefaultCertificateRepository(
        CertificateApi(
          _transport(
            FakeClient((_) async {
              return http.StreamedResponse(
                Stream<List<int>>.value(
                  utf8.encode(
                    jsonEncode(<String, Object?>{
                      'error': <String, Object?>{
                        'code': 'https_unavailable',
                        'message': 'down',
                      },
                    }),
                  ),
                ),
                503,
              );
            }),
          ),
        ),
      );

      expect(
        () => repository.downloadCertificatePem(),
        throwsA(isA<CertificateRepositoryException>()),
      );
    });
  });
}

HttpTransport _transport(http.BaseClient client) => HttpTransport(
      client: client,
      originProvider: () async => Uri.parse('https://api.example.test'),
      tokenProvider: (_) async => 'test-token',
      requestIdGenerator: () => 'certificate-repo-test',
    );

http.StreamedResponse _success(Object? data) => http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(jsonEncode(<String, Object?>{'data': data})),
      ),
      200,
    );
