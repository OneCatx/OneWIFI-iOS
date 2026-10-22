// SM-DP+ 下载前国家和体积提示。激活码本身不含这些字段。
// Nekoko LPA 的做法：用 SM-DP+ 主机名去对社区实测库
// （NekokoLPA2 data/reference_sizes_simple.json，MIT © 2026 Nekoko），
// 再按本卡 EID 前 8 位（EUM）取更接近的占用。
// 这不是连 SM-DP+ 拉包，只是本地对照。不要改 [parseLpaActivationCode] 的下载语义。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'lpa_activation.dart';

const String kLpaSmdpPreviewAsset = 'assets/esim/lpa_smdp_preview.db.json';

const Map<String, String> kSmdpCountryZh = <String, String>{
  'AD': '安道尔',
  'AE': '阿联酋',
  'AL': '阿尔巴尼亚',
  'AM': '亚美尼亚',
  'AO': '安哥拉',
  'AR': '阿根廷',
  'AT': '奥地利',
  'AU': '澳大利亚',
  'AW': '阿鲁巴',
  'AZ': '阿塞拜疆',
  'BA': '波黑',
  'BD': '孟加拉',
  'BE': '比利时',
  'BG': '保加利亚',
  'BH': '巴林',
  'BN': '文莱',
  'BO': '玻利维亚',
  'BQ': '荷属加勒比',
  'BR': '巴西',
  'BS': '巴哈马',
  'BY': '白俄罗斯',
  'BZ': '伯利兹',
  'CA': '加拿大',
  'CD': '刚果（金）',
  'CH': '瑞士',
  'CL': '智利',
  'CN': '中国',
  'CO': '哥伦比亚',
  'CR': '哥斯达黎加',
  'CV': '佛得角',
  'CY': '塞浦路斯',
  'CZ': '捷克',
  'DE': '德国',
  'DK': '丹麦',
  'DO': '多米尼加',
  'EC': '厄瓜多尔',
  'EE': '爱沙尼亚',
  'EG': '埃及',
  'ES': '西班牙',
  'FI': '芬兰',
  'FO': '法罗群岛',
  'FR': '法国',
  'GB': '英国',
  'GE': '格鲁吉亚',
  'GI': '直布罗陀',
  'GL': '格陵兰',
  'GM': '冈比亚',
  'GR': '希腊',
  'GY': '圭亚那',
  'HK': '香港',
  'HR': '克罗地亚',
  'HU': '匈牙利',
  'ID': '印尼',
  'IE': '爱尔兰',
  'IL': '以色列',
  'IN': '印度',
  'IQ': '伊拉克',
  'IS': '冰岛',
  'IT': '意大利',
  'JM': '牙买加',
  'JO': '约旦',
  'JP': '日本',
  'KE': '肯尼亚',
  'KG': '吉尔吉斯',
  'KH': '柬埔寨',
  'KM': '科摩罗',
  'KP': '朝鲜',
  'KR': '韩国',
  'KW': '科威特',
  'KZ': '哈萨克',
  'LA': '老挝',
  'LB': '黎巴嫩',
  'LI': '列支敦士登',
  'LK': '斯里兰卡',
  'LT': '立陶宛',
  'LU': '卢森堡',
  'LV': '拉脱维亚',
  'MA': '摩洛哥',
  'MD': '摩尔多瓦',
  'ME': '黑山',
  'MK': '北马其顿',
  'MM': '缅甸',
  'MN': '蒙古',
  'MO': '澳门',
  'MT': '马耳他',
  'MU': '毛里求斯',
  'MV': '马尔代夫',
  'MX': '墨西哥',
  'MY': '马来西亚',
  'NG': '尼日利亚',
  'NL': '荷兰',
  'NO': '挪威',
  'NP': '尼泊尔',
  'NZ': '新西兰',
  'OM': '阿曼',
  'PE': '秘鲁',
  'PF': '法属波利尼西亚',
  'PH': '菲律宾',
  'PK': '巴基斯坦',
  'PL': '波兰',
  'PT': '葡萄牙',
  'PW': '帕劳',
  'PY': '巴拉圭',
  'QA': '卡塔尔',
  'RO': '罗马尼亚',
  'RS': '塞尔维亚',
  'RU': '俄罗斯',
  'RW': '卢旺达',
  'SA': '沙特',
  'SC': '塞舌尔',
  'SE': '瑞典',
  'SG': '新加坡',
  'SI': '斯洛文尼亚',
  'SK': '斯洛伐克',
  'SV': '萨尔瓦多',
  'SY': '叙利亚',
  'TH': '泰国',
  'TJ': '塔吉克',
  'TN': '突尼斯',
  'TR': '土耳其',
  'TT': '特立尼达',
  'TW': '台湾',
  'TZ': '坦桑尼亚',
  'UA': '乌克兰',
  'UG': '乌干达',
  'US': '美国',
  'UY': '乌拉圭',
  'UZ': '乌兹别克',
  'VE': '委内瑞拉',
  'VN': '越南',
  'WS': '萨摩亚',
  'YT': '马约特',
  'ZA': '南非',
  'ZM': '赞比亚',
  'ZW': '津巴布韦',
};

