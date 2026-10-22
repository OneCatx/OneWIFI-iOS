import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import 'auth_dto.dart';

final class AuthApi {
  const AuthApi(this._transport);

  final HttpTransport _transport;

  Future<AuthSessionDto> login(String username, String password) async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: '/api/auth/login',
      body: <String, String>{'username': username, 'password': password},
      authMode: AuthMode.none,
      expireSessionOnUnauthorized: false,
    );
    return _parseSession(() => AuthSessionDto.fromLoginData(data));
  }

  Future<AuthSessionDto> restore({RequestCancellation? cancellation}) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: '/api/auth/session',
      cancellation: cancellation,
    );
    return _parseSession(() => AuthSessionDto.fromSessionData(data));
  }

  Future<void> logout() async {
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: '/api/auth/logout',
      expireSessionOnUnauthorized: false,
    );
    return guardShape('local-auth-response', () async {
      LogoutDto.fromData(data);
    });
  }

  static AuthSessionDto _parseSession(AuthSessionDto Function() parse) =>
      guardShapeSync('local-auth-response', parse);
}
