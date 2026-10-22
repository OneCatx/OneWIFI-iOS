import 'wifi_call_group.dart';

/// 从 Mihomo `GET /proxies` 抽出 `XX-WIFI` 国家选择器，
/// 并按「香港 / 美国 / 英国 / 德国 / 新西兰 / 其余」排序。
abstract final class WifiSelectorCatalog {
  static const List<String> pinnedCountryOrder = <String>[
    'HK',
    'US',
    'GB',
    'DE',
    'NZ',
  ];

  static final RegExp _wifiInName = RegExp('WIFI', caseSensitive: false);
  static final RegExp _drWifi = RegExp(r'^DR[-_]?WIFI$', caseSensitive: false);
  static final RegExp _tagWifi = RegExp(
    r'^TAG[-_]?WIFI$',
    caseSensitive: false,
  );
  static final RegExp _countryWifi = RegExp(
    r'\b([A-Za-z]{2})-WIFI\b',
    caseSensitive: false,
  );

  static List<WifiCallGroup> fromProxies(Map<String, Object?> proxies) {
    final alias = _aliasIndex(proxies);
    final groups = <WifiCallGroup>[];
    for (final entry in proxies.entries) {
      final group = _parseSelector(entry.key, entry.value, proxies, alias);
      if (group != null) groups.add(group);
    }
    groups.sort(_compareGroups);
    return List<WifiCallGroup>.unmodifiable(groups);
  }

  static bool isWifiProxyGroup(String name) {
    if (name.isEmpty || !_wifiInName.hasMatch(name)) return false;
    if (_drWifi.hasMatch(name) || _tagWifi.hasMatch(name)) return false;
    return true;
  }

  static String? countryCodeOf(String groupName) {
    final match = _countryWifi.firstMatch(groupName.trim());
    if (match == null) return null;
    final code = match.group(1)!.toUpperCase();
    if (!_countryNames.containsKey(code) &&
        !_countryNames.containsKey(_canonicalPinCode(code))) {
      return null;
    }
    return code;
  }

  /// 卡片上用的组名：去掉 `📱 HK-WIFI` 前面的符号，API 仍用原名。
  static String visibleGroupName(String groupName) {
    return stripLeadingDecor(groupName);
  }

