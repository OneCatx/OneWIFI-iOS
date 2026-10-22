import 'http_transport.dart' show ApiFailure, ApiFailureKind;

/// 各模块 `*DtoException` 的公共标记：只表示「响应形状与契约不符」，不携带任何
/// 响应内容，避免把敏感字段带进错误对象。
abstract interface class DtoShapeException implements Exception {}

/// 把数据层抛出的 [DtoShapeException] 统一翻成 `ApiFailure(protocol)`，
/// `requestId` 用 `local-<module>-response` 标记这是本地解析失败、不是网关回的请求号。
/// 其它异常（网络、取消、业务失败）原样穿透。
Future<T> guardShape<T>(String requestId, Future<T> Function() body) async {
  try {
    return await body();
  } on DtoShapeException {
    throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
  }
}

/// [guardShape] 的同步版，给纯解析函数用。
T guardShapeSync<T>(String requestId, T Function() body) {
  try {
    return body();
  } on DtoShapeException {
    throw ApiFailure(ApiFailureKind.protocol, requestId: requestId);
  }
}

/// 响应 JSON 的形状校验器。
///
/// 每个数据模块用自己的 `*DtoException` 实例化一份（`JsonShape(XDtoException.new)`），
/// 这样仓储层与测试仍按模块异常类型区分「哪一路契约坏了」，而校验逻辑只有这一份，
/// 不再每个 api/dto 文件各抄一套 `_requireMap / _requireList / _requireString`。
///
/// 只做类型与范围判断，不做业务含义解释；业务口径（比如「ICCID 非空」）留在调用方。
final class JsonShape {
  const JsonShape(this._raise);

  final Exception Function() _raise;

  Never _fail() => throw _raise();

  Map<Object?, Object?> map(Object? value) =>
      value is Map<Object?, Object?> ? value : _fail();

  List<Object?> list(Object? value) => value is List<Object?> ? value : _fail();

  String string(Object? value) => value is String ? value : _fail();

  /// 非空字符串（不 trim；`" "` 视为有内容）。需要去空白的口径由调用方自行 trim。
  String nonEmptyString(Object? value) {
    final result = string(value);
    return result.isEmpty ? _fail() : result;
  }

  /// 先 trim 再判空，返回 trim 后的值；仅空白视为空。
  String trimmedNonEmptyString(Object? value) {
    final result = string(value).trim();
    return result.isEmpty ? _fail() : result;
  }

  /// 缺省 / null 当空串；给了但不是字串才算脏数据。不 trim。
  String optionalString(Object? value) => value == null ? '' : string(value);

  bool boolean(Object? value) => value is bool ? value : _fail();

  /// 严格整数：JSON 里必须是 int，`3.0` 也拒绝。
  int integer(Object? value) => value is int ? value : _fail();

  /// 整数值：接受 int，也接受 `3.0` 这类整值 double（部分网关按 float64 序列化计数）。
  int integralInt(Object? value) {
    if (value is int) return value;
    if (value is double &&
        value.isFinite &&
        value == value.truncateToDouble()) {
      return value.toInt();
    }
    return _fail();
  }

  int nonNegativeInt(Object? value) {
    final result = integer(value);
    return result < 0 ? _fail() : result;
  }

  int nonNegativeIntegralInt(Object? value) {
    final result = integralInt(value);
    return result < 0 ? _fail() : result;
  }

  int positiveInt(Object? value) {
    final result = integer(value);
    return result <= 0 ? _fail() : result;
  }

  /// `DateTime.tryParse` 能解析的日期时间字串（不 trim，不接受数字时间戳）。
  /// 按解析结果原样返回、不转时区；`toLocal()` 与 Go 零时间 `year <= 1` 哨兵由调用方处理。
  DateTime dateTime(Object? value) =>
      DateTime.tryParse(string(value)) ?? _fail();
}
