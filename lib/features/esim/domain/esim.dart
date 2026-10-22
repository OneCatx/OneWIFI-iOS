/// Opaque card identity. Repository implementations preserve value equality
/// across refreshes; redacted display labels are never identity keys.
abstract interface class EsimSwitchTarget {}

enum EsimProfileState { disabled, enabled }

enum EsimInventoryHint {
  none,
  refreshRequired,
  uimBusy,
  qmiUnavailable,
  notEuicc,
}

enum EsimSwitchStatus { switched, alreadyActive }

final class EsimProfile {
  const EsimProfile({
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

  /// WEB `currentSimAsProfile`：物理卡不能从芯片删除。
  final bool locked;
  final String stateText;

  /// 打码后的 EID，用来按 eUICC 分组；空串表示网关没给。
  final String eidDisplay;

  /// WEB `canDeleteEsimProfile`：有卡、未锁定、当前未启用。
  bool get canDelete => !locked && !active;

  String get deleteBlockedReason {
    if (locked) return '物理卡不能从芯片删除';
    if (active) return '当前启用的卡不能删，先切到别的卡';
    return '';
  }

  @override
  String toString() => 'EsimProfile(name: $name, active: $active)';
}

final class EsimInventory {
  EsimInventory({required this.hint, required List<EsimProfile> profiles})
    : profiles = List<EsimProfile>.unmodifiable(profiles);

  final EsimInventoryHint hint;
  final List<EsimProfile> profiles;
}

final class EsimSwitchResult {
  const EsimSwitchResult({required this.status, required this.verified});

  final EsimSwitchStatus status;
  final bool verified;
}
