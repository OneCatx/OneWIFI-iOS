import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_selector_catalog.dart';

void main() {
  test('keeps WIFI Selector groups and pins HK US UK DE NZ first', () {
    final groups = WifiSelectorCatalog.fromProxies(<String, Object?>{
      'GLOBAL': _selector(
        'HK-WIFI Selector',
        all: <String>['HK-WIFI Selector'],
      ),
      'TAG-WIFI': _selector('ignored', all: <String>['ignored']),
      'DR-WIFI': <String, Object?>{
        'type': 'URLTest',
        'now': 'x',
        'all': <Object?>['x'],
      },
      'HK-WIFI': <String, Object?>{
        'type': 'URLTest',
        'now': 'leaf',
        'all': <Object?>['leaf'],
      },
      'JP-WIFI Selector': _selector('jp-now', all: <String>['jp-1']),
      'HK-WIFI Selector': _selector(
        'TAG | 香港 家宽 01',
        all: <String>['TAG | 香港 家宽 01', 'dead-hk'],
      ),
      'US-WIFI Selector': _selector('us-now', all: <String>['us-1']),
      'UK-WIFI Selector': _selector('uk-now', all: <String>['uk-1']),
      'DE-WIFI Selector': _selector('de-now', all: <String>['de-1']),
      'NZ-WIFI Selector': _selector('nz-now', all: <String>['nz-1']),
      'TAG | 香港 家宽 01': _leaf(delay: 80),
      'dead-hk': _leaf(delay: 0, alive: false),
      'jp-1': _leaf(delay: 40),
      'us-1': _leaf(delay: 120),
      'uk-1': _leaf(delay: 90),
      'de-1': _leaf(delay: 70),
      'nz-1': _leaf(delay: 110),
    });

    expect(groups.map((group) => group.countryCode).toList(), <String>[
      'HK',
      'US',
      'UK',
      'DE',
      'NZ',
      'JP',
    ]);
    expect(groups.first.groupName, 'HK-WIFI Selector');
    expect(groups.first.countryName, '香港');
    expect(groups.first.flagEmoji, '🇭🇰');
    expect(groups.first.now, 'TAG | 香港 家宽 01');
    expect(groups.first.aliveCount, 2);
    expect(groups.first.totalCount, 2);
    expect(groups[2].countryName, '英国');
  });

  test(
    'reads emoji-prefixed XX-WIFI groups and keeps hidden country selectors',
    () {
      final groups = WifiSelectorCatalog.fromProxies(<String, Object?>{
        '📱 HK-WIFI': _selector(
          '🇭🇰 TAG | 香港 家宽 01',
          all: <String>['🇭🇰 TAG | 香港 家宽 01'],
        ),
        '📱 US-WIFI': _selector('us-now', all: <String>['us-1']),
        '📱 UK-WIFI': _selector('uk-now', all: <String>['uk-1']),
        '📱 DE-WIFI': _selector('de-now', all: <String>['de-1']),
        '📱 NZ-WIFI': _selector('nz-now', all: <String>['nz-1']),
        '📱 TW-WIFI': <String, Object?>{
          'type': 'Selector',
          'hidden': true,
          'now': 'tw-now',
          'all': <Object?>['tw-1'],
        },
        '📱 Bk-WIFI': _selector('bookmark', all: <String>['bookmark']),
        '📱 DR-WIFI': _selector('direct', all: <String>['direct']),
        '📱 TAG-WIFI': _selector('tag', all: <String>['tag']),
        '🇭🇰 TAG | 香港 家宽 01': _leaf(delay: 80),
        'us-1': _leaf(delay: 120),
        'uk-1': _leaf(delay: 90),
        'de-1': _leaf(delay: 70),
        'nz-1': _leaf(delay: 110),
        'tw-1': _leaf(delay: 50),
      });

      expect(groups.map((group) => group.countryCode).toList(), <String>[
        'HK',
        'US',
        'UK',
        'DE',
        'NZ',
        'TW',
      ]);
      expect(groups.first.groupName, '📱 HK-WIFI');
      expect(
        WifiSelectorCatalog.visibleGroupName(groups.first.groupName),
        'HK-WIFI',
      );
      expect(groups.first.countryName, '香港');
    },
  );

  test('drops names without a country prefix', () {
    final groups = WifiSelectorCatalog.fromProxies(<String, Object?>{
      'WIFI Selector': _selector('now', all: <String>['n']),
      'SG-WIFI Selector': _selector('sg-now', all: <String>['sg-1']),
      'sg-1': _leaf(delay: 10),
    });

    expect(groups.single.countryCode, 'SG');
    expect(groups.single.countryName, '新加坡');
  });

  test('keeps alive nodes without delay history', () {
    final groups = WifiSelectorCatalog.fromProxies(<String, Object?>{
      'HK-WIFI': _selector('home', all: <String>['home', 'dead', 'untested']),
      'home': _leaf(delay: 80),
      'dead': _leaf(delay: 0, alive: false),
      'untested': <String, Object?>{'type': 'Shadowsocks', 'alive': true},
    });

    expect(groups.single.aliveCount, 3);
    expect(groups.single.totalCount, 3);
    expect(groups.single.nodes.map((node) => node.alive).toList(), <bool>[
      true,
      true,
      true,
    ]);
    expect(groups.single.nodes.last.delayMs, 0);
  });

  test('maps flag-prefixed selector names onto undecorated leaves', () {
    final groups = WifiSelectorCatalog.fromProxies(<String, Object?>{
      'HK-WIFI': _selector(
        '🇭🇰 TAG | 香港 01',
        all: <String>['🇭🇰 TAG | 香港 01', '🇭🇰 TAG | 香港 02', 'missing-leaf'],
      ),
      'TAG | 香港 01': _leaf(delay: 80),
      'TAG | 香港 02': <String, Object?>{'type': 'Shadowsocks', 'alive': false},
    });

    expect(groups.single.aliveCount, 3);
    expect(groups.single.totalCount, 3);
    expect(groups.single.nodes.map((node) => node.alive).toList(), <bool>[
      true,
      true,
      true,
    ]);
    expect(groups.single.nodes.first.delayMs, 80);
    expect(groups.single.nodes.first.probeName, 'TAG | 香港 01');
    expect(groups.single.nodes[1].delayMs, 0);
  });

  test('HTTP delay history of 0 is not catalog-dead', () {
    final groups = WifiSelectorCatalog.fromProxies(<String, Object?>{
      'HK-WIFI': _selector(
        'home',
        all: <String>['home', 'dead', 'untested-false'],
      ),
      'home': _leaf(delay: 80),
      'dead': _leaf(delay: 0, alive: false),
      'untested-false': <String, Object?>{
        'type': 'Shadowsocks',
        'alive': false,
      },
    });

    expect(groups.single.nodes.map((node) => node.alive).toList(), <bool>[
      true,
      true,
      true,
    ]);
    expect(groups.single.nodes[1].delayFailed, isFalse);
    expect(groups.single.nodes[1].delayProbed, isFalse);
  });

  test('reads delay from extra.history', () {
    final groups = WifiSelectorCatalog.fromProxies(<String, Object?>{
      'US-WIFI': _selector('leaf', all: <String>['leaf']),
      'leaf': <String, Object?>{
        'type': 'Shadowsocks',
        'extra': <String, Object?>{
          'alive': true,
          'history': <Object?>[
            <String, Object?>{'delay': 42},
          ],
        },
      },
    });
    expect(groups.single.nodes.single.alive, isTrue);
    expect(groups.single.nodes.single.delayMs, 42);
  });

  test('reads delay from jsonDecode-shaped history maps', () {
    final decoded = jsonDecode(
      '{"type":"Shadowsocks","history":[{"delay":77.0}]}',
    );
    final groups = WifiSelectorCatalog.fromProxies(<String, Object?>{
      'US-WIFI': _selector('leaf', all: <String>['leaf']),
      'leaf': decoded as Object,
    });
    expect(groups.single.nodes.single.delayMs, 77);
  });
}

Map<String, Object?> _selector(String now, {required List<String> all}) =>
    <String, Object?>{'type': 'Selector', 'now': now, 'all': all};

Map<String, Object?> _leaf({required int delay, bool alive = true}) =>
    <String, Object?>{
      'type': 'Shadowsocks',
      'alive': alive,
      'history': <Object?>[
        <String, Object?>{'delay': delay},
      ],
    };
