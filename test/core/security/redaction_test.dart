import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/security/redaction.dart';

void main() {
  group('Redaction.maskTail4', () {
    test('shows only the final four digits of a sensitive identifier', () {
      final identifier = List<String>.generate(
        20,
        (index) => ((index + 1) % 10).toString(),
      ).join();

      final masked = Redaction.maskTail4(identifier);

      expect(
        masked == '•••• ${identifier.substring(identifier.length - 4)}',
        isTrue,
        reason: 'masked output did not expose exactly the safe tail four',
      );
      expect(
        masked.contains(identifier),
        isFalse,
        reason: 'masked output retained the complete identifier',
      );
    });
  });

  group('Redaction.sanitizeText', () {
    test('removes raw mobile identifiers from error text', () {
      final identifiers = <String>[
        List<String>.generate(20, (index) => (index % 10).toString()).join(),
        List<String>.generate(
          15,
          (index) => ((index + 2) % 10).toString(),
        ).join(),
        List<String>.generate(
          15,
          (index) => ((index + 4) % 10).toString(),
        ).join(),
        List<String>.generate(
          11,
          (index) => ((index + 6) % 10).toString(),
        ).join(),
      ];
      final raw = 'Identifiers: ${identifiers.join(', ')}';

      final sanitized = Redaction.sanitizeText(raw);

      for (final identifier in identifiers) {
        expect(
          sanitized.contains(identifier),
          isFalse,
          reason: 'sanitized text retained a complete mobile identifier',
        );
        expect(
          sanitized.contains(identifier.substring(identifier.length - 4)),
          isTrue,
          reason: 'sanitized text did not retain the safe tail-four display',
        );
      }
    });

    test('removes values of named credential fields', () {
      final password = _runtimeSecret(length: 24, offset: 1);
      final accessToken = _runtimeSecret(length: 48, offset: 3);
      final sessionToken = _runtimeSecret(length: 40, offset: 5);
      final apiKey = _runtimeSecret(length: 36, offset: 7);
      final raw = <String>[
        'password=$password',
        'access_token: "$accessToken"',
        'session-token=$sessionToken',
        "api_key='$apiKey'",
      ].join('; ');

      final sanitized = Redaction.sanitizeText(raw);
      final retainedSecrets = <bool>[
        sanitized.contains(password),
        sanitized.contains(accessToken),
        sanitized.contains(sessionToken),
        sanitized.contains(apiKey),
      ];

      expect(
        retainedSecrets,
        everyElement(isFalse),
        reason: 'sanitized text retained a named credential value',
      );
      expect(
        '<redacted>'.allMatches(sanitized).length,
        4,
        reason: 'each named credential must have one redaction marker',
      );
    });

    test('removes full URI and bearer credential from diagnostic text', () {
      final account = List<String>.generate(
        15,
        (index) => ((index + 3) % 10).toString(),
      ).join();
      final token = List<String>.generate(
        48,
        (index) => String.fromCharCode(65 + (index % 26)),
      ).join();
      final uri = Uri(
        scheme: 'https',
        host: 'api.example.test',
        path: '/devices/$account',
        queryParameters: <String, String>{'access_token': token},
      );
      final raw = 'GET $uri failed; Authorization: Bearer $token';

      final sanitized = Redaction.sanitizeText(raw);

      expect(
        <bool>[
          sanitized.contains(uri.toString()),
          sanitized.contains(account),
          sanitized.contains(token),
        ],
        everyElement(isFalse),
        reason: 'sanitized diagnostics retained URI or credential material',
      );
      expect(sanitized.contains('<redacted-uri>'), isTrue);
      expect(sanitized.contains('Bearer <redacted>'), isTrue);
    });

    test('replaces a response body without inspecting its content', () {
      final secret = _runtimeSecret(length: 52, offset: 9);
      final responseBody = '{"password":"$secret","result":"opaque"}';

      final diagnostic = Redaction.redactResponseBody(responseBody);

      expect(
        diagnostic == '<redacted-body>',
        isTrue,
        reason: 'response body diagnostic was not the fixed placeholder',
      );
      expect(
        diagnostic.contains(secret),
        isFalse,
        reason: 'response body diagnostic retained original content',
      );
    });
  });
}

String _runtimeSecret({required int length, required int offset}) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}
