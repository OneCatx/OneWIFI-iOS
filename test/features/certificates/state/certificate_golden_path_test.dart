import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';
import 'package:onewifi_android/features/certificates/data/certificate_repository.dart';
import 'package:onewifi_android/features/certificates/domain/certificate.dart';
import 'package:onewifi_android/features/certificates/state/certificate_controller.dart';

/// P4 证书旧黄金路径（iOS RequestNotifier 控制器）：load → upload → delete；401 鉴权。
void main() {
  group('load', () {
    test('loadCertificates lands under certificate.load key', () async {
      final repo = _Repo(items: <Certificate>[_cert('AA:BB')]);
      final controller = CertificateController(
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      await controller.loadCertificates();

      expect(controller.certificates.status, QueryStatus.data);
      expect(controller.certificates.key, 'certificate.load');
      expect(controller.items.single.fingerprint, 'AA:BB');
    });

    test('load 401 maps to authentication without fabricating empty', () async {
      final controller = CertificateController(
        repository: _Repo(
          loadError: const ApiFailure(
            ApiFailureKind.http,
            requestId: 'cert-401',
            statusCode: 401,
            backendCode: 'unauthorized',
          ),
        ),
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      await controller.loadCertificates();

      expect(controller.certificates.status, QueryStatus.failed);
      expect(
        controller.certificates.failure?.kind,
        StateFailureKind.authentication,
      );
      expect(controller.certificates.failure?.statusCode, 401);
      expect(controller.certificates.lastGoodData, isNull);
    });
  });

  group('upload', () {
    test('uploadCertificate replaces list and succeeds', () async {
      final repo = _Repo();
      final controller = CertificateController(
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      final ok = await controller.uploadCertificate(
        certificatePem:
            '-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----',
        privateKeyPem:
            '-----BEGIN PRIVATE KEY-----\nx\n-----END PRIVATE KEY-----',
      );

      expect(ok, isTrue);
      expect(repo.uploadCalls, 1);
      expect(controller.uploadAction.status, ActionStatus.succeeded);
      expect(controller.items.single.fingerprint, 'UP:LOAD');
    });
  });

  group('delete', () {
    test('deleteCertificate reloads list after success', () async {
      final repo = _Repo(items: <Certificate>[_cert('OLD')]);
      final controller = CertificateController(
        repository: repo,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      await controller.loadCertificates();
      repo.items = <Certificate>[];
      final ok = await controller.deleteCertificate('cert-1');

      expect(ok, isTrue);
      expect(repo.deleteCalls, 1);
      expect(repo.loadCalls, greaterThanOrEqualTo(2));
      expect(controller.deleteAction.status, ActionStatus.succeeded);
      expect(controller.certificates.status, QueryStatus.empty);
    });
  });
}

Certificate _cert(String fingerprint) => Certificate(
  id: 'cert-1',
  commonName: 'localhost',
  issuer: 'OneWIFI',
  validFrom: DateTime.utc(2026, 1, 1),
  validTo: DateTime.utc(2027, 1, 1),
  fingerprint: fingerprint,
  source: CertificateSource.custom,
  subjectAlternativeNames: const <String>['localhost'],
  coversHost: true,
);

final class _Repo implements CertificateRepository {
  _Repo({List<Certificate>? items, this.loadError})
    : items = items ?? <Certificate>[];

  List<Certificate> items;
  final Object? loadError;
  int loadCalls = 0;
  int uploadCalls = 0;
  int deleteCalls = 0;

  @override
  Future<List<Certificate>> getCertificates({
    RequestCancellation? cancellation,
  }) async {
    loadCalls += 1;
    final error = loadError;
    if (error != null) throw error;
    return List<Certificate>.unmodifiable(items);
  }

  @override
  Future<String> downloadCertificatePem({
    RequestCancellation? cancellation,
  }) async => '-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----';

  @override
  Future<Certificate> uploadCertificate({
    required String certificatePem,
    required String privateKeyPem,
    RequestCancellation? cancellation,
  }) async {
    uploadCalls += 1;
    final uploaded = _cert('UP:LOAD');
    items = <Certificate>[uploaded];
    return uploaded;
  }

  @override
  Future<void> deleteCertificate(
    String certificateId, {
    RequestCancellation? cancellation,
  }) async {
    deleteCalls += 1;
  }
}
