import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/esim/domain/lpa_smdp_preview.dart';

final LpaSmdpCatalog _fixture = LpaSmdpCatalog.fromJson(<String, Object?>{
  'hosts': <String, Object?>{
    'rsp.example.com': <String, Object?>{
      'c': <String>['JP'],
      'o': <String>['Example Mobile'],
      'r': 40960,
      'n': 40960,
      'x': 40960,
      'e': <String, Object?>{'89049032': 41175, '89033023': 36086},
    },
    'wholesale.example.com': <String, Object?>{
      'c': <String>['JP', 'KR', 'US', 'GB'],
      'o': <String>['Alpha', 'Beta'],
      'k': 12,
      'r': 50000,
      'n': 20000,
      'x': 90000,
      'e': <String, Object?>{'89049032': 52000},
    },
  },
});

void main() {
  test(
    'does not invent a country from an empty or host-less activation code',
    () {
      expect(previewLpaActivation('', catalog: _fixture), isNull);
      expect(previewLpaActivation('LPA:1\$', catalog: _fixture), isNull);
    },
  );

  test(
    'looks up country and EUM-specific size from the SM-DP+ host before download',
    () {
      final preview = previewLpaActivation(
        'LPA:1\$rsp.example.com\$MATCH-1',
        eid: '89049032000000000000000000000002',
        catalog: _fixture,
      );
      expect(preview, isNotNull);
      expect(preview!.known, isTrue);
      expect(preview.countries.single.name, '日本');
      expect(preview.countries.single.flag, '🇯🇵');
      expect(preview.operators.single, 'Example Mobile');
      expect(preview.sizeBytes, 41175);
      expect(preview.matchedEum, '89049032');
      expect(preview.sizeRanged, isFalse);
      expect(formatSmdpPreview(preview)?.size, '约 40.2 KB');
    },
  );

  test('falls back to a size range on a shared wholesale SM-DP+', () {
    final preview = lookupSmdpPreview(
      'wholesale.example.com',
      eid: 'unknown',
      catalog: _fixture,
    );
    expect(preview?.sizeRanged, isTrue);
    expect(preview?.countries, hasLength(4));
    final text = formatSmdpPreview(preview);
    expect(text?.title, contains('等 4 地'));
    expect(text?.detail, contains('12 家'));
    expect(text?.size, contains('19.5 KB–87.9 KB'));
  });

  test('warns when the estimate is larger than free NVRAM', () {
    final preview = lookupSmdpPreview(
      'rsp.example.com',
      eid: '8903302300000001',
      freeNvramBytes: 10000,
      catalog: _fixture,
    );
    expect(preview?.sizeBytes, 36086);
    expect(preview?.spaceWarning, isTrue);
    expect(formatSmdpPreview(preview)?.warning, contains('可用空间'));
  });

  test('marks an unknown SM-DP+ instead of guessing a country', () {
    final preview = previewLpaActivation(
      '1\$no-such-smdp.invalid\$abc',
      catalog: _fixture,
    );
    expect(preview?.known, isFalse);
    expect(preview?.host, 'no-such-smdp.invalid');
    expect(formatSmdpPreview(preview)?.title, contains('未收录'));
  });

  test('normalizes host case, trailing dot and port for catalog lookup', () {
    expect(
      lookupSmdpPreview('RSP.EXAMPLE.COM.', catalog: _fixture)?.known,
      isTrue,
    );
    expect(
      lookupSmdpPreview('rsp.example.com:443', catalog: _fixture)?.known,
      isTrue,
    );
    expect(
      lookupSmdpPreview(
        'https://RSP.EXAMPLE.COM/path',
        catalog: _fixture,
      )?.host,
      'rsp.example.com',
    );
  });

  test(
    'recognizes a real Nekoko sample host from the compact community table',
    () {
      final catalog = LpaSmdpCatalog.fromJson(
        jsonDecode(
          File('assets/esim/lpa_smdp_preview.db.json').readAsStringSync(),
        ),
      );
      expect(catalog.license, contains('MIT Copyright (c) 2026 Nekoko'));
      final preview = previewLpaActivation(
        'LPA:1\$sm-v4-018-gra-gtm.pr.go-esim.com\$abc',
        eid: '8904903200000002',
        catalog: catalog,
      );
      expect(preview?.known, isTrue);
      expect(preview?.countries.single.iso, 'GR');
      expect(preview?.countries.single.name, '希腊');
      expect(preview?.operators.single, 'Vodafone GR');
      expect(preview?.sizeBytes, 60352);
      expect(formatProfileBytes(preview!.sizeBytes), '58.9 KB');
    },
  );

  test(
    'PERF-P5: loadBundled with explicit bundle bypasses process cache',
    () async {
      final first = _CountingAssetBundle(
        File('assets/esim/lpa_smdp_preview.db.json').readAsStringSync(),
      );
      final second = _CountingAssetBundle(
        File('assets/esim/lpa_smdp_preview.db.json').readAsStringSync(),
      );
      final a = await LpaSmdpCatalog.loadBundled(bundle: first);
      final b = await LpaSmdpCatalog.loadBundled(bundle: second);
      expect(first.loadStringCount, 1);
      expect(second.loadStringCount, 1);
      expect(a.hosts.length, b.hosts.length);
      expect(identical(a, b), isFalse);
    },
  );

  test(
    'PERF-P5: default loadBundled memoizes after first successful decode',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      LpaSmdpCatalog.debugResetBundledCacheForTest();
      final first = await LpaSmdpCatalog.loadBundled();
      final second = await LpaSmdpCatalog.loadBundled();
      expect(identical(first, second), isTrue);
      expect(first.hosts, isNotEmpty);
      LpaSmdpCatalog.debugResetBundledCacheForTest();
    },
  );
}

final class _CountingAssetBundle extends CachingAssetBundle {
  _CountingAssetBundle(this._text);

  final String _text;
  int loadStringCount = 0;

  @override
  Future<ByteData> load(String key) async {
    throw UnsupportedError('load not used');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    loadStringCount += 1;
    expect(key, kLpaSmdpPreviewAsset);
    return _text;
  }
}
