/// MDD instance-scoped calls API (matches gateway_api.dart routes).
///
/// Used when the gateway runs on the MDD base; existing CallsApi stays for
/// the legacy OneWIFI path.
library;

import 'gateway_api.dart';
import 'gateway_client.dart';

class MddCallsApi {
  MddCallsApi(this._client);

  final GatewayClient _client;

  Future<List<dynamic>> fetchLines() => _client.fetchLines();

  Future<Map<String, dynamic>> status(String lineId) =>
      _client.fetchLineStatus(lineId);

  Future<Map<String, dynamic>> softphone(String lineId) =>
      _client.fetchSoftphone(lineId);

  Future<Map<String, dynamic>> dial(String lineId, String number) =>
      _client.dial(lineId, number);

  Future<Map<String, dynamic>> hangup(String lineId) =>
      _client.hangup(lineId);

  Future<Map<String, dynamic>> history(String lineId) async {
    final data = await _client.request(GatewayApi.calls(lineId));
    return (data['data'] as Map?)?.cast<String, dynamic>() ?? data;
  }

  Uri websocket(String lineId) => _client.softphoneWebsocket(lineId);
}
