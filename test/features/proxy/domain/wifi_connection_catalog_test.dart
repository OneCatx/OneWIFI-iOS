import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_connection_catalog.dart';

void main() {
  test(
    'drops DIRECT and other non-WIFI links; preview and sheet keep any country',
    () {
      final rows = WifiConnectionCatalog.fromConnections(<String, Object?>{
        'connections': <Object?>[
          _conn(
            id: 'direct',
            host: '120.53.53.53',
            port: '443',
            chains: <String>['DIRECT'],
            download: 9999,
          ),
          _conn(
            id: 'jp',
            host: 'jp.example.test',
            port: '443',
            chains: <String>['node-jp', '📱 JP-WIFI'],
            download: 8888,
          ),
          for (var i = 0; i < 12; i++)
            _conn(
              id: 'us-$i',
              host: 'epdg.epc.att.net',
              port: '${500 + i}',
              chains: <String>['☠️自建USHOME', '📱 US-WIFI'],
              download: 1000 - i,
              upload: 10,
            ),
        ],
      });

      expect(rows.length, 13);
      expect(
        rows.every((row) => !row.direct && row.countryCode != null),
        isTrue,
      );
      expect(rows.first.chainLabel, 'JP-WIFI → node-jp');
      expect(rows[1].chainLabel, 'US-WIFI → 自建USHOME');
      expect(rows[1].host, 'epdg.epc.att.net:500');
      expect(
        WifiConnectionCatalog.previewOf(rows).map((row) => row.id).toList(),
        <String>['jp', 'us-0', 'us-1', 'us-2', 'us-3'],
      );
      final sheet = WifiConnectionCatalog.sheetOf(rows);
      expect(sheet.length, 10);
      expect(sheet.first.id, 'jp');
      expect(sheet.first.countryCode, 'JP');
      expect(sheet[1].countryCode, 'US');
    },
  );

  test('formats rates and fills B/s from byte deltas', () {
    expect(WifiConnectionCatalog.formatRate(0), '0 B/s');
    expect(WifiConnectionCatalog.formatRate(512), '512 B/s');
    expect(WifiConnectionCatalog.formatRate(1536), '1.5 KB/s');

    final first = WifiConnectionCatalog.fromConnections(_snapshot(100, 20));
    final next = WifiConnectionCatalog.fromConnections(
      _snapshot(1124, 20),
      previous: first,
      previousAt: DateTime.utc(2026, 9, 11, 12),
      now: DateTime.utc(2026, 9, 11, 12, 0, 1),
    );
    expect(next.single.downloadBps, 1024);
    expect(
      WifiConnectionCatalog.formatRate(next.single.downloadBps),
      '1.0 KB/s',
    );
  });

  test('compacts ePDG hosts and keeps the short node name', () {
    expect(
      WifiConnectionCatalog.compactHost(
        'epdg.epc.mnc030.mcc234.pub.3gppnetwork.org:500',
      ),
      'ePDG 234/030',
    );
    expect(
      WifiConnectionCatalog.compactHost('epdg.epc.att.net:500'),
      'ePDG att',
    );
    expect(
      WifiConnectionCatalog.compactChain('UK-WIFI → Cyber | 英国 1.5×'),
      '英国 1.5×',
    );
    expect(
      WifiConnectionCatalog.compactChain('NZ-WIFI → TAG | 新西兰 2×'),
      '新西兰 2×',
    );
    expect(WifiConnectionCatalog.compactChain('JP-WIFI → node-jp'), 'node-jp');
  });

  test('keeps live downloadSpeed from the API', () {
    final rows = WifiConnectionCatalog.fromConnections(<String, Object?>{
      'connections': <Object?>[
        _conn(
          id: 'live',
          host: 'epdg.epc.att.net',
          port: '500',
          chains: <String>['node', '📱 HK-WIFI'],
          download: 10,
          downloadSpeed: 2048,
          uploadSpeed: 0,
        ),
      ],
    });
    expect(rows.single.downloadBps, 2048);
    expect(rows.single.liveRate, isTrue);
  });
}

Map<String, Object?> _snapshot(int download, int upload) => <String, Object?>{
  'connections': <Object?>[
    _conn(
      id: 'us-0',
      host: 'epdg.epc.att.net',
      port: '500',
      chains: <String>['node', '📱 US-WIFI'],
      download: download,
      upload: upload,
    ),
  ],
};

Map<String, Object?> _conn({
  required String id,
  required String host,
  required String port,
  required List<String> chains,
  int download = 0,
  int upload = 0,
  int? downloadSpeed,
  int? uploadSpeed,
}) => <String, Object?>{
  'id': id,
  'download': download,
  'upload': upload,
  'downloadSpeed': ?downloadSpeed,
  'uploadSpeed': ?uploadSpeed,
  'chains': chains,
  'metadata': <String, Object?>{'host': host, 'destinationPort': port},
};
