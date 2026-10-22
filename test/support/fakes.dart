import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/config/base_url_store.dart';
import 'package:onewifi_android/core/security/secure_token_store.dart';

/// 把每个请求交给 [handler] 的 http 客户端，同时记下调用次数与请求原文，
/// 供「没有多打一次」「头部没带 cookie」这类断言使用。
final class FakeClient extends http.BaseClient {
  FakeClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;
  int sendCount = 0;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sendCount += 1;
    requests.add(request);
    return handler(request);
  }
}

/// 内存版 [TokenStore]；记录 clear 过哪些 origin 以便断言登出路径。
final class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([Map<Uri, String>? seed]) : tokens = <Uri, String>{...?seed};

  final Map<Uri, String> tokens;
  final List<Uri> clearOrigins = <Uri>[];

  @override
  Future<void> clear(Uri origin) async {
    clearOrigins.add(origin);
    tokens.remove(origin);
  }

  @override
  Future<void> clearAll() async => tokens.clear();

  @override
  Future<String?> read(Uri origin) async => tokens[origin];

  @override
  Future<void> write(Uri origin, String token) async {
    tokens[origin] = token;
  }
}

/// 内存版 [BaseUrlStore]。
final class MemoryBaseUrlStore implements BaseUrlStore {
  MemoryBaseUrlStore(this.origin);

  Uri origin;

  @override
  Future<Uri> read() async => origin;

  @override
  Future<void> write(Uri origin) async => this.origin = origin;
}
