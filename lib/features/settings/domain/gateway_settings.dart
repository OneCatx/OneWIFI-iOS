/// 设置页领域模型。契约对齐 WEB `Settings.vue` + `onewifiGateway.js`。
enum UiLanguage { zh, en }

enum AccessMode { internal, public }

enum NotifyChannel { telegram, bark, email, pushplus, webhook, wecom, onetools }

extension NotifyChannelApi on NotifyChannel {
  String get apiName => name;

  String get label => switch (this) {
    NotifyChannel.telegram => 'Telegram',
    NotifyChannel.bark => 'Bark',
    NotifyChannel.email => 'Email',
    NotifyChannel.pushplus => 'PushPlus',
    NotifyChannel.webhook => 'Webhook',
    NotifyChannel.wecom => '企业微信',
    NotifyChannel.onetools => 'OneTools',
  };

  bool get canTest => this != NotifyChannel.pushplus;
}

final class SmsModemSettings {
  const SmsModemSettings({this.autoClearModemStorage = true});

  final bool autoClearModemStorage;
}

final class VowifiMtuSettings {
  const VowifiMtuSettings({this.mtuCompatibility = false});

  final bool mtuCompatibility;
}

/// Gateway/router seat from GET /api/license. Android seat stays native.
final class GatewayLicenseStatus {
  const GatewayLicenseStatus({
    this.activated = false,
    this.code = '',
    this.edition = '',
    this.clientKind = '',
  });

  final bool activated;
  final String code;
  final String edition;
  final String clientKind;
}

final class ProductLicense {
  const ProductLicense({
    this.key = '',
    this.activated = false,
    this.membershipBadge = '',
  });

  final String key;
  final bool activated;
  final String membershipBadge;

  bool get isActive => activated && key.trim().isNotEmpty;
}

final class SystemInfo {
  const SystemInfo({
    this.version = 'OneWIFI',
    this.buildTime = '',
    this.developer = false,
  });

  final String version;
  final String buildTime;
  final bool developer;
}

final class GatewayUpdate {
  const GatewayUpdate({
    required this.available,
    this.version = '',
    this.currentVersion = '',
    this.message = '',
    this.repository = '',
  });

  final bool available;
  final String version;
  final String currentVersion;
  final String message;
  final String repository;
}

final class GatewayUpdateApply {
  const GatewayUpdateApply({
    required this.applied,
    this.version = '',
    this.message = '',
    this.reauthenticationRequired = false,
  });

  final bool applied;
  final String version;
  final String message;
  final bool reauthenticationRequired;
}

final class HttpsSettings {
  const HttpsSettings({
    required this.enabled,
    this.httpUrl = '',
    this.httpsUrl = '',
    this.fingerprint = '',
    this.notAfter,
    this.source = '',
    this.names = const <String>[],
    this.coversHost = false,
    this.host = '',
  });

  final bool enabled;
  final String httpUrl;
  final String httpsUrl;
  final String fingerprint;
  final DateTime? notAfter;
  final String source;
  final List<String> names;
  final bool coversHost;
  final String host;

  bool get isCustom => source == 'custom';
  bool get isSelfSigned => source == 'self_signed';
  bool get hasExpiry => notAfter != null;
  bool get hasNames => names.isNotEmpty;
}

final class DeveloperQuota {
  const DeveloperQuota({
    required this.deviceLimit,
    required this.maxDeviceLimit,
    required this.smsHourlyLimit,
    required this.maxSmsHourlyLimit,
  });

  final int deviceLimit;
  final int maxDeviceLimit;
  final int smsHourlyLimit;
  final int maxSmsHourlyLimit;
}

final class AccessPolicy {
  const AccessPolicy({
    this.mode = AccessMode.internal,
    this.allowedCidrs = const <String>[],
    this.trustProxyHeaders = false,
    this.trustedProxyCidrs = const <String>[],
    this.clientIp = '',
    this.clientAllowed = true,
  });

  final AccessMode mode;
  final List<String> allowedCidrs;
  final bool trustProxyHeaders;
  final List<String> trustedProxyCidrs;
  final String clientIp;
  final bool clientAllowed;

  String get allowedCidrsText => allowedCidrs.join('\n');
  String get trustedProxyCidrsText => trustedProxyCidrs.join('\n');
}

/// 六个通知通道共用一份字段袋：保存时只序列化该通道认识的键。
final class NotifyChannelSettings {
  const NotifyChannelSettings({
    this.enabled = false,
    this.url = '',
    this.extraUrls = const <String>[],
    this.secret = '',
    this.timeoutMs = 5000,
    this.botToken = '',
    this.chatId = '',
    this.adminId = '',
    this.baseUrl = '',
    this.proxy = '',
    this.token = '',
    this.topic = '',
    this.pushChannel = '',
    this.smtpHost = '',
    this.smtpPort = 465,
    this.useSsl = true,
    this.username = '',
    this.password = '',
    this.fromAddress = '',
    this.toAddresses = '',
    this.group = '',
    this.icon = '',
    this.level = 'active',
    this.payloadTemplate = '',
  });

  final bool enabled;
  final String url;

  /// 网关 `urls[1..]`。表单只编辑 [url]，保存时必须原样带回，否则 PUT 会抹掉副地址。
  final List<String> extraUrls;
  final String secret;
  final int timeoutMs;
  final String botToken;
  final String chatId;
  final String adminId;
  final String baseUrl;
  final String proxy;
  final String token;
  final String topic;
  final String pushChannel;
  final String smtpHost;
  final int smtpPort;
  final bool useSsl;
  final String username;
  final String password;
  final String fromAddress;
  final String toAddresses;
  final String group;
  final String icon;
  final String level;
  final String payloadTemplate;

