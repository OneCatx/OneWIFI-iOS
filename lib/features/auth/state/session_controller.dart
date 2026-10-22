import '../../../core/config/base_url_policy.dart';
import '../../../core/config/base_url_store.dart';
import '../../../core/http/gateway_io_client.dart';
import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/security/secure_token_store.dart';
import '../../../core/security/session_resource.dart';
import '../../../core/state/request_notifier.dart';
import '../../../core/state/session_state.dart';
import '../../../core/state/state_failure.dart';
import '../data/auth_repository.dart';
import '../domain/session_user.dart';

/// Manages user authentication session lifecycle and state.
///
/// This controller handles bootstrap restoration, sign-in, sign-out, origin changes,
/// and session expiration. It coordinates token storage, session resource cleanup,
/// and request cancellation across session boundaries.
///
/// The iOS version supports registering multiple [SessionResource] instances that
/// will be cleared on session changes (sign-in, sign-out, origin change, expiration).
///
/// The controller maintains a session epoch counter that increments on each authentication
/// state change, allowing in-flight requests to be invalidated when stale.
final class SessionController extends RequestNotifier {
  /// Creates a [SessionController] with the specified dependencies.
  ///
  /// Parameters:
  /// - [repository]: Repository for authentication operations
  /// - [tokenStore]: Secure storage for authentication tokens
  /// - [baseUrlStore]: Storage for the gateway base URL/origin
  /// - [requestRegistry]: Registry for tracking and cancelling requests
  /// - [connections]: Optional factory for gateway connections
  factory SessionController({
    required AuthRepository repository,
    required TokenStore tokenStore,
    required BaseUrlStore baseUrlStore,
    required RequestRegistry requestRegistry,
    GatewayConnectionFactory? connections,
  }) {
    return SessionController._(
      repository,
      tokenStore,
      baseUrlStore,
      requestRegistry,
      connections,
    );
  }

  SessionController._(
    this._repository,
    this._tokenStore,
    this._baseUrlStore,
    this._requestRegistry,
    this.connections,
  ) : _restore = RequestSlot(_requestRegistry, 'auth.restore');

  final AuthRepository _repository;
  final TokenStore _tokenStore;
  final BaseUrlStore _baseUrlStore;
  final RequestRegistry _requestRegistry;
  final GatewayConnectionFactory? connections;
  final RequestSlot _restore;
  SessionState _state = const SessionState.booting();
  Uri _origin = BaseUrlPolicy.defaultOrigin;
  int _sessionEpoch = 0;
  Future<void> _mutationTail = Future<void>.value();
  Future<void>? _signInInFlight;

  /// Current session state (booting, signed in, signed out, failed, etc.).
  SessionState get state => _state;
  
  /// Current gateway origin URL.
  Uri get origin => _origin;
  
  /// Current session epoch counter, incremented on each authentication state change.
  int get sessionEpoch => _sessionEpoch;
  
  final Set<SessionResource> _resources = {};
  
  /// Registers a [SessionResource] to be cleared on session changes.
  void registerResource(SessionResource resource) => _resources.add(resource);
  
  /// Unregisters a previously registered [SessionResource].
  void unregisterResource(SessionResource resource) =>
      _resources.remove(resource);
      
  /// Clears all registered session resources with timeout protection.
  Future<void> _clearResources() async {
    await Future.wait(
      _resources.toList().map((resource) async {
        try {
          await resource.clear().timeout(const Duration(seconds: 3));
        } catch (_) {
          // Local auth cleanup must still proceed if a platform teardown fails.
        }
      }),
    );
  }

  @override
  List<RequestSlot> get slots => <RequestSlot>[_restore];

  /// Bootstraps the session by restoring the saved token and user from storage.
  ///
  /// This method:
  /// 1. Reads the saved origin URL
  /// 2. Attempts to load the authentication token
  /// 3. If a valid token exists, restores the user session
  /// 4. Transitions to signed-in state on success, or signed-out if no token
  ///
  /// This is typically called at app startup. If the controller is disposed or
  /// the session epoch changes during bootstrap, the restoration is cancelled.
  Future<void> bootstrap() async {
    if (isDisposed) return;
    final startedEpoch = _sessionEpoch;
    final ticket = _restore.begin();
    try {
      final origin = await _baseUrlStore.read();
      if (!_isBootstrapCurrent(startedEpoch, ticket)) return;
      _origin = origin;
      final token = await _tokenStore.read(origin);
      if (!_isBootstrapCurrent(startedEpoch, ticket)) return;
      if (token == null || token.trim().isEmpty) {
        _setState(const SessionState.signedOut());
        return;
      }
      final user = await _repository.restore(cancellation: ticket.cancellation);
      if (_isBootstrapCurrent(startedEpoch, ticket)) {
        _setState(
          SessionState.signedIn(
            principal: user,
            expiresAt: _takeSessionExpiresAt(user),
          ),
        );
      }
    } catch (error) {
      if (!_isBootstrapCurrent(startedEpoch, ticket)) return;
      _setState(SessionState.failed(failure: StateFailure.fromError(error)));
    } finally {
      ticket.end();
    }
  }

