import 'wifi_call_connection.dart';
import 'wifi_selector_catalog.dart';

/// 把 Mihomo 连接表收成代理页要用的两档列表。
abstract final class WifiConnectionCatalog {
  static const int previewLimit = 5;
  static const int sheetLimit = 10;

  static List<WifiCallConnection> fromConnections(
    Map<String, Object?> root, {
    List<WifiCallConnection>? previous,
    DateTime? previousAt,
    DateTime? now,
  }) {
    final raw = root['connections'];
    if (raw is! List<Object?>) return const <WifiCallConnection>[];
    final prevById = <String, WifiCallConnection>{
      for (final row in previous ?? const <WifiCallConnection>[]) row.id: row,
    };
    final elapsed = (previousAt != null && now != null)
        ? now.difference(previousAt)
        : Duration.zero;
    final rows = <WifiCallConnection>[];
    for (final item in raw) {
      if (item is! Map<Object?, Object?>) continue;
      final row = _rowOf(item, previous: prevById, elapsed: elapsed);
      if (row == null || !_isWifiSession(row)) continue;
      rows.add(row);
    }
    return List<WifiCallConnection>.unmodifiable(rows);
  }

  static List<WifiCallConnection> previewOf(List<WifiCallConnection> rows) {
    final wifi = wifiSessionsOf(rows);
    if (wifi.length <= previewLimit) return wifi;
    return List<WifiCallConnection>.unmodifiable(wifi.take(previewLimit));
  }

  static List<WifiCallConnection> sheetOf(List<WifiCallConnection> rows) {
    final wifi = wifiSessionsOf(rows);
    if (wifi.length <= sheetLimit) return wifi;
    return List<WifiCallConnection>.unmodifiable(wifi.take(sheetLimit));
  }

  static List<WifiCallConnection> wifiSessionsOf(
    List<WifiCallConnection> rows,
  ) {
    return List<WifiCallConnection>.unmodifiable(<WifiCallConnection>[
      for (final row in rows)
        if (_isWifiSession(row)) row,
    ]);
  }

  static bool _isWifiSession(WifiCallConnection row) {
    return !row.direct && row.countryCode != null;
  }

  static String formatRate(int bps) {
    if (bps <= 0) return '0 B/s';
    if (bps < 1024) return '$bps B/s';
    const kb = 1024.0;
    final asKb = bps / kb;
    if (asKb < 1024) return '${asKb.toStringAsFixed(1)} KB/s';
    final asMb = asKb / kb;
    if (asMb < 1024) return '${asMb.toStringAsFixed(1)} MB/s';
    return '${(asMb / kb).toStringAsFixed(1)} GB/s';
  }

  /// ePDG 长域名收成 `ePDG MCC/MNC`；代理链只留节点短名。
  static String compactHost(String host) {
    final name = _hostnameOf(host);
    final mccMnc = RegExp(
      r'^epdg\.epc\.mnc(\d+)\.mcc(\d+)\.',
      caseSensitive: false,
    ).firstMatch(name);
    if (mccMnc != null) return 'ePDG ${mccMnc[2]}/${mccMnc[1]}';
    final carrier = RegExp(
      r'^epdg\.epc\.([^.:]+)',
      caseSensitive: false,
    ).firstMatch(name);
    if (carrier != null) return 'ePDG ${carrier[1]}';
    if (RegExp(r'^epdg\.', caseSensitive: false).hasMatch(name)) return 'ePDG';
    return host;
  }

  static String compactChain(String chainLabel) {
    const sep = ' → ';
    var label = chainLabel;
    final index = chainLabel.indexOf(sep);
    if (index > 0) {
      final left = chainLabel.substring(0, index);
      final right = chainLabel.substring(index + sep.length);
      if (right.isNotEmpty && WifiSelectorCatalog.countryCodeOf(left) != null) {
        label = right;
      }
    }
    return compactNodeName(label);
  }

  /// `Cyber | 英国 1.5×` → `英国 1.5×`。
  static String compactNodeName(String name) {
    final stripped = WifiSelectorCatalog.stripLeadingDecor(name);
    final bar = stripped.indexOf(' | ');
    if (bar <= 0 || bar + 3 >= stripped.length) return stripped;
    return stripped.substring(bar + 3).trim();
  }

