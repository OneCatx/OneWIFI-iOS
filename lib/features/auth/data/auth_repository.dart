import '../../../core/http/http_transport.dart';
import '../../../core/security/secure_token_store.dart';
import '../domain/session_user.dart';
import 'auth_api.dart';

abstract interface class AuthRepository {
  Future<SessionUser> login(String username, String password);

  Future<SessionUser> restore({RequestCancellation? cancellation});

  Future<void> logout();
}

abstract interface class SessionExpirySource {
  DateTime? takeSessionExpiresAt(SessionUser user);
}

final class DefaultAuthRepository
    implements AuthRepository, SessionExpirySource {
  factory DefaultAuthRepository({
    required AuthApi api,
    required TokenStore tokenStore,
    required Future<Uri> Function() originProvider,
  }) {
    return DefaultAuthRepository._(api, tokenStore, originProvider);
  }

  DefaultAuthRepository._(this._api, this._tokenStore, this._originProvider);

  final AuthApi _api;
  final TokenStore _tokenStore;
  final Future<Uri> Function() _originProvider;
  final Expando<DateTime> _expiresAtByUser = Expando<DateTime>();

  @override
  Future<SessionUser> login(String username, String password) async {
    final origin = await _originProvider();
    final session = await _api.login(username, password);
    await _tokenStore.write(origin, session.sessionToken);
    final user = SessionUser(session.username);
    _expiresAtByUser[user] = session.expiresAt;
    return user;
  }

  @override
  Future<SessionUser> restore({RequestCancellation? cancellation}) async {
    final session = await _api.restore(cancellation: cancellation);
    final user = SessionUser(session.username);
    _expiresAtByUser[user] = session.expiresAt;
    return user;
  }

  @override
  Future<void> logout() => _api.logout();

  @override
  DateTime? takeSessionExpiresAt(SessionUser user) {
    final value = _expiresAtByUser[user];
    _expiresAtByUser[user] = null;
    return value;
  }
}
