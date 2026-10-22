part of 'esim_api.dart';

/// 总览里的 profile 清单只用来给联系人卡配名字：网关没缓存（null）或
/// 形状对不上时退成空表，不能连带把铭牌 / 容量一起判失败。
List<EsimProfileDto> _parseCachedGroups(Object? value) {
  if (value is! List<Object?>) return const <EsimProfileDto>[];
  try {
    return _parseGroups(value);
  } on EsimDtoException {
    return const <EsimProfileDto>[];
  }
}

CardPolicy _parsePolicy(Object? value) {
  final map = _shape.map(value);
  _shape.string(map['iccid']);
  final apn = _shape.string(map['apn']).trim();
  try {
    return CardPolicy(
      apn: apn,
      ipVersion: parseCardIpVersion(_shape.string(map['ip_version'])),
      networkEnabled: _optionalBool(map['network_enabled'], true),
      vowifiEnabled: _optionalBool(map['vowifi_enabled'], true),
      airplaneEnabled: _optionalBool(map['airplane_enabled'], true),
      mbnProfile: map['mbn_profile'] is String
          ? (map['mbn_profile'] as String).trim()
          : '',
      voicePath: parseCardVoicePath(
        map['voice_path'] is String ? map['voice_path'] as String : null,
      ),
    );
  } on FormatException {
    throw const EsimDtoException();
  }
}

bool _optionalBool(Object? value, bool fallback) {
  if (value == null) return fallback;
  return _shape.boolean(value);
}

List<EuiccHardware> _parseHardware(Map<Object?, Object?> root) {
  final chipInfo = root['chipInfo'];
  if (chipInfo == null) return const <EuiccHardware>[];
  final chip = _shape.map(chipInfo);
  final eids = chip['eids'];
  if (eids == null) return const <EuiccHardware>[];
  final entries = _shape.list(eids);
  final firmware = chip['firmware'] is String
      ? (chip['firmware'] as String).trim()
      : '';
  final groups = root['profiles'] is List<Object?>
      ? root['profiles'] as List<Object?>
      : const <Object?>[];
  final aids = <String>[
    for (final groupValue in groups)
      if (groupValue case final Map<Object?, Object?> group)
        if (group['aidHex'] is String) group['aidHex'] as String,
    for (final entryValue in entries)
      if (entryValue case final Map<Object?, Object?> entry)
        if (entry['aid'] is String) entry['aid'] as String,
  ];
  final eidValues = <String>[];
  final sasValues = <String>[];
  for (final entryValue in entries) {
    final entry = _shape.map(entryValue);
    if (entry['eid'] is String) eidValues.add(entry['eid'] as String);
    if (entry['sasAccreditationNumber'] is String) {
      sasValues.add(entry['sasAccreditationNumber'] as String);
    }
  }
  final nameplate = resolveEuiccNameplate(
    aids: aids,
    eids: eidValues,
    sasList: sasValues,
    firmware: firmware,
  );
  final result = <EuiccHardware>[];
  for (var index = 0; index < entries.length; index++) {
    final entry = _shape.map(entries[index]);
    final eid = entry['eid'] is String ? (entry['eid'] as String).trim() : '';
    final manufacturer = entry['manufacturer'] is String
        ? (entry['manufacturer'] as String).trim()
        : '';
    final bytes = entry['freeNvramBytes'];
    result.add(
      EuiccHardware(
        index: index,
        eidDisplay: eid.isEmpty ? '' : Redaction.maskTail4(eid),
        chipMaker: manufacturer.isNotEmpty
            ? manufacturer
            : chipMakerFromEid(eid),
        freeNvram: entry['freeNvram'] is String
            ? (entry['freeNvram'] as String).trim()
            : '',
        freeNvramBytes: bytes is int
            ? bytes
            : bytes is num
            ? bytes.toInt()
            : null,
        nameplate: nameplate.isEmpty ? unknownEuiccNameplate : nameplate,
        eidPrefix: eidPrefixFromEid(eid),
      ),
    );
  }
  return List<EuiccHardware>.unmodifiable(result);
}

