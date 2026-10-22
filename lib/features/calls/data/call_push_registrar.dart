import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import 'ios_call_push.dart';

/// 把本机 VoIP 令牌登记到网关。只有登记过的令牌，服务端才可能在来电时
/// 推来一条 VoIP 推送；登记动作本身幂等，重复登记没有副作用。
abstract interface class CallPushRegistrar {
  Future<void> register(CallPushToken token);
}

/// 走登录会话的 Bearer 请求。登记绑定的是「这条会话能触达哪些设备」，所以
/// 这里既没有配对码也没有单独的鉴权材料——会话失效，登记自然也就不该继续
/// 被当作有效。
final class GatewayCallPushRegistrar implements CallPushRegistrar {
  const GatewayCallPushRegistrar(this._transport);

  final HttpTransport _transport;

  @override
  Future<void> register(CallPushToken token) async {
    await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.callsPush,
      body: <String, String>{
        'device_token': token.deviceToken,
        'environment': token.environment,
      },
    );
  }
}