  static String _hostnameOf(String host) {
    if (host.startsWith('[')) {
      final end = host.indexOf(']');
      if (end > 0) return host.substring(1, end);
    }
    final colon = host.lastIndexOf(':');
    if (colon <= 0) return host;
    return host.substring(0, colon);
  }

  static WifiCallConnection? _rowOf(
    Map<Object?, Object?> raw, {
    required Map<String, WifiCallConnection> previous,
    required Duration elapsed,
  }) {
    final id = _idOf(raw['id']);
    if (id.isEmpty) return null;
    final metadata = raw['metadata'];
    final meta = metadata is Map<Object?, Object?> ? metadata : null;
    final host = _hostPort(
      _text(meta?['host']).isNotEmpty
          ? _text(meta?['host'])
          : _text(meta?['destinationIP']),
      _text(meta?['destinationPort']),
    );
    if (host.isEmpty) return null;
    final chains = _stringList(raw['chains']);
    final country = _countryOf(chains);
    final chainLabel = _chainLabel(chains);
    final direct = chainLabel == 'DIRECT';
    final downloadBytes = _nonNegative(raw['download']);
    final uploadBytes = _nonNegative(raw['upload']);
    final liveDown = _optionalNonNegative(raw['downloadSpeed']);
    final liveUp = _optionalNonNegative(raw['uploadSpeed']);
    final live = liveDown != null || liveUp != null;
    var downloadBps = liveDown ?? 0;
    var uploadBps = liveUp ?? 0;
    if (!live) {
      final prev = previous[id];
      if (prev != null) {
        downloadBps = _bps(downloadBytes - prev.downloadBytes, elapsed);
        uploadBps = _bps(uploadBytes - prev.uploadBytes, elapsed);
      }
    }
    return WifiCallConnection(
      id: id,
      host: host,
      chainLabel: chainLabel,
      countryCode: country,
      direct: direct,
      downloadBytes: downloadBytes,
      uploadBytes: uploadBytes,
      downloadBps: downloadBps,
      uploadBps: uploadBps,
      liveRate: live,
    );
  }

  static String? _countryOf(List<String> chains) {
    for (final hop in chains) {
      final code = WifiSelectorCatalog.countryCodeOf(hop);
      if (code != null) return code;
    }
    return null;
  }

  static String _chainLabel(List<String> chains) {
    final hops = <String>[];
    for (final hop in chains) {
      final visible = WifiSelectorCatalog.stripLeadingDecor(hop);
      if (visible.isEmpty) continue;
      if (visible.toUpperCase() == 'GLOBAL') continue;
      hops.add(visible);
    }
    if (hops.isEmpty) return 'DIRECT';
    String? wifi;
    String? node;
    for (final hop in hops) {
      if (WifiSelectorCatalog.countryCodeOf(hop) != null) {
        wifi ??= hop;
      } else if (hop.toUpperCase() != 'DIRECT') {
        node ??= hop;
      }
    }
    if (wifi != null && node != null) return '$wifi → $node';
    if (wifi != null) return wifi;
    if (hops.length == 1) return hops.first;
    return '${hops.last} → ${hops.first}';
  }

  static String _hostPort(String host, String port) {
    if (host.isEmpty) return port;
    if (port.isEmpty) return host;
    if (host.contains(':') && !host.startsWith('[')) {
      return '[$host]:$port';
    }
    return '$host:$port';
  }

  static String _idOf(Object? value) {
    if (value is String) return value.trim();
    if (value is int) return '$value';
    return '';
  }

  static String _text(Object? value) {
    if (value is String) return value.trim();
    if (value is int) return '$value';
    return '';
  }

  static List<String> _stringList(Object? value) {
    if (value is! List<Object?>) return const <String>[];
    return <String>[
      for (final item in value)
        if (item is String && item.trim().isNotEmpty) item,
    ];
  }

  static int _nonNegative(Object? value) {
    final parsed = _optionalNonNegative(value);
    return parsed ?? 0;
  }

  static int? _optionalNonNegative(Object? value) {
    if (value is int) return value < 0 ? 0 : value;
    if (value is double && value.isFinite) {
      final rounded = value.round();
      return rounded < 0 ? 0 : rounded;
    }
    return null;
  }

  static int _bps(int delta, Duration elapsed) {
    if (delta <= 0 || elapsed.inMicroseconds <= 0) return 0;
    return (delta * 1000000 / elapsed.inMicroseconds).round();
  }
}