EsimInventoryDto _parseInventory(Object? value) {
  if (value is List<Object?>) {
    return EsimInventoryDto(
      hint: EsimInventoryHint.none,
      profiles: _parseGroups(value),
    );
  }
  final map = _shape.map(value);
  final error = map['error'];
  if (error != null) {
    final errorMap = _shape.map(error);
    final hint = switch (_shape.string(errorMap['code'])) {
      'not_euicc' => EsimInventoryHint.notEuicc,
      'esim_uim_busy' => EsimInventoryHint.uimBusy,
      'esim_qmi_unavailable' => EsimInventoryHint.qmiUnavailable,
      _ => throw const EsimDtoException(),
    };
    _shape.string(errorMap['message']);
    _shape.list(map['ses']);
    return EsimInventoryDto(hint: hint, profiles: const <EsimProfileDto>[]);
  }
  if (map['cached'] == false) {
    _shape.list(map['ses']);
    return const EsimInventoryDto(
      hint: EsimInventoryHint.refreshRequired,
      profiles: <EsimProfileDto>[],
    );
  }
  throw const EsimDtoException();
}

List<EsimProfileDto> _parseGroups(List<Object?> groups) {
  final result = <EsimProfileDto>[];
  for (final groupValue in groups) {
    final group = _shape.map(groupValue);
    final eid = _shape.string(group['eid']).trim();
    final aidHex = _shape.string(group['aidHex']).trim();
    final eidDisplay = eid.isEmpty ? '' : Redaction.maskTail4(eid);
    for (final profileValue in _shape.list(group['profiles'])) {
      final profile = _shape.map(profileValue);
      final iccid = _shape.string(profile['iccid']).trim();
      if (iccid.isEmpty) throw const EsimDtoException();
      final state = switch (profile['state']) {
        0 => EsimProfileState.disabled,
        1 => EsimProfileState.enabled,
        _ => throw const EsimDtoException(),
      };
      final name = _shape.string(profile['name']).trim();
      final provider = _shape.string(profile['serviceProviderName']).trim();
      final stateText = _shape.string(profile['stateText']);
      _shape.string(profile['classText']);
      // WEB `esimProfileName/esimProfileProvider`：昵称是可选字段，
      // 名字为空退到运营商名，再退「未命名」；运营商为空显示「—」。
      final nickname = switch (profile['profileNickname'] ??
          profile['nickname']) {
        final String value => value.trim(),
        _ => '',
      };
      result.add(
        EsimProfileDto(
          name: nickname.isNotEmpty
              ? nickname
              : name.isNotEmpty
              ? name
              : provider.isNotEmpty
              ? provider
              : '未命名',
          provider: provider.isEmpty ? '—' : provider,
          iccidDisplay: Redaction.maskTail4(iccid),
          active: state == EsimProfileState.enabled,
          state: state,
          locked: profile['locked'] == true,
          stateText: stateText,
          eidDisplay: eidDisplay,
          target: _EsimSwitchTarget(iccid, aidHex),
        ),
      );
    }
  }
  return List<EsimProfileDto>.unmodifiable(result);
}

final class EsimInventoryDto {
  const EsimInventoryDto({required this.hint, required this.profiles});
  final EsimInventoryHint hint;
  final List<EsimProfileDto> profiles;
}

final class EsimOverviewDto {
  const EsimOverviewDto({required this.hardware, required this.profiles});
  final List<EuiccHardware> hardware;
  final List<EsimProfileDto> profiles;
}

final class EsimProfileDto {
  const EsimProfileDto({
    required this.name,
    required this.provider,
    required this.iccidDisplay,
    required this.active,
    required this.state,
    required this.target,
    this.locked = false,
    this.stateText = '',
    this.eidDisplay = '',
  });
  final String name;
  final String provider;
  final String iccidDisplay;
  final bool active;
  final EsimProfileState state;
  final EsimSwitchTarget target;
  final bool locked;
  final String stateText;
  final String eidDisplay;

  @override
  String toString() => 'EsimProfileDto(name: $name, active: $active)';
}

final class _EsimSwitchTarget implements EsimSwitchTarget {
  const _EsimSwitchTarget(this._iccid, this._aidHex);
  final String _iccid;
  final String _aidHex;

  // Keep card identity stable across DTO refreshes without exposing raw IDs.
  @override
  bool operator ==(Object other) =>
      other is _EsimSwitchTarget &&
      other._iccid == _iccid &&
      other._aidHex == _aidHex;

  @override
  int get hashCode => Object.hash(_iccid, _aidHex);

  @override
  String toString() => 'EsimSwitchTarget(redacted)';
}

final class EsimDtoException implements DtoShapeException {
  const EsimDtoException();
}

const _shape = JsonShape(EsimDtoException.new);
