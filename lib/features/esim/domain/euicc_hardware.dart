import 'esim.dart';
import 'euicc_catalog.dart';

/// eUICC 硅片身份（来自网关 `GET /devices/{id}/esim` 的 `chipInfo.eids`）。
///
/// 与 WEB `utils/euiccCardCatalog.js` 同一套两层身份：
/// - EUM / EID 前缀 = 硅片厂（Thales / G+D / 东信和平 / Kigen…）
/// - ISD-R AID + EIN/SAS/固件组合 = 零售品牌铭牌（ESTK.me Max / 5ber / XeSIM…）
///
/// 指纹不够唯一时铭牌回落「Nekoko联名」（原来的「eSIM 实体卡」没有名字）。
final class EuiccHardware {
  const EuiccHardware({
    required this.index,
    required this.eidDisplay,
    required this.chipMaker,
    required this.freeNvram,
    required this.freeNvramBytes,
    required this.nameplate,
    this.eidPrefix = '',
  });

  /// 芯片序号（0 起），显示为「eSIM ${index + 1}」。
  final int index;

  /// 打码后的 EID（尾 4 位），空串表示网关没给。
  final String eidDisplay;

  /// 硅片厂：优先网关回的 `manufacturer`，否则按 EID 前缀查表；查不到为空。
  final String chipMaker;

  /// 可用容量的人读文本，如 `634.55 KB`；网关未上报时为空。
  final String freeNvram;

  final int? freeNvramBytes;

  /// 零售铭牌；全卡共享同一个判定结果。
  final String nameplate;

  /// EID 前 8 位数字（EUM），给 LPA 预览按硅片校正体积。打码展示用 [eidDisplay]。
  final String eidPrefix;

  String get slotLabel => 'eSIM ${index + 1}';

  bool get hasCapacity => freeNvram.isNotEmpty;
}

/// 网关缓存的 eUICC 总览：硅片身份 + 上次读到的 profile 清单。
///
/// 一次 `GET /devices/{id}/esim` 同时喂设备卡铭牌与「这张 ICCID 叫什么名」，
/// 短信页据此把联系人卡的铭牌写成卡名，不必再打一轮 UIM。
final class EuiccOverview {
  EuiccOverview({
    required List<EuiccHardware> hardware,
    required List<EsimProfile> profiles,
  }) : hardware = List<EuiccHardware>.unmodifiable(hardware),
       profiles = List<EsimProfile>.unmodifiable(profiles);

  final List<EuiccHardware> hardware;
  final List<EsimProfile> profiles;

  /// 按打码后的 ICCID（尾 4 位形态）找卡名；找不到返回 null，由调用方回退。
  String? profileNameFor(String iccidDisplay) {
    if (iccidDisplay.isEmpty) return null;
    for (final profile in profiles) {
      if (profile.iccidDisplay == iccidDisplay) return profile.name;
    }
    return null;
  }
}

const String unknownEuiccNameplate = 'Nekoko联名';

/// EID 前 8 位 EIN → 硅片厂。与 WEB `EID_CHIP_MAKER` 同表。
const Map<String, String> _eidChipMaker = <String, String>{
  '89033023': 'Thales DIS France SAS',
  '89033024': 'IDEMIA',
  '89034011': 'Valid',
  '89041030': 'STMicroelectronics',
  '89043051': 'NXP',
  '89043052': 'NXP',
  '89044045': 'Kigen / SIMLINK',
  '89044047': 'Kigen',
  '89049032': 'G+D Mobile Security GmbH',
  '89049038': 'G+D Mobile Security GmbH',
  '89049044': 'G+D Mobile Security GmbH',
  '89086001': '恒宝 Hengbao',
  '89086029': '武汉天瑜',
  '89086030': '东信和平 Eastcompeace',
  '35060000': '中国大陆 EUM',
  '35840574': 'WatchData Technologies Ltd.',
};

/// GSMA SGP.02 EID[1:5] 四位 EUM 码。与 WEB `EUM_CODE_CHIP_MAKER` 同表。
const Map<String, String> _eumChipMaker = <String, String>{
  '5840': 'WatchData Technologies Ltd.',
  '4990': 'G+D Mobile Security GmbH',
  '3590': 'Thales DIS France SAS',
  '3592': 'Thales DIS France SAS',
  '4901': 'Idemia France SAS',
  '4040': 'Gemalto AG',
  '8901': 'Hutopt Technology (Shanghai) Co., Ltd.',
  '9086': 'Eastcompeace Technology Co., Ltd.',
};

