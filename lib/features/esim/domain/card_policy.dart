enum CardIpVersion { ip, ipv6, ipv4v6 }

CardIpVersion parseCardIpVersion(String raw) {
  return switch (raw.trim().toUpperCase()) {
    'IP' || 'IPV4' => CardIpVersion.ip,
    'IPV6' => CardIpVersion.ipv6,
    'IPV4V6' || '' => CardIpVersion.ipv4v6,
    _ => throw const FormatException('Unsupported card IP version.'),
  };
}

extension CardIpVersionApi on CardIpVersion {
  String get apiValue => switch (this) {
    CardIpVersion.ip => 'IP',
    CardIpVersion.ipv6 => 'IPV6',
    CardIpVersion.ipv4v6 => 'IPV4V6',
  };

  String get label => switch (this) {
    CardIpVersion.ip => 'IPv4',
    CardIpVersion.ipv6 => 'IPv6',
    CardIpVersion.ipv4v6 => 'IPv4v6',
  };
}

const List<({String value, String label})> kMbnProfileOptions =
    <({String value, String label})>[
      (value: '', label: '自动（按卡的 HPLMN 选择）'),
      (value: 'OpenMkt-Commercial-CU', label: '强制中国联通 OpenMkt'),
      (value: 'Volte_OpenMkt-Commercial-CMCC', label: '强制中国移动 VoLTE'),
      (value: 'OpenMkt-Commercial-CT', label: '强制中国电信 OpenMkt'),
    ];

const String kMbnProfileHint = 'EC20-CE 没有通用 ROW；海外卡请指定运营商。正在使用的卡更改后模组可能会重启。';

/// 卡策略里的语音路径。默认 VoWiFi，旧卡不选也不变。
/// cellular 只表示拨号走当前模组的 ATD，不代表听筒已经接到模组。
enum CardVoicePath { vowifi, cellular }

CardVoicePath parseCardVoicePath(String? raw) {
  return switch (raw?.trim().toLowerCase()) {
    'cellular' || 'cellular_direct' || 'direct' => CardVoicePath.cellular,
    _ => CardVoicePath.vowifi,
  };
}

extension CardVoicePathApi on CardVoicePath {
  String get apiValue => switch (this) {
    CardVoicePath.vowifi => 'vowifi',
    CardVoicePath.cellular => 'cellular',
  };

  String get label => switch (this) {
    CardVoicePath.vowifi => 'VoWiFi 通话',
    CardVoicePath.cellular => '蜂窝直拨',
  };
}

const String kVoicePathHint = '跟着这张卡走。蜂窝直拨只在插到蜂窝模组上时可用，读卡器没有这条路径。';

final class CardPolicy {
  const CardPolicy({
    required this.apn,
    required this.ipVersion,
    this.networkEnabled = true,
    this.vowifiEnabled = true,
    this.airplaneEnabled = true,
    this.mbnProfile = '',
    this.voicePath = CardVoicePath.vowifi,
  });

  final String apn;
  final CardIpVersion ipVersion;
  final bool networkEnabled;
  final bool vowifiEnabled;
  final bool airplaneEnabled;

  /// 网关 `mbn_profile`。空串 = 自动。PUT 省略该键才是「不改库」。
  final String mbnProfile;

  /// 网关 `voice_path`。缺省 vowifi，和旧卡策略兼容。
  final CardVoicePath voicePath;

  CardPolicy copyWith({
    String? apn,
    CardIpVersion? ipVersion,
    bool? networkEnabled,
    bool? vowifiEnabled,
    bool? airplaneEnabled,
    String? mbnProfile,
    CardVoicePath? voicePath,
  }) {
    return CardPolicy(
      apn: apn ?? this.apn,
      ipVersion: ipVersion ?? this.ipVersion,
      networkEnabled: networkEnabled ?? this.networkEnabled,
      vowifiEnabled: vowifiEnabled ?? this.vowifiEnabled,
      airplaneEnabled: airplaneEnabled ?? this.airplaneEnabled,
      mbnProfile: mbnProfile ?? this.mbnProfile,
      voicePath: voicePath ?? this.voicePath,
    );
  }
}

final class EsimDownloadProgress {
  const EsimDownloadProgress({
    required this.step,
    required this.message,
    required this.percent,
  });

  final String step;
  final String message;
  final int percent;

  bool get isDone => step == 'done';
  bool get isError => step == 'error';
}

final class EsimDownloadFailed implements Exception {
  const EsimDownloadFailed(this.message);
  final String message;
}
