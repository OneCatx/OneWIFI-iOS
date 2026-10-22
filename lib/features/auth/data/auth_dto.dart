import '../../../core/http/json_shape.dart';

final class AuthSessionDto {
  const AuthSessionDto._({
    required this.username,
    required this.sessionToken,
    required this.expiresAt,
  });

  factory AuthSessionDto.fromLoginData(Object? value) {
    final data = _shape.map(value);
    _requireNonEmptyString(data['csrf_token']);
    if (data['status'] != 'ok') throw const AuthDtoException();
    return AuthSessionDto._fromSessionData(data);
  }

  factory AuthSessionDto.fromSessionData(Object? value) {
    return AuthSessionDto._fromSessionData(_shape.map(value));
  }

  factory AuthSessionDto._fromSessionData(Map<Object?, Object?> data) {
    final user = _shape.map(data['user']);
    final username = _requireNonEmptyString(user['username']);
    final sessionToken = _requireNonEmptyString(data['session_token']);
    if (data['authenticated'] != true) throw const AuthDtoException();
    final expiresAt = _parseRfc3339(data['expires_at']);
    return AuthSessionDto._(
      username: username,
      sessionToken: sessionToken,
      expiresAt: expiresAt,
    );
  }

  final String username;
  final String sessionToken;
  final DateTime expiresAt;
}

final class LogoutDto {
  const LogoutDto._();

  factory LogoutDto.fromData(Object? value) {
    final data = _shape.map(value);
    if (data['logged_out'] != true) throw const AuthDtoException();
    return const LogoutDto._();
  }
}

final class AuthDtoException implements DtoShapeException {
  const AuthDtoException();
}

String _requireNonEmptyString(Object? value) {
  final text = _shape.string(value);
  if (text.trim().isEmpty) throw const AuthDtoException();
  return text;
}

DateTime _parseRfc3339(Object? value) {
  final text = _shape.string(value);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|([+-])(\d{2}):(\d{2}))$',
  ).firstMatch(text);
  if (match == null) throw const AuthDtoException();

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final offsetHour = match.group(8) == null ? 0 : int.parse(match.group(8)!);
  final offsetMinute = match.group(9) == null ? 0 : int.parse(match.group(9)!);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > _daysInMonth(year, month) ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      offsetHour > 23 ||
      offsetMinute > 59) {
    throw const AuthDtoException();
  }
  try {
    return DateTime.parse(text).toUtc();
  } on FormatException {
    throw const AuthDtoException();
  }
}

int _daysInMonth(int year, int month) {
  return switch (month) {
    2 => _isLeapYear(year) ? 29 : 28,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };
}

bool _isLeapYear(int year) {
  return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

const _shape = JsonShape(AuthDtoException.new);