const String _gsmaIsdrAid = 'A0000005591010FFFFFFFF8900000100';
const String _estkSe0Aid = 'A06573746B6D65FFFF4953442D522030';
const String _estkSe1Aid = 'A06573746B6D65FFFF4953442D522031';
const String _estkAidPrefix = 'A06573746B6D65';
const String _xesimAid = 'A0000005591010FFFFFFFF8900000177';
const String _esimMeAid = 'A0000005591010000000008900000300';
const String _ber5Aid = 'A0000005591010FFFFFFFF8900050500';
const String _linksfieldAid = 'A000000559104C696E6B736669656C64';

String eidPrefixFromEid(String eid) {
  final digits = eid.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 8 ? digits.substring(0, 8) : '';
}

String chipMakerFromEid(String eid) {
  final digits = eid.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 8) {
    final byEin = _eidChipMaker[digits.substring(0, 8)];
    if (byEin != null) return byEin;
  }
  if (digits.length >= 5) {
    final byEum = _eumChipMaker[digits.substring(1, 5)];
    if (byEum != null) return byEum;
  }
  return '';
}

String _normalizeAid(String value) =>
    value.replaceAll(RegExp(r'\s+'), '').toUpperCase();

bool _isEstkAid(String aid) => _normalizeAid(aid).startsWith(_estkAidPrefix);

bool _isOemRetailAid(String aid) {
  final hex = _normalizeAid(aid);
  return hex == _xesimAid ||
      hex == _ber5Aid ||
      hex == _esimMeAid ||
      hex == _linksfieldAid ||
      _isEstkAid(hex);
}

bool _isEstkCos6(String firmware) {
  final text = firmware.trim();
  if (RegExp(r'cos\s*6', caseSensitive: false).hasMatch(text)) return true;
  final major = RegExp(r'^(\d+)').firstMatch(text)?.group(1);
  return major == '32';
}

/// 用一张卡上出现的全部 ISD-R AID + EID + SAS + 固件判定零售品牌。
/// 规则顺序与 WEB `resolveEuiccProduct` 一致；判不出返回空串。
String resolveEuiccNameplate({
  required List<String> aids,
  required List<String> eids,
  List<String> sasList = const <String>[],
  String firmware = '',
}) {
  final list = aids.map(_normalizeAid).where((aid) => aid.isNotEmpty).toList();
  final eins = <String>{
    for (final eid in eids)
      if (eid.replaceAll(RegExp(r'\D'), '').length >= 8)
        eid.replaceAll(RegExp(r'\D'), '').substring(0, 8),
  };
  bool hasAid(String wanted) => list.contains(_normalizeAid(wanted));
  final se0 = hasAid(_estkSe0Aid);
  final se1 = hasAid(_estkSe1Aid);
  final estk = se0 || se1 || list.any(_isEstkAid);
  final gsma = hasAid(_gsmaIsdrAid);
  final gdEin = eins.contains('89049032') || eins.contains('89049038');
  final thalesEstk = eins.isNotEmpty && eins.every((ein) => ein == '89033023');

  String plate(String ruleId, String fallback) {
    final synced = catalogNameplate(ruleId);
    return synced.isEmpty ? fallback : synced;
  }

  if (se0 && se1) return plate('estk-max', 'ESTK.me Max');
  if (estk && thalesEstk) return plate('estk-max', 'ESTK.me Max');
  if (estk && eins.contains('89034011')) return plate('estk-plus-plus', 'ESTK.me Plus+');
  if (estk && eins.contains('89049032') && _isEstkCos6(firmware)) {
    return plate('estk-c-beta', 'Estk.me C beta');
  }
  if (estk) return plate('estk-generic', 'ESTK.me');

  if (hasAid(_xesimAid)) return plate('xesim', 'XeSIM');
  if (hasAid(_ber5Aid)) return plate('5ber', '5ber.eSIM');
  if (hasAid(_esimMeAid)) return plate('esim-me', 'eSIM.me');
  if (hasAid(_linksfieldAid)) return plate('linksfield', 'LinksField');

  final gdSas = sasList.any(
    (sas) => RegExp(r'^GD[-_]', caseSensitive: false).hasMatch(sas.trim()),
  );
  if (gdSas || (gdEin && gsma)) return plate('tianlian', 'G+D天联');

  if ((eins.contains('89044045') || eins.contains('89044047')) &&
      !list.any(_isOemRetailAid)) {
    return plate('9esim', '9eSIM');
  }
  if (eins.contains('89049044')) return plate('sysmo-c2t', 'sysmoEUICC1-C2T');
  if (eins.contains('89086030') &&
      sasList.any((value) => value.trim().toUpperCase() == 'ED-ZI-UP-0828')) {
    return plate('9esim-b1', '9eSIM B1');
  }
  return syncedEuiccNameplate(eins: eins, sasList: sasList);
}