  NotifyChannelSettings copyWith({
    bool? enabled,
    String? url,
    List<String>? extraUrls,
    String? secret,
    int? timeoutMs,
    String? botToken,
    String? chatId,
    String? adminId,
    String? baseUrl,
    String? proxy,
    String? token,
    String? topic,
    String? pushChannel,
    String? smtpHost,
    int? smtpPort,
    bool? useSsl,
    String? username,
    String? password,
    String? fromAddress,
    String? toAddresses,
    String? group,
    String? icon,
    String? level,
    String? payloadTemplate,
  }) {
    return NotifyChannelSettings(
      enabled: enabled ?? this.enabled,
      url: url ?? this.url,
      extraUrls: extraUrls ?? this.extraUrls,
      secret: secret ?? this.secret,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      botToken: botToken ?? this.botToken,
      chatId: chatId ?? this.chatId,
      adminId: adminId ?? this.adminId,
      baseUrl: baseUrl ?? this.baseUrl,
      proxy: proxy ?? this.proxy,
      token: token ?? this.token,
      topic: topic ?? this.topic,
      pushChannel: pushChannel ?? this.pushChannel,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      useSsl: useSsl ?? this.useSsl,
      username: username ?? this.username,
      password: password ?? this.password,
      fromAddress: fromAddress ?? this.fromAddress,
      toAddresses: toAddresses ?? this.toAddresses,
      group: group ?? this.group,
      icon: icon ?? this.icon,
      level: level ?? this.level,
      payloadTemplate: payloadTemplate ?? this.payloadTemplate,
    );
  }
}

final class NotificationSettings {
  const NotificationSettings({
    this.telegram = const NotifyChannelSettings(),
    this.bark = const NotifyChannelSettings(),
    this.email = const NotifyChannelSettings(),
    this.pushplus = const NotifyChannelSettings(),
    this.webhook = const NotifyChannelSettings(),
    this.wecom = const NotifyChannelSettings(),
    this.onetools = const NotifyChannelSettings(),
  });

  final NotifyChannelSettings telegram;
  final NotifyChannelSettings bark;
  final NotifyChannelSettings email;
  final NotifyChannelSettings pushplus;
  final NotifyChannelSettings webhook;
  final NotifyChannelSettings wecom;
  final NotifyChannelSettings onetools;

  NotifyChannelSettings of(NotifyChannel channel) => switch (channel) {
    NotifyChannel.telegram => telegram,
    NotifyChannel.bark => bark,
    NotifyChannel.email => email,
    NotifyChannel.pushplus => pushplus,
    NotifyChannel.webhook => webhook,
    NotifyChannel.wecom => wecom,
    NotifyChannel.onetools => onetools,
  };

  NotificationSettings replacing(
    NotifyChannel channel,
    NotifyChannelSettings next,
  ) {
    return NotificationSettings(
      telegram: channel == NotifyChannel.telegram ? next : telegram,
      bark: channel == NotifyChannel.bark ? next : bark,
      email: channel == NotifyChannel.email ? next : email,
      pushplus: channel == NotifyChannel.pushplus ? next : pushplus,
      webhook: channel == NotifyChannel.webhook ? next : webhook,
      wecom: channel == NotifyChannel.wecom ? next : wecom,
      onetools: channel == NotifyChannel.onetools ? next : onetools,
    );
  }
}

final class SettingsSnapshot {
  const SettingsSnapshot({
    this.language = UiLanguage.zh,
    this.info = const SystemInfo(),
    this.notifications = const NotificationSettings(),
    this.security = const AccessPolicy(),
    this.https,
    this.quota,
    this.license = const ProductLicense(),
    this.gatewayLicense,
    this.smsModem = const SmsModemSettings(),
    this.vowifiMtu = const VowifiMtuSettings(),
  });

  final UiLanguage language;
  final SystemInfo info;
  final NotificationSettings notifications;
  final AccessPolicy security;
  final HttpsSettings? https;
  final DeveloperQuota? quota;
  final ProductLicense license;
  final GatewayLicenseStatus? gatewayLicense;
  final SmsModemSettings smsModem;
  final VowifiMtuSettings vowifiMtu;

  SettingsSnapshot copyWith({
    UiLanguage? language,
    SystemInfo? info,
    NotificationSettings? notifications,
    AccessPolicy? security,
    HttpsSettings? https,
    DeveloperQuota? quota,
    ProductLicense? license,
    GatewayLicenseStatus? gatewayLicense,
    SmsModemSettings? smsModem,
    VowifiMtuSettings? vowifiMtu,
    bool clearHttps = false,
    bool clearQuota = false,
    bool clearGatewayLicense = false,
  }) {
    return SettingsSnapshot(
      language: language ?? this.language,
      info: info ?? this.info,
      notifications: notifications ?? this.notifications,
      security: security ?? this.security,
      https: clearHttps ? null : (https ?? this.https),
      quota: clearQuota ? null : (quota ?? this.quota),
      license: license ?? this.license,
      gatewayLicense: clearGatewayLicense
          ? null
          : (gatewayLicense ?? this.gatewayLicense),
      smsModem: smsModem ?? this.smsModem,
      vowifiMtu: vowifiMtu ?? this.vowifiMtu,
    );
  }
}

List<String> splitCidrLines(String text) {
  return text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

List<String> splitAddressList(String text) {
  return text
      .split(RegExp(r'[,;\s]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
