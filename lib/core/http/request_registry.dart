import 'http_transport.dart';

final class RequestRegistration {
  RequestRegistration._(this.cancellation);

  final RequestCancellation cancellation;
}

final class RequestRegistry {
  final Map<String, RequestRegistration> _reads =
      <String, RequestRegistration>{};

  RequestRegistration register(String key) {
    final next = RequestRegistration._(RequestCancellation());
    _reads.update(key, (current) {
      current.cancellation.cancel();
      return next;
    }, ifAbsent: () => next);
    return next;
  }

  void remove(String key, RequestRegistration registration) {
    if (identical(_reads[key], registration)) {
      _reads.remove(key);
    }
  }

  void cancelAll() {
    final active = _reads.values.toList(growable: false);
    _reads.clear();
    for (final registration in active) {
      registration.cancellation.cancel();
    }
  }
}