  /// 去掉节点/组名前面的 emoji、符号，保留中文和 ASCII。
  static String stripLeadingDecor(String name) {
    return name
        .replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '')
        .trim();
  }

  static bool isPinnedCountry(String code) {
    return pinnedCountryOrder.contains(_canonicalPinCode(code.toUpperCase()));
  }

  static List<WifiCallGroup> pinnedOf(List<WifiCallGroup> groups) {
    return pinnedBy(groups, pinnedCountryOrder);
  }

  static List<WifiCallGroup> moreOf(List<WifiCallGroup> groups) {
    return moreBy(groups, pinnedCountryOrder);
  }

  /// 一级菜单按 [pins] 的顺序排。不在名单里的进「更多」。
  static List<WifiCallGroup> pinnedBy(
    List<WifiCallGroup> groups,
    List<String> pins,
  ) {
    final index = <String, int>{
      for (var i = 0; i < pins.length; i++)
        _canonicalPinCode(pins[i].toUpperCase()): i,
    };
    final pinned = <WifiCallGroup>[
      for (final group in groups)
        if (index.containsKey(_canonicalPinCode(group.countryCode.toUpperCase())))
          group,
    ];
    pinned.sort((left, right) {
      final leftIndex =
          index[_canonicalPinCode(left.countryCode.toUpperCase())]!;
      final rightIndex =
          index[_canonicalPinCode(right.countryCode.toUpperCase())]!;
      return leftIndex.compareTo(rightIndex);
    });
    return pinned;
  }

  static List<WifiCallGroup> moreBy(
    List<WifiCallGroup> groups,
    List<String> pins,
  ) {
    final shown = pinnedBy(groups, pins).map((group) => group.groupName).toSet();
    return <WifiCallGroup>[
      for (final group in groups)
        if (!shown.contains(group.groupName)) group,
    ];
  }

  static String countryDisplayName(String code) {
    final key = code.toUpperCase();
    return _countryNames[key] ?? _countryNames[_canonicalPinCode(key)] ?? key;
  }

  static String flagEmoji(String code) {
    final iso = _canonicalPinCode(code.toUpperCase());
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(iso)) return '🌐';
    return String.fromCharCodes(<int>[
      0x1F1E6 + iso.codeUnitAt(0) - 0x41,
      0x1F1E6 + iso.codeUnitAt(1) - 0x41,
    ]);
  }

  static WifiCallGroup? _parseSelector(
    String name,
    Object? raw,
    Map<String, Object?> proxies,
    Map<String, String> alias,
  ) {
    if (!isWifiProxyGroup(name)) return null;
    if (raw is! Map<Object?, Object?>) return null;
    if (!_isSelectorType(raw['type'])) return null;
    final country = countryCodeOf(name);
    if (country == null) return null;

    final now = raw['now'] is String ? (raw['now'] as String) : '';
    final all = _stringList(raw['all']);
    final nodes = <WifiCallNode>[
      for (final nodeName in all)
        _nodeOf(nodeName, _resolveProxy(proxies, alias, nodeName)),
    ];
    final alive = nodes.where((node) => node.alive).length;
    return WifiCallGroup(
      groupName: name,
      countryCode: country,
      countryName: countryDisplayName(country),
      flagEmoji: flagEmoji(country),
      now: now,
      aliveCount: alive,
      totalCount: nodes.length,
      nodes: List<WifiCallNode>.unmodifiable(nodes),
    );
  }

  static Map<String, String> _aliasIndex(Map<String, Object?> proxies) {
    final alias = <String, String>{};
    for (final key in proxies.keys) {
      final stripped = _normalizeName(key);
      if (stripped.isEmpty) continue;
      final current = alias[stripped];
      if (current == null || (key == stripped && current != stripped)) {
        alias[stripped] = key;
      }
    }
    return alias;
  }

  static ({String key, Object? raw}) _resolveProxy(
    Map<String, Object?> proxies,
    Map<String, String> alias,
    String name,
  ) {
    if (proxies.containsKey(name)) {
      return (key: name, raw: proxies[name]);
    }
    final stripped = _normalizeName(name);
    if (proxies.containsKey(stripped)) {
      return (key: stripped, raw: proxies[stripped]);
    }
    final aliased = alias[stripped];
    if (aliased != null && proxies.containsKey(aliased)) {
      return (key: aliased, raw: proxies[aliased]);
    }
    return (key: stripped.isEmpty ? name : stripped, raw: null);
  }

  static WifiCallNode _nodeOf(
    String name,
    ({String key, Object? raw}) resolved,
  ) {
    final raw = resolved.raw;
    if (raw is! Map) {
      // 对不上 leaf 名时不当超时：订阅里 all 常带旗标、map key 不带。
      return WifiCallNode(name: name, alive: true, probeName: resolved.key);
    }
    final fields = Map<Object?, Object?>.from(raw);
    final type = fields['type'] is String
        ? (fields['type'] as String).toLowerCase()
        : '';
    final delay = _delayOf(fields);
    final aliveFlag = _aliveFlagOf(fields);
    final bool alive;
    if (type == 'direct' || type == 'reject' || type == 'compatible') {
      alive = aliveFlag != false;
    } else {
      // Mihomo 的 alive/history 来自 HTTP generate_204，WiFi Call 叶子经常是 0。
      // 目录里不当超时；只有现场 delay API 明确超时才标红。
      alive = true;
    }
    return WifiCallNode(
      name: name,
      alive: alive,
      delayMs: delay,
      probeName: resolved.key,
      delayProbed: delay > 0,
    );
  }

  static String _normalizeName(String name) {
    return stripLeadingDecor(name).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool sameProxyName(String left, String right) {
    return _normalizeName(left) == _normalizeName(right);
  }

  static Object? _aliveFlagOf(Map<Object?, Object?> raw) {
    if (raw['alive'] is bool) return raw['alive'];
    final extra = raw['extra'];
    if (extra is Map && extra['alive'] is bool) {
      return extra['alive'];
    }
    return raw['alive'];
  }

  static int _delayOf(Map<Object?, Object?> raw) {
    final top = _lastDelayMs(raw['history']);
    if (top > 0) return top;
    final extra = raw['extra'];
    if (extra is Map) {
      return _lastDelayMs(extra['history']);
    }
    return 0;
  }

  static int _lastDelayMs(Object? history) {
    if (history is! List || history.isEmpty) return 0;
    final last = history.last;
    if (last is! Map) return 0;
    final delay = last['delay'];
    if (delay is int) return delay < 0 ? 0 : delay;
    if (delay is double && delay.isFinite) {
      final value = delay.round();
      return value < 0 ? 0 : value;
    }
    return 0;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List<Object?>) return const <String>[];
    final names = <String>[];
    for (final item in value) {
      if (item is String && item.isNotEmpty) names.add(item);
    }
    return names;
  }

  static bool _isSelectorType(Object? type) {
    if (type is! String) return false;
    return type.toLowerCase() == 'selector';
  }

  static int _compareGroups(WifiCallGroup left, WifiCallGroup right) {
    final byPin = _pinIndex(
      left.countryCode,
    ).compareTo(_pinIndex(right.countryCode));
    if (byPin != 0) return byPin;
    final byCode = left.countryCode.compareTo(right.countryCode);
    if (byCode != 0) return byCode;
    return left.groupName.compareTo(right.groupName);
  }

  static int _pinIndex(String code) {
    final index = pinnedCountryOrder.indexOf(_canonicalPinCode(code));
    return index < 0 ? pinnedCountryOrder.length : index;
  }

  static String _canonicalPinCode(String code) => code == 'UK' ? 'GB' : code;
}

const Map<String, String> _countryNames = <String, String>{
  'HK': '香港',
  'US': '美国',
  'GB': '英国',
  'UK': '英国',
  'DE': '德国',
  'NZ': '新西兰',
  'JP': '日本',
  'SG': '新加坡',
  'KR': '韩国',
  'TW': '台湾',
  'MO': '澳门',
  'CN': '中国',
  'AU': '澳大利亚',
  'CA': '加拿大',
  'FR': '法国',
  'NL': '荷兰',
  'IT': '意大利',
  'ES': '西班牙',
  'PT': '葡萄牙',
  'IE': '爱尔兰',
  'CH': '瑞士',
  'AT': '奥地利',
  'BE': '比利时',
  'SE': '瑞典',
  'NO': '挪威',
  'FI': '芬兰',
  'DK': '丹麦',
  'PL': '波兰',
  'CZ': '捷克',
  'AE': '阿联酋',
  'SA': '沙特阿拉伯',
  'IL': '以色列',
  'IN': '印度',
  'ID': '印度尼西亚',
  'MY': '马来西亚',
  'TH': '泰国',
  'VN': '越南',
  'PH': '菲律宾',
  'BR': '巴西',
  'MX': '墨西哥',
  'AR': '阿根廷',
  'RU': '俄罗斯',
  'TR': '土耳其',
  'ZA': '南非',
};
