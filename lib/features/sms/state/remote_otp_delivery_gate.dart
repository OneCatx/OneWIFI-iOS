/// Serializes notification ownership across the APNs and SSE paths.
///
/// A message is marked delivered only after its visible notification has been
/// accepted. Failed delivery releases the id so the other path can retry it.
final class RemoteOtpDeliveryGate {
  final Set<int> _claimed = <int>{};

  bool claim(int smsId) {
    if (smsId <= 0 || _claimed.contains(smsId)) return false;
    _claimed.add(smsId);
    return true;
  }

  bool contains(int smsId) => _claimed.contains(smsId);

  void release(int smsId) => _claimed.remove(smsId);
}