final class SmdpCountry {
  const SmdpCountry({
    required this.iso,
    required this.name,
    required this.flag,
  });

  final String iso;
  final String name;
  final String flag;
}

final class SmdpPreview {
  const SmdpPreview({
    required this.known,
    required this.host,
    this.countries = const <SmdpCountry>[],
    this.operators = const <String>[],
    this.operatorTotal = 0,
    this.sizeBytes = 0,
    this.sizeMin = 0,
    this.sizeMax = 0,
    this.sizeRanged = false,
    this.matchedEum = '',
    this.spaceWarning = false,
  });

  final bool known;
  final String host;
  final List<SmdpCountry> countries;
  final List<String> operators;
  final int operatorTotal;
  final int sizeBytes;
  final int sizeMin;
  final int sizeMax;
  final bool sizeRanged;
  final String matchedEum;
  final bool spaceWarning;
}

final class SmdpPreviewCopy {
  const SmdpPreviewCopy({
    required this.title,
    required this.detail,
    required this.size,
    required this.warning,
  });

  final String title;
  final String detail;
  final String size;
  final String warning;
}

final class LpaSmdpHostRecord {
  const LpaSmdpHostRecord({
    required this.countries,
    required this.operators,
    required this.operatorHint,
    required this.typical,
    required this.min,
    required this.max,
    required this.eumSizes,
  });

  final List<String> countries;
  final List<String> operators;
  final int operatorHint;
  final double typical;
  final double min;
  final double max;
  final Map<String, int> eumSizes;

  factory LpaSmdpHostRecord.fromJson(Object? raw) {
    if (raw is! Map) {
      return const LpaSmdpHostRecord(
        countries: <String>[],
        operators: <String>[],
        operatorHint: 0,
        typical: 0,
        min: 0,
        max: 0,
        eumSizes: <String, int>{},
      );
    }
    final eum = <String, int>{};
    final eRaw = raw['e'];
    if (eRaw is Map) {
      for (final entry in eRaw.entries) {
        final bytes = _positiveInt(entry.value);
        if (bytes > 0) eum[entry.key.toString()] = bytes;
      }
    }
    return LpaSmdpHostRecord(
      countries: _stringList(raw['c']),
      operators: _stringList(
        raw['o'],
      ).where((item) => item.isNotEmpty).toList(),
      operatorHint: _positiveInt(raw['k']),
      typical: _finite(raw['r']),
      min: _finite(raw['n']),
      max: _finite(raw['x']),
      eumSizes: eum,
    );
  }
}

final class LpaSmdpCatalog {
  const LpaSmdpCatalog({
    required this.hosts,
    this.source = '',
    this.license = '',
  });

  final Map<String, LpaSmdpHostRecord> hosts;
  final String source;
  final String license;

