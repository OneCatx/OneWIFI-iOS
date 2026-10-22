final class SessionUser {
  factory SessionUser(String username) {
    final validated = username.trim();
    if (validated.isEmpty) {
      throw ArgumentError.value(null, 'username', 'Username is required.');
    }
    return SessionUser._(validated);
  }

  const SessionUser._(this.username);

  final String username;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SessionUser && other.username == username);
  }

  @override
  int get hashCode => username.hashCode;
}
