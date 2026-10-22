import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/certificates/data/certificate_api.dart';
import 'package:onewifi_android/features/certificates/data/certificate_dto.dart';

import '../../../support/fakes.dart';

void main() {
  group('CertificateApi', () {
    test('getHttpsState returns state when successful', () async {
      final api = CertificateApi(
        _transport(
          FakeClient((request) async {
            expect(request.url.path, '/api/settings/https');
            expect(request.headers['authorization'], 'Bearer test-token');
            return _success(<String, Object?>{
              'enabled': true,
              'http_url': 'http://localhost:7575',
              'https_url': 'https://localhost:7575',
              'fingerprint': 'AA:BB:CC',
              'not_after': '2027-01-01T00:00:00.000Z',
              'source': 'custom',
              'names': <String>['localhost'],
              'covers_host': true,
              'host': 'localhost',
            });
          }),
        ),
      );

      final state = await api.getHttpsState();

      expect(state.enabled, true);
      expect(state.fingerprint, 'AA:BB:CC');
      expect(state.source, 'custom');
      expect(state.coversHost, true);
    });

    test('getHttpsState propagates unauthorized failures', () async {
      final api = CertificateApi(
        _transport(
          FakeClient((request) async {
            return http.StreamedResponse(
              Stream<List<int>>.value(utf8.encode('Unauthorized')),
              401,
            );
          }),
        ),
      );

      expect(() => api.getHttpsState(), throwsA(isA<ApiFailure>()));
    });

    test('uploadCertificate sends body and returns state', () async {
      http.BaseRequest? captured;
      final api = CertificateApi(
        _transport(
          FakeClient((request) async {
            captured = request;
            return _success(<String, Object?>{
              'enabled': true,
              'http_url': 'http://localhost:7575',
              'https_url': 'https://localhost:7575',
              'fingerprint': 'NEW:FINGERPRINT',
              'not_after': '2027-01-01T00:00:00.000Z',
              'source': 'custom',
              'names': <String>['localhost'],
              'covers_host': true,
              'host': 'localhost',
            });
          }),
        ),
      );

      final state = await api.uploadCertificate(
        const UploadCertificateDto(
          certificate: 'cert-pem',
          privateKey: 'key-pem',
        ),
      );

      expect(state.fingerprint, 'NEW:FINGERPRINT');
      expect(captured!.url.path, '/api/settings/https/custom');
      expect(captured!.method, 'PUT');
      final body = jsonDecode(
        utf8.decode(await captured!.finalize().toBytes()),
      ) as Map<String, Object?>;
      expect(body['certificate'], 'cert-pem');
      expect(body['private_key'], 'key-pem');
    });

    test('deleteCertificate returns self-signed state', () async {
      final api = CertificateApi(
        _transport(
          FakeClient((request) async {
            expect(request.method, 'DELETE');
            expect(request.url.path, '/api/settings/https/custom');
            return _success(<String, Object?>{
              'enabled': true,
              'http_url': 'http://localhost:7575',
              'https_url': 'https://localhost:7575',
              'fingerprint': 'SELF:SIGNED',
              'not_after': '2027-01-01T00:00:00.000Z',
              'source': 'self_signed',
              'names': <String>['localhost'],
              'covers_host': true,
              'host': 'localhost',
            });
          }),
        ),
      );

      final state = await api.deleteCertificate();
      expect(state.source, 'self_signed');
    });

    test('downloadCertificate returns PEM bytes', () async {
      const pem =
          '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n';
      http.BaseRequest? captured;
      final api = CertificateApi(
        _transport(
          FakeClient((request) async {
            captured = request;
            return http.StreamedResponse(
              Stream<List<int>>.value(utf8.encode(pem)),
              200,
              headers: const <String, String>{
                'content-type': 'application/x-pem-file',
              },
            );
          }),
        ),
      );

      final bytes = await api.downloadCertificate();

      expect(utf8.decode(bytes), pem);
      expect(captured!.method, 'GET');
      expect(captured!.url.path, '/api/settings/https/certificate');
      expect(captured!.headers['authorization'], 'Bearer test-token');
      expect(
        captured!.headers['accept'],
        contains('application/x-pem-file'),
      );
    });

    test('downloadCertificate rejects empty body', () async {
      final api = CertificateApi(
        _transport(
          FakeClient(
            (_) async => http.StreamedResponse(Stream<List<int>>.empty(), 200),
          ),
        ),
      );

      expect(
        () => api.downloadCertificate(),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    });

    test('downloadCertificate propagates HTTP failures', () async {
      final api = CertificateApi(
        _transport(
          FakeClient((request) async {
            return http.StreamedResponse(
              Stream<List<int>>.value(
                utf8.encode(
                  jsonEncode(<String, Object?>{
                    'error': <String, Object?>{
                      'code': 'certificate_unavailable',
                      'message': 'missing',
                    },
                  }),
                ),
              ),
              500,
            );
          }),
        ),
      );

      expect(
        () => api.downloadCertificate(),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.kind,
            'kind',
            ApiFailureKind.http,
          ),
        ),
      );
    });
  });
}

HttpTransport _transport(http.BaseClient client) => HttpTransport(
      client: client,
      originProvider: () async => Uri.parse('https://api.example.test'),
      tokenProvider: (_) async => 'test-token',
      requestIdGenerator: () => 'certificate-test',
    );

http.StreamedResponse _success(Object? data) => http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(jsonEncode(<String, Object?>{'data': data})),
      ),
      200,
    );