  factory LpaSmdpCatalog.fromJson(Object? raw) {
    if (raw is! Map) {
      return const LpaSmdpCatalog(hosts: <String, LpaSmdpHostRecord>{});
    }
    final hostsRaw = raw['hosts'];
    final hosts = <String, LpaSmdpHostRecord>{};
    if (hostsRaw is Map) {
      for (final entry in hostsRaw.entries) {
        final host = normalizeSmdpHost(entry.key.toString());
        if (host.isEmpty) continue;
        hosts[host] = LpaSmdpHostRecord.fromJson(entry.value);
      }
    }
    return LpaSmdpCatalog(
      hosts: hosts,
      source: raw['source'] is String ? raw['source'] as String : '',
      license: raw['license'] is String ? raw['license'] as String : '',
    );
  }

  /// Process-lifetime cache for the default asset bundle only.
  /// Pass [bundle] (tests) to bypass cache and always read that bundle.
  static LpaSmdpCatalog? _bundledCache;
  static Future<LpaSmdpCatalog>? _bundledInflight;

  /// Test-only: clear process cache so memoize can be re-asserted.
  @visibleForTesting
  static void debugResetBundledCacheForTest() {
    _bundledCache = null;
    _bundledInflight = null;
  }

  static Future<LpaSmdpCatalog> loadBundled({AssetBundle? bundle}) async {
    if (bundle != null) {
      final text = await bundle.loadString(kLpaSmdpPreviewAsset);
      return LpaSmdpCatalog.fromJson(jsonDecode(text));
    }
    final cached = _bundledCache;
    if (cached != null) return cached;
    final inflight = _bundledInflight;
    if (inflight != null) return inflight;
    final future = () async {
      try {
        final text = await rootBundle.loadString(kLpaSmdpPreviewAsset);
        final catalog = LpaSmdpCatalog.fromJson(jsonDecode(text));
        _bundledCache = catalog;
        return catalog;
      } catch (_) {
        _bundledInflight = null;
        rethrow;
      }
    }();
    _bundledInflight = future;
    return future;
  }
}

String normalizeSmdpHost(String raw) {
  var text = raw.trim().toLowerCase();
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  if (text.isEmpty) return '';
  if (RegExp(r'^https?:\/\/').hasMatch(text)) {
    try {
      return Uri.parse(
        text,
      ).host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    } catch (_) {
      return '';
    }
  }
  return text.split('/').first.split(':').first;
}

String countryLabel(String iso) {
  final code = iso.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return '';
  return kSmdpCountryZh[code] ?? code;
}

String flagEmoji(String iso) {
  final code = iso.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return '';
  return String.fromCharCodes(code.codeUnits.map((unit) => 127397 + unit));
}

String formatProfileBytes(int bytes) {
  if (bytes <= 0) return '';
  final kb = bytes / 1024;
  if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(2)} MB';
  return '${kb >= 100 ? kb.toStringAsFixed(0) : kb.toStringAsFixed(1)} KB';
}

String eumPrefix(String eid) {
  final digits = eid.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 8 ? digits.substring(0, 8) : '';
}

({int bytes, int min, int max, String matchedEum, bool ranged}) pickSize(
  LpaSmdpHostRecord record,
  String eid,
) {
  final eum = eumPrefix(eid);
  final mapped = eum.isEmpty ? 0 : (record.eumSizes[eum] ?? 0);
  if (mapped > 0) {
    return (
      bytes: mapped,
      min: mapped,
      max: mapped,
      matchedEum: eum,
      ranged: false,
    );
  }
  final min = record.min;
  final max = record.max;
  final mid = record.typical;
  if (min > 0 && max > 0 && max > min * 1.35) {
    final bytes = mid > 0 ? mid : min;
    return (
      bytes: bytes.round(),
      min: min.round(),
      max: max.round(),
      matchedEum: '',
      ranged: true,
    );
  }
  if (mid > 0) {
    final bytes = mid.round();
    return (
      bytes: bytes,
      min: bytes,
      max: bytes,
      matchedEum: '',
      ranged: false,
    );
  }
  if (min > 0) {
    final bytes = min.round();
    return (
      bytes: bytes,
      min: bytes,
      max: bytes,
      matchedEum: '',
      ranged: false,
    );
  }
  return (bytes: 0, min: 0, max: 0, matchedEum: '', ranged: false);
}