  /// Signs in a user with the provided credentials.
  ///
  /// Parameters:
  /// - [username]: User's username or email
  /// - [password]: User's password
  ///
  /// This method:
  /// 1. Cancels any in-flight restoration or requests
  /// 2. Transitions to signing-in state
  /// 3. Clears all registered session resources
  /// 4. Attempts login and increments session epoch on success
  /// 5. Transitions to signed-in or failed state
  ///
  /// Only one sign-in operation can be active at a time. Subsequent calls
  /// return the same pending future.
  ///
  /// Returns a [Future] that completes when the sign-in attempt finishes.
  Future<void> signIn(String username, String password) {
    if (isDisposed) return Future<void>.value();
    final current = _signInInFlight;
    if (current != null) return current;
    // 登录会重置会话：正在恢复的旧 token 结果不能再落下来。
    _restore.cancel();
    _requestRegistry.cancelAll();
    final pending = _enqueue(() async {
      final previous = _state;
      _setState(SessionState.signingIn(previousStable: previous));
      await _clearResources();
      try {
        final user = await _repository.login(username, password);
        _sessionEpoch += 1;
        _setState(
          SessionState.signedIn(
            principal: user,
            expiresAt: _takeSessionExpiresAt(user),
          ),
        );
      } catch (error) {
        _setState(
          SessionState.failed(
            failure: StateFailure.fromError(error),
            previousStable: previous,
          ),
        );
      }
    });
    _signInInFlight = pending;
    pending.whenComplete(() {
      if (identical(_signInInFlight, pending)) {
        _signInInFlight = null;
      }
    });
    return pending;
  }

  /// Signs out the current user and clears the stored token.
  ///
  /// This method:
  /// 1. Clears all registered session resources
  /// 2. Reads the current origin
  /// 3. Cancels all in-flight requests
  /// 4. Increments the session epoch
  /// 5. Attempts to notify the backend of logout
  /// 6. Clears the stored authentication token
  /// 7. Transitions to signed-out state
  ///
  /// The local token cleanup is authoritative; backend logout failures
  /// are silently ignored.
  ///
  /// Returns a [Future] that completes when sign-out finishes.
  Future<void> signOut() {
    if (isDisposed) return Future<void>.value();
    return _enqueue(() async {
      await _clearResources();
      final Uri origin;
      try {
        origin = await _baseUrlStore.read();
      } catch (error) {
        _setState(SessionState.failed(failure: StateFailure.fromError(error)));
        return;
      }
      _requestRegistry.cancelAll();
      _sessionEpoch += 1;
      try {
        await _repository.logout();
      } catch (_) {
        // Local exact-origin cleanup is authoritative for the signed-out state.
      }
      try {
        await _tokenStore.clear(origin);
        _setState(const SessionState.signedOut());
      } catch (error) {
        _setState(SessionState.failed(failure: StateFailure.fromError(error)));
      }
    });
  }

  /// Changes the gateway origin URL and clears the current session.
  ///
  /// Parameters:
  /// - [origin]: New gateway origin URI
  ///
  /// This method:
  /// 1. Clears all registered session resources
  /// 2. Validates and normalizes the new origin
  /// 3. Cancels all in-flight requests
  /// 4. Increments the session epoch
  /// 5. Clears tokens for both old and new origins
  /// 6. Persists the new origin
  /// 7. Transitions to signed-out state
  ///
  /// Returns a [Future] that completes when the origin change finishes.
  Future<void> changeOrigin(Uri origin) {
    if (isDisposed) return Future<void>.value();
    return _enqueue(() async {
      await _clearResources();
      final Uri normalized;
      final Uri oldOrigin;
      try {
        normalized = BaseUrlPolicy.parseAndValidate(origin.toString());
        oldOrigin = await _baseUrlStore.read();
      } catch (error) {
        _setState(SessionState.failed(failure: StateFailure.fromError(error)));
        return;
      }

      _requestRegistry.cancelAll();
      _sessionEpoch += 1;
      Object? clearFailure;
      for (final target in <Uri>{oldOrigin, normalized}) {
        try {
          await _tokenStore.clear(target);
        } catch (error) {
          clearFailure ??= error;
        }
      }
      if (clearFailure != null) {
        _setState(
          SessionState.failed(failure: StateFailure.fromError(clearFailure)),
        );
        return;
      }
      try {
        await _baseUrlStore.write(normalized);
        _origin = normalized;
        _setState(const SessionState.signedOut());
      } catch (error) {
        _setState(SessionState.failed(failure: StateFailure.fromError(error)));
      }
    });
  }

  /// Expires the current session if the captured epoch matches.
  ///
  /// Parameters:
  /// - [capturedEpoch]: Session epoch to check before expiring
  ///
  /// This method is called when a 401 or session timeout is detected.
  /// If the captured epoch still matches the current epoch (meaning no
  /// intervening sign-in/sign-out has occurred), the session is expired:
  /// 1. Cancels all in-flight requests
  /// 2. Increments the session epoch
  /// 3. Clears all registered session resources
  /// 4. Clears the stored token
  /// 5. Transitions to expired state
  ///
  /// Returns a [Future] that completes when expiration finishes.
  Future<void> expireIfCurrent(int capturedEpoch) {
    if (isDisposed) return Future<void>.value();
    return _enqueue(() async {
      if (capturedEpoch != _sessionEpoch) return;
      _requestRegistry.cancelAll();
      _sessionEpoch += 1;
      await _clearResources();
      try {
        final origin = await _baseUrlStore.read();
        await _tokenStore.clear(origin);
        _setState(
          const SessionState.expired(
            failure: StateFailure(StateFailureKind.authentication),
          ),
        );
      } catch (error) {
        _setState(SessionState.failed(failure: StateFailure.fromError(error)));
      }
    });
  }

  void _setState(SessionState next) => publish(() => _state = next);

  bool _isBootstrapCurrent(int startedEpoch, RequestTicket ticket) =>
      _sessionEpoch == startedEpoch && ticket.isCurrent;

  DateTime? _takeSessionExpiresAt(SessionUser user) {
    return switch (_repository) {
      final SessionExpirySource source => source.takeSessionExpiresAt(user),
      _ => null,
    };
  }

  Future<void> _enqueue(Future<void> Function() mutation) {
    final next = _mutationTail.then((_) => mutation());
    _mutationTail = next;
    return next;
  }
}
