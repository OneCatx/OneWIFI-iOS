import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/config/base_url.dart';
import 'package:onewifi_android/core/config/base_url_policy.dart';

void main() {
  group('BaseUrlPolicy constants', () {
    test('keeps the client 6699 default separate from backend 6688 info', () {
      expect(
        BaseUrlPolicy.defaultOrigin,
        Uri.parse('http://192.168.1.88:6699'),
      );
      expect(BaseUrlPolicy.backendDefaultListen, '0.0.0.0:6688');
      expect(
        BaseUrlPolicy.defaultOrigin.port,
        isNot(Uri.parse('http://0.0.0.0:6688').port),
      );
    });
  });

  group('BaseUrlPolicy.parseAndValidate', () {
    test('normalizes whitespace host case root slash and default port', () {
      expect(
        BaseUrlPolicy.parseAndValidate('  HTTPS://Example.COM:443/  '),
        Uri.parse('https://example.com'),
      );
      expect(
        BaseUrl.parse(' http://192.168.1.88:6699/ ').origin,
        BaseUrlPolicy.defaultOrigin,
      );
    });

    test('accepts HTTPS origins', () {
      expect(
        BaseUrlPolicy.parseAndValidate('https://api.example.test:8443'),
        Uri.parse('https://api.example.test:8443'),
      );
    });

    test('accepts loopback and private IP literal HTTP origins', () {
      final allowed = <String>[
        'http://127.0.0.1:6699',
        'http://10.42.0.1',
        'http://172.16.0.1:8080',
        'http://172.31.255.254',
        'http://192.168.1.88:6699',
        'http://[::1]:6699',
        'http://[fd12:3456::1]:6699',
      ];

      for (final input in allowed) {
        expect(
          BaseUrlPolicy.parseAndValidate(input),
          Uri.parse(input),
          reason: input,
        );
      }
    });

    test('accepts public IP and hostname HTTP origins', () {
      final allowed = <String>[
        'http://8.8.8.8:6688',
        'http://172.32.0.1:6688',
        'http://example.com:6688',
        'http://localhost:6699',
      ];

      for (final input in allowed) {
        expect(
          BaseUrlPolicy.parseAndValidate(input),
          Uri.parse(input),
          reason: input,
        );
      }
    });

    test('rejects path query fragment and userinfo', () {
      final rejected = <String>[
        'https://example.com/api',
        'https://example.com?token=value',
        'https://example.com#fragment',
        'https://user:password@example.com',
      ];

      for (final input in rejected) {
        expect(
          () => BaseUrlPolicy.parseAndValidate(input),
          throwsFormatException,
          reason: input,
        );
      }
    });

    test('rejects empty malformed and unsupported origins', () {
      final rejected = <String>['', 'not a URI', 'ftp://192.168.1.88'];

      for (final input in rejected) {
        expect(
          () => BaseUrlPolicy.parseAndValidate(input),
          throwsFormatException,
          reason: input,
        );
      }
    });
  });

  group('BaseUrlPolicy.fromHostAndPort', () {
    test('builds a private HTTP origin from host and port', () {
      expect(
        BaseUrlPolicy.fromHostAndPort(host: ' 192.168.10.20 ', port: '6688'),
        Uri.parse('http://192.168.10.20:6688'),
      );
    });

    test('builds a public HTTPS origin when https is selected', () {
      expect(
        BaseUrlPolicy.fromHostAndPort(
          host: 'api.example.test',
          port: '8443',
          https: true,
        ),
        Uri.parse('https://api.example.test:8443'),
      );
    });

    test('accepts public HTTP host and port combinations', () {
      expect(
        BaseUrlPolicy.fromHostAndPort(host: 'example.com', port: '6688'),
        Uri.parse('http://example.com:6688'),
      );
    });

    test('rejects missing or out-of-range ports', () {
      expect(
        () => BaseUrlPolicy.fromHostAndPort(host: '192.168.1.88', port: ''),
        throwsFormatException,
      );
      expect(
        () =>
            BaseUrlPolicy.fromHostAndPort(host: '192.168.1.88', port: '70000'),
        throwsFormatException,
      );
    });
  });

  group('BaseUrlPolicy.split', () {
    test('returns host port and https flag for an origin', () {
      expect(BaseUrlPolicy.split(Uri.parse('http://192.168.1.88:6699')), (
        host: '192.168.1.88',
        port: '6699',
        https: false,
      ));
      expect(BaseUrlPolicy.split(Uri.parse('https://api.example.test')), (
        host: 'api.example.test',
        port: '443',
        https: true,
      ));
    });

    test('flags public HTTP as cleartext risk', () {
      expect(
        BaseUrlPolicy.isPublicCleartext(Uri.parse('http://8.8.8.8:6688')),
        isTrue,
      );
      expect(
        BaseUrlPolicy.isPublicCleartext(Uri.parse('http://192.168.1.88:6699')),
        isFalse,
      );
    });

    test('localhost is loopback, not public cleartext', () {
      expect(
        BaseUrlPolicy.isPublicCleartext(Uri.parse('http://localhost:6688')),
        isFalse,
      );
      expect(
        BaseUrlPolicy.isPublicCleartext(Uri.parse('http://foo.localhost:6688')),
        isFalse,
      );
    });

    test('link-local addresses are not public cleartext', () {
      expect(
        BaseUrlPolicy.isPublicCleartext(Uri.parse('http://169.254.10.20:6688')),
        isFalse,
      );
      expect(
        BaseUrlPolicy.isPublicCleartext(Uri.parse('http://[fe80::1]:6688')),
        isFalse,
      );
    });
  });
}
