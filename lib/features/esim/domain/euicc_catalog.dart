/// 网关 `GET /api/euicc-catalog` 下发的 eUICC 铭牌。
///
/// 品牌文案以这份目录为准，安卓只按规则 id 取铭牌。目录没拉到时才用本地兜底。
final class EuiccCatalogRule {
  const EuiccCatalogRule({
    required this.nameplate,
    this.id = '',
    this.eidPrefixes = const <String>[],
    this.sas = const <String>[],
  });

  final String nameplate;
  final String id;
  final List<String> eidPrefixes;
  final List<String> sas;
}

List<EuiccCatalogRule> _syncedRules = const <EuiccCatalogRule>[];

/// 用网关 `GET /api/euicc-catalog` 的 `data` 替换同步表。形状不对就清空。
void replaceEuiccCatalog(Object? data) {
  if (data is! Map<Object?, Object?>) {
    _syncedRules = const <EuiccCatalogRule>[];
    return;
  }
  final raw = data['rules'];
  if (raw is! List<Object?>) {
    _syncedRules = const <EuiccCatalogRule>[];
    return;
  }
  final rules = <EuiccCatalogRule>[];
  for (final item in raw) {
    if (item is! Map<Object?, Object?>) continue;
    final nameplate = item['nameplate'];
    if (nameplate is! String || nameplate.trim().isEmpty) continue;
    final id = item['id'];
    rules.add(
      EuiccCatalogRule(
        nameplate: nameplate.trim(),
        id: id is String ? id.trim() : '',
        eidPrefixes: _stringList(item['eidPrefixes']),
        sas: _stringList(item['sas']),
      ),
    );
  }
  _syncedRules = List<EuiccCatalogRule>.unmodifiable(rules);
}

void clearEuiccCatalog() => _syncedRules = const <EuiccCatalogRule>[];

/// 拉取网关目录并替换同步表。调用方负责吞掉网络错误。
Future<void> syncEuiccCatalog(Future<Object?> Function() fetch) async {
  replaceEuiccCatalog(await fetch());
}

/// 网关目录里这条规则的铭牌。没同步到就返回空串，调用方再用本地兜底。
String catalogNameplate(String ruleId) {
  final id = ruleId.trim();
  if (id.isEmpty) return '';
  for (final rule in _syncedRules) {
    if (rule.id == id && rule.nameplate.isNotEmpty) return rule.nameplate;
  }
  return '';
}

String syncedEuiccNameplate({
  required Set<String> eins,
  required List<String> sasList,
}) {
  final sas = sasList.map((value) => value.trim().toUpperCase()).toSet();
  for (final rule in _syncedRules) {
    if (rule.eidPrefixes.isNotEmpty &&
        !rule.eidPrefixes.any(eins.contains)) {
      continue;
    }
    if (rule.sas.isNotEmpty &&
        !rule.sas.any((value) => sas.contains(value.trim().toUpperCase()))) {
      continue;
    }
    if (rule.eidPrefixes.isEmpty && rule.sas.isEmpty) continue;
    return rule.nameplate;
  }
  return '';
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?>) return const <String>[];
  return <String>[
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
