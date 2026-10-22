import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/json_shape.dart';

final class _ShapeError implements DtoShapeException {
  const _ShapeError();
}

final class _OtherError implements DtoShapeException {
  const _OtherError();
}

const shape = JsonShape(_ShapeError.new);

final Matcher throwsShapeError = throwsA(isA<_ShapeError>());

void main() {
  test('raises the exception type injected by the owning module', () {
    const other = JsonShape(_OtherError.new);
    expect(() => shape.string(null), throwsShapeError);
    expect(() => other.string(null), throwsA(isA<_OtherError>()));
    expect(() => other.string(null), isNot(throwsShapeError));
  });

  group('map', () {
    test('returns the same map instance', () {
      final value = <String, Object?>{'a': 1};
      expect(shape.map(value), same(value));
      expect(shape.map(<Object?, Object?>{}), isEmpty);
    });

    test('rejects null and non-map values', () {
      expect(() => shape.map(null), throwsShapeError);
      expect(() => shape.map(<Object?>[]), throwsShapeError);
      expect(() => shape.map('{}'), throwsShapeError);
      expect(() => shape.map(1), throwsShapeError);
    });
  });

  group('list', () {
    test('returns the same list instance', () {
      final value = <Object?>[1, 'two'];
      expect(shape.list(value), same(value));
      expect(shape.list(<int>[3]), <Object?>[3]);
      expect(shape.list(<Object?>[]), isEmpty);
    });

    test('rejects null and non-list values', () {
      expect(() => shape.list(null), throwsShapeError);
      expect(() => shape.list(<Object?, Object?>{}), throwsShapeError);
      expect(() => shape.list('[]'), throwsShapeError);
      expect(() => shape.list(1), throwsShapeError);
    });
  });

  group('string', () {
    test('returns strings untouched, including empty and whitespace', () {
      expect(shape.string('abc'), 'abc');
      expect(shape.string(''), '');
      expect(shape.string(' \t'), ' \t');
      expect(shape.string(' a '), ' a ');
    });

    test('rejects null and non-string values', () {
      expect(() => shape.string(null), throwsShapeError);
      expect(() => shape.string(1), throwsShapeError);
      expect(() => shape.string(true), throwsShapeError);
      expect(() => shape.string(<Object?>[]), throwsShapeError);
    });
  });

  group('nonEmptyString', () {
    test('returns non-empty strings without trimming', () {
      expect(shape.nonEmptyString('abc'), 'abc');
      expect(shape.nonEmptyString(' a '), ' a ');
      expect(shape.nonEmptyString(' '), ' ');
      expect(shape.nonEmptyString('\n'), '\n');
    });

    test('rejects empty string, null and non-string values', () {
      expect(() => shape.nonEmptyString(''), throwsShapeError);
      expect(() => shape.nonEmptyString(null), throwsShapeError);
      expect(() => shape.nonEmptyString(1), throwsShapeError);
      expect(() => shape.nonEmptyString(<Object?>['a']), throwsShapeError);
    });
  });

  group('optionalString', () {
    test('maps null to empty and returns strings without trimming', () {
      expect(shape.optionalString(null), '');
      expect(shape.optionalString(''), '');
      expect(shape.optionalString(' '), ' ');
      expect(shape.optionalString(' a '), ' a ');
      expect(shape.optionalString('abc'), 'abc');
    });

    test('rejects present non-string values', () {
      expect(() => shape.optionalString(1), throwsShapeError);
      expect(() => shape.optionalString(0), throwsShapeError);
      expect(() => shape.optionalString(true), throwsShapeError);
      expect(() => shape.optionalString(<Object?>[]), throwsShapeError);
      expect(
        () => shape.optionalString(<Object?, Object?>{}),
        throwsShapeError,
      );
    });
  });

  group('trimmedNonEmptyString', () {
    test('returns the trimmed value', () {
      expect(shape.trimmedNonEmptyString('abc'), 'abc');
      expect(shape.trimmedNonEmptyString(' a '), 'a');
      expect(shape.trimmedNonEmptyString('\ta b\n'), 'a b');
    });

    test('rejects empty, whitespace-only, null and non-string values', () {
      expect(() => shape.trimmedNonEmptyString(''), throwsShapeError);
      expect(() => shape.trimmedNonEmptyString(' '), throwsShapeError);
      expect(() => shape.trimmedNonEmptyString(' \t\n'), throwsShapeError);
      expect(() => shape.trimmedNonEmptyString(null), throwsShapeError);
      expect(() => shape.trimmedNonEmptyString(1), throwsShapeError);
      expect(
        () => shape.trimmedNonEmptyString(<Object?>['a']),
        throwsShapeError,
      );
    });
  });

  group('boolean', () {
    test('returns both boolean values', () {
      expect(shape.boolean(true), isTrue);
      expect(shape.boolean(false), isFalse);
    });

    test('rejects null, numbers and string spellings', () {
      expect(() => shape.boolean(null), throwsShapeError);
      expect(() => shape.boolean(1), throwsShapeError);
      expect(() => shape.boolean(0), throwsShapeError);
      expect(() => shape.boolean('true'), throwsShapeError);
      expect(() => shape.boolean(''), throwsShapeError);
    });
  });

  group('integer', () {
    test('returns any int including zero and negatives', () {
      expect(shape.integer(0), 0);
      expect(shape.integer(-1), -1);
      expect(shape.integer(7), 7);
    });

    test('rejects doubles even when integral, and non-numbers', () {
      expect(() => shape.integer(3.0), throwsShapeError);
      expect(() => shape.integer(2.5), throwsShapeError);
      expect(() => shape.integer(double.nan), throwsShapeError);
      expect(() => shape.integer(double.infinity), throwsShapeError);
      expect(() => shape.integer(null), throwsShapeError);
      expect(() => shape.integer('3'), throwsShapeError);
      expect(() => shape.integer(''), throwsShapeError);
      expect(() => shape.integer(true), throwsShapeError);
    });
  });

  group('integralInt', () {
    test('returns ints and converts integral doubles', () {
      expect(shape.integralInt(0), 0);
      expect(shape.integralInt(-1), -1);
      expect(shape.integralInt(7), 7);
      expect(shape.integralInt(3.0), 3);
      expect(shape.integralInt(-2.0), -2);
      expect(shape.integralInt(0.0), 0);
      expect(shape.integralInt(-0.0), 0);
    });

    test('rejects fractional, non-finite and non-numeric values', () {
      expect(() => shape.integralInt(2.5), throwsShapeError);
      expect(() => shape.integralInt(-0.5), throwsShapeError);
      expect(() => shape.integralInt(double.nan), throwsShapeError);
      expect(() => shape.integralInt(double.infinity), throwsShapeError);
      expect(
        () => shape.integralInt(double.negativeInfinity),
        throwsShapeError,
      );
      expect(() => shape.integralInt(null), throwsShapeError);
      expect(() => shape.integralInt('3'), throwsShapeError);
      expect(() => shape.integralInt(''), throwsShapeError);
      expect(() => shape.integralInt(true), throwsShapeError);
    });
  });

  group('nonNegativeInt', () {
    test('returns zero and positive ints', () {
      expect(shape.nonNegativeInt(0), 0);
      expect(shape.nonNegativeInt(5), 5);
    });

    test('rejects negatives, doubles and non-numbers', () {
      expect(() => shape.nonNegativeInt(-1), throwsShapeError);
      expect(() => shape.nonNegativeInt(3.0), throwsShapeError);
      expect(() => shape.nonNegativeInt(0.0), throwsShapeError);
      expect(() => shape.nonNegativeInt(2.5), throwsShapeError);
      expect(() => shape.nonNegativeInt(double.nan), throwsShapeError);
      expect(() => shape.nonNegativeInt(null), throwsShapeError);
      expect(() => shape.nonNegativeInt('0'), throwsShapeError);
      expect(() => shape.nonNegativeInt(''), throwsShapeError);
    });
  });

  group('nonNegativeIntegralInt', () {
    test('returns zero, positive ints and integral doubles', () {
      expect(shape.nonNegativeIntegralInt(0), 0);
      expect(shape.nonNegativeIntegralInt(5), 5);
      expect(shape.nonNegativeIntegralInt(3.0), 3);
      expect(shape.nonNegativeIntegralInt(0.0), 0);
    });

    test('rejects negatives, fractional, non-finite and non-numbers', () {
      expect(() => shape.nonNegativeIntegralInt(-1), throwsShapeError);
      expect(() => shape.nonNegativeIntegralInt(-1.0), throwsShapeError);
      expect(() => shape.nonNegativeIntegralInt(2.5), throwsShapeError);
      expect(() => shape.nonNegativeIntegralInt(double.nan), throwsShapeError);
      expect(
        () => shape.nonNegativeIntegralInt(double.infinity),
        throwsShapeError,
      );
      expect(() => shape.nonNegativeIntegralInt(null), throwsShapeError);
      expect(() => shape.nonNegativeIntegralInt('0'), throwsShapeError);
      expect(() => shape.nonNegativeIntegralInt(''), throwsShapeError);
    });
  });

  group('positiveInt', () {
    test('returns ints greater than zero', () {
      expect(shape.positiveInt(1), 1);
      expect(shape.positiveInt(42), 42);
    });

    test('rejects zero, negatives, doubles and non-numbers', () {
      expect(() => shape.positiveInt(0), throwsShapeError);
      expect(() => shape.positiveInt(-1), throwsShapeError);
      expect(() => shape.positiveInt(1.0), throwsShapeError);
      expect(() => shape.positiveInt(2.5), throwsShapeError);
      expect(() => shape.positiveInt(double.nan), throwsShapeError);
      expect(() => shape.positiveInt(null), throwsShapeError);
      expect(() => shape.positiveInt('1'), throwsShapeError);
      expect(() => shape.positiveInt(''), throwsShapeError);
    });
  });

  group('dateTime', () {
    test('parses ISO-8601 text and keeps the parsed zone (no toLocal)', () {
      expect(
        shape.dateTime('2026-09-02T04:00:00Z'),
        DateTime.utc(2026, 9, 2, 4),
      );
      expect(shape.dateTime('2026-09-02T04:00:00Z').isUtc, isTrue);
      expect(
        shape.dateTime('2026-09-02T04:00:00+08:00'),
        DateTime.utc(2026, 9, 1, 20),
      );
      expect(shape.dateTime('2026-09-02'), DateTime(2026, 9, 2));
      expect(shape.dateTime('2026-09-02').isUtc, isFalse);
    });

    test('passes the Go zero time through; the sentinel is the caller\'s', () {
      expect(shape.dateTime('0001-01-01T00:00:00Z').year, 1);
    });

    test('rejects null, non-strings, empty, untrimmed and unparsable text', () {
      expect(() => shape.dateTime(null), throwsShapeError);
      expect(() => shape.dateTime(1725249600), throwsShapeError);
      expect(() => shape.dateTime(1725249600000), throwsShapeError);
      expect(() => shape.dateTime(1.5), throwsShapeError);
      expect(() => shape.dateTime(true), throwsShapeError);
      expect(() => shape.dateTime(<Object?>[]), throwsShapeError);
      expect(() => shape.dateTime(''), throwsShapeError);
      expect(() => shape.dateTime(' '), throwsShapeError);
      expect(() => shape.dateTime(' 2026-09-02T04:00:00Z'), throwsShapeError);
      expect(() => shape.dateTime('2026-09-02T04:00:00Z '), throwsShapeError);
      expect(() => shape.dateTime('yesterday'), throwsShapeError);
    });
  });

  group('guardShape', () {
    test('translates shape exceptions into protocol failures', () async {
      await expectLater(
        guardShape<String>('local-test-response', () async {
          return shape.string(null);
        }),
        throwsA(
          isA<ApiFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (failure) => failure.requestId,
                'requestId',
                'local-test-response',
              ),
        ),
      );
      expect(
        () => guardShapeSync<String>(
          'local-sync-response',
          () => shape.string(null),
        ),
        throwsA(
          isA<ApiFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                ApiFailureKind.protocol,
              )
              .having(
                (failure) => failure.requestId,
                'requestId',
                'local-sync-response',
              ),
        ),
      );
    });

    test('returns values and lets other exceptions pass through', () async {
      expect(await guardShape<int>('id', () async => 1), 1);
      expect(guardShapeSync<int>('id', () => 2), 2);
      await expectLater(
        guardShape<int>('id', () async => throw StateError('other')),
        throwsStateError,
      );
      expect(
        () => guardShapeSync<int>('id', () => throw StateError('other')),
        throwsStateError,
      );
    });
  });
}
