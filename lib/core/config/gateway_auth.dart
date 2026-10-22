/// MDD auth helper: login stores CSRF for mutating calls.
library;

import 'gateway_api.dart';
import 'gateway_client.dart';
import 'gateway_mode.dart';

class GatewayAuth {
  GatewayAuth(this._client);

  final GatewayClient _client;

  Future<void> login(String username, String password, {String? lineId}) async {
    await _client.login(username, password);
    GatewayModeController.useMdd(_client.origin, initialLine: lineId);
  }

  Future<Map<String, dynamic>> status() async {
    try {
      return await _client.request(GatewayApi.session);
    } catch (_) {
      return <String, dynamic>{'authenticated': false};
    }
  }

  void useLegacy() {
    GatewayModeController.useLegacy();
  }
}
