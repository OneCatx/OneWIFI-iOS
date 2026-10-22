import '../../../core/config/base_url_policy.dart';
import '../../../core/http/gateway_io_client.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/request_notifier.dart';
import '../data/mihomo_backend_store.dart';
import '../data/mihomo_client.dart';
import '../domain/mihomo_backend.dart';

final class MihomoConnectionController extends RequestNotifier {
  factory MihomoConnectionController({
    required MihomoBackendStore store,
    required MihomoClient client,
    required RequestRegistry requestRegistry,
    GatewayConnectionFactory? connections,
  }) =>
      MihomoConnectionController._(store, client, requestRegistry, connections);

  MihomoConnectionController._(
    this._store,
    this._client,
    RequestRegistry requestRegistry,
    this.connections,
  ) : _connect = RequestSlot(requestRegistry, _connectKey);

  static const String _connectKey = 'mihomo.connect';

  final MihomoBackendStore _store;
  final MihomoClient _client;
  final RequestSlot _connect;
  final GatewayConnectionFactory? connections;
  ActionState _connectAction = const ActionState.idle();
  var _connected = false;
  Uri? _origin;
  String _secret = '';
  String _status = '';

  ActionState get connectAction => _connectAction;
  bool get connected => _connected;
  Uri? get origin => _origin;
  String get secret => _secret;
  String get status => _status;

  @override
  List<RequestSlot> get slots => <RequestSlot>[_connect];

  Future<void> hydrate() async {
    if (isDisposed) return;
    final saved = await _store.read();
    if (isDisposed) return;
    if (saved != null) {
      publish(() {
        _origin = saved.origin;
        _secret = saved.secret;
        _connected = true;
        _status = '';
      });
      return;
    }
    publish(() {
      _origin = null;
      _secret = '';
      _connected = false;
      _status = '';
    });
  }

  Future<bool> connect({
    required String host,
    required String port,
    required bool https,
    required String secret,
  }) async {
    final Uri origin;
    try {
      origin = BaseUrlPolicy.fromHostAndPort(
        host: host,
        port: port,
        https: https,
      );
    } on FormatException catch (error) {
      if (isDisposed) return false;
      publish(() => _status = error.message);
      return false;
    }
    final trimmedSecret = secret.trim();
    return runAction<void>(
      slot: _connect,
      current: () => _connectAction,
      set: _setConnectAction,
      request: (ticket) async {
        await _client.fetchProxies(
          origin: origin,
          secret: trimmedSecret,
          cancellation: ticket.cancellation,
        );
        await _store.write(
          MihomoBackend(origin: origin, secret: trimmedSecret),
        );
      },
      onSuccess: (_, _) {
        publish(() {
          _origin = origin;
          _secret = trimmedSecret;
          _connected = true;
          _status = '已连上';
        });
        return const ActionState.succeeded();
      },
      onFailure: (error) {
        publish(() {
          _connected = false;
          _status = _connectFailureStatus(error, trimmedSecret);
        });
      },
    );
  }

  void _setConnectAction(ActionState next) {
    publish(() => _connectAction = next);
  }

  static String _connectFailureStatus(Object error, String secret) {
    if (error is ApiFailure && error.kind == ApiFailureKind.authentication) {
      return secret.isEmpty ? '这台 Mihomo 开了密钥，空着连不上。' : '密钥不对。';
    }
    return '连不上 Mihomo。检查主机和端口。';
  }
}