SmdpPreview? lookupSmdpPreview(
  String smdp, {
  String eid = '',
  int? freeNvramBytes,
  required LpaSmdpCatalog catalog,
}) {
  final host = normalizeSmdpHost(smdp);
  if (host.isEmpty) return null;
  final record = catalog.hosts[host];
  if (record == null) {
    return SmdpPreview(known: false, host: host);
  }
  final countries = <SmdpCountry>[
    for (final iso in record.countries)
      if (countryLabel(iso).isNotEmpty)
        SmdpCountry(
          iso: iso.trim().toUpperCase(),
          name: countryLabel(iso),
          flag: flagEmoji(iso),
        ),
  ];
  final size = pickSize(record, eid);
  final free = freeNvramBytes;
  final spaceWarning =
      free != null && free > 0 && size.bytes > 0 && free < size.bytes * 1.25;
  return SmdpPreview(
    known: true,
    host: host,
    countries: countries,
    operators: record.operators,
    operatorTotal: record.operatorHint > 0
        ? record.operatorHint
        : record.operators.length,
    sizeBytes: size.bytes,
    sizeMin: size.min,
    sizeMax: size.max,
    sizeRanged: size.ranged,
    matchedEum: size.matchedEum,
    spaceWarning: spaceWarning,
  );
}

SmdpPreviewCopy? formatSmdpPreview(SmdpPreview? preview) {
  if (preview == null) return null;
  if (!preview.known) {
    return SmdpPreviewCopy(
      title: '未收录此 SM-DP+',
      detail: '${preview.host} 不在社区样本库里，下载前无法估计国家和占用。',
      size: '',
      warning: '',
    );
  }
  final countryText = preview.countries.isEmpty
      ? '国家未知'
      : preview.countries.length <= 3
      ? preview.countries
            .map((item) => '${item.flag} ${item.name}'.trim())
            .join(' · ')
      : '${preview.countries.take(2).map((item) => '${item.flag} ${item.name}'.trim()).join(' · ')} 等 ${preview.countries.length} 地';
  final operatorText = preview.operatorTotal > preview.operators.length
      ? '${preview.operators.take(3).join(' / ')} 等 ${preview.operatorTotal} 家'
      : preview.operators.take(3).join(' / ');
  final size = preview.sizeRanged
      ? '估计 ${formatProfileBytes(preview.sizeMin)}–${formatProfileBytes(preview.sizeMax)}'
      : preview.sizeBytes > 0
      ? '约 ${formatProfileBytes(preview.sizeBytes)}'
      : '';
  return SmdpPreviewCopy(
    title: countryText,
    detail: <String>[
      operatorText,
      preview.matchedEum.isNotEmpty ? '已按本卡硅片校正体积' : '社区样本，不是实测包体',
    ].where((item) => item.isNotEmpty).join(' · '),
    size: size,
    warning: preview.spaceWarning ? '估计占用接近或超过当前可用空间，下载可能失败。' : '',
  );
}

SmdpPreview? previewLpaActivation(
  String raw, {
  String eid = '',
  int? freeNvramBytes,
  required LpaSmdpCatalog catalog,
}) {
  final parsed = parseLpaActivationCode(raw);
  if (!parsed.hasSmdp) return null;
  return lookupSmdpPreview(
    parsed.smdp,
    eid: eid,
    freeNvramBytes: freeNvramBytes,
    catalog: catalog,
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return <String>[
    for (final item in raw)
      if (item is String) item,
  ];
}

int _positiveInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return 0;
}

double _finite(Object? raw) {
  if (raw is num && raw.isFinite) return raw.toDouble();
  return 0;
}
