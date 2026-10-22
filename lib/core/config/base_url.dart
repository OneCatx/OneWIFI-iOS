import 'base_url_policy.dart';

final class BaseUrl {
  const BaseUrl._(this.origin);

  factory BaseUrl.parse(String input) {
    return BaseUrl._(BaseUrlPolicy.parseAndValidate(input));
  }

  final Uri origin;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is BaseUrl && other.origin == origin);
  }

  @override
  int get hashCode => origin.hashCode;
}
