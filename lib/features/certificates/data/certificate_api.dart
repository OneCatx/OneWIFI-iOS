import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import 'certificate_dto.dart';

/// API client for certificate management endpoints.
final class CertificateApi {
  const CertificateApi(this._transport);

  final HttpTransport _transport;

  /// Fetches the current HTTPS settings state.
  Future<HttpsStateDto> getHttpsState({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.settingsHttps,
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
    return _parse(() => HttpsStateDto.fromJson(data));
  }

  /// Downloads the certificate PEM file as bytes.
  ///
  /// Backend: `GET /api/settings/https/certificate`
  /// (`application/x-pem-file` attachment).
  Future<List<int>> downloadCertificate({
    RequestCancellation? cancellation,
  }) async {
    final bytes = await _transport.sendBytes(
      method: 'GET',
      routeTemplate: GatewayApi.settingsHttpsCertificate,
      authMode: AuthMode.bearer,
      accept: 'application/x-pem-file, application/octet-stream, */*',
      cancellation: cancellation,
    );
    if (bytes.isEmpty) {
      throw ApiFailure(
        ApiFailureKind.protocol,
        requestId: 'local-certificate-download',
        message: 'The certificate download response was empty.',
      );
    }
    return bytes;
  }

  /// Uploads a custom certificate.
  Future<HttpsStateDto> uploadCertificate(
    UploadCertificateDto dto, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.settingsHttpsCustom,
      body: dto.toJson(),
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
    return _parse(() => HttpsStateDto.fromJson(data));
  }

  /// Deletes the custom certificate (reverts to self-signed).
  Future<HttpsStateDto> deleteCertificate({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'DELETE',
      routeTemplate: GatewayApi.settingsHttpsCustom,
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
    return _parse(() => HttpsStateDto.fromJson(data));
  }

  /// Re-issues the self-signed certificate for the current host.
  Future<HttpsStateDto> reissueCertificate({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.settingsHttpsReissue,
      authMode: AuthMode.bearer,
      cancellation: cancellation,
    );
    return _parse(() => HttpsStateDto.fromJson(data));
  }

  static T _parse<T>(T Function() parse) =>
      guardShapeSync('local-certificate-response', parse);
}
