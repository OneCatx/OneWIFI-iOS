part of 'settings_api.dart';

UiLanguage _parseLanguage(Object? value) {
  final raw = _optString(value, 'zh').toLowerCase();
  return raw == 'en' ? UiLanguage.en : UiLanguage.zh;
}

NotificationSettings _parseNotifications(Object? value) {
  final map = _shape.map(value);
  return NotificationSettings(
    telegram: _parseChannel(map['telegram']),
    bark: _parseChannel(map['bark']),
    email: _parseChannel(map['email']),
    pushplus: _parseChannel(map['pushplus']),
    webhook: _parseChannel(map['webhook']),
    wecom: _parseChannel(map['wecom']),
  );
}

NotifyChannelSettings _parseChannel(Object? value) {
  if (value == null) return const NotifyChannelSettings();
  final map = _shape.map(value);
  final urls = _channelUrlsFromMap(map);
  return NotifyChannelSettings(
    enabled: map['enabled'] == true,
    url: urls.$1,
    extraUrls: urls.$2,
    secret: _shape.optionalString(map['secret']),
    timeoutMs: _optInt(map['timeout_ms'], 5000),
    botToken: _shape.optionalString(map['bot_token']),
    chatId: _shape.optionalString(map['chat_id']),
    adminId: _shape.optionalString(map['admin_id']),
    baseUrl: _shape.optionalString(map['base_url']),
    proxy: _shape.optionalString(map['proxy']),
    token: _shape.optionalString(map['token']),
    topic: _shape.optionalString(map['topic']),
    pushChannel: _shape.optionalString(map['channel']),
    smtpHost: _shape.optionalString(map['smtp_host']),
    smtpPort: _optInt(map['smtp_port'], 465),
    useSsl: map['use_ssl'] is bool ? map['use_ssl'] as bool : true,
    username: _shape.optionalString(map['username']),
    password: _shape.optionalString(map['password']),
    fromAddress: _shape.optionalString(map['from_address']),
    toAddresses: _joinAddresses(map['to_addresses']),
    group: _shape.optionalString(map['group']),
    icon: _shape.optionalString(map['icon']),
    level: _optString(map['level'], 'active'),
    payloadTemplate: _shape.optionalString(map['payload_template']),
  );
}

Map<String, Object?> _encodeNotifications(NotificationSettings notifications) {
  return <String, Object?>{
    for (final channel in NotifyChannel.values)
      channel.apiName: _encodeChannel(channel, notifications.of(channel)),
  };
}

Map<String, Object?> _encodeChannel(
  NotifyChannel channel,
  NotifyChannelSettings settings,
) {
  final urls = _encodeUrls(settings);
  return switch (channel) {
    NotifyChannel.telegram => <String, Object?>{
      'enabled': settings.enabled,
      'bot_token': settings.botToken,
      'chat_id': settings.chatId,
      'admin_id': settings.adminId,
      'base_url': settings.baseUrl,
      'proxy': settings.proxy,
    },
    NotifyChannel.bark => <String, Object?>{
      'enabled': settings.enabled,
      'urls': urls,
      'group': settings.group,
      'icon': settings.icon,
      'level': settings.level,
    },
    NotifyChannel.email => <String, Object?>{
      'enabled': settings.enabled,
      'smtp_host': settings.smtpHost,
      'smtp_port': settings.smtpPort,
      'use_ssl': settings.useSsl,
      'username': settings.username,
      'password': settings.password,
      'from_address': settings.fromAddress,
      'to_addresses': splitAddressList(settings.toAddresses),
    },
    NotifyChannel.pushplus => <String, Object?>{
      'enabled': settings.enabled,
      'token': settings.token,
      'topic': settings.topic,
      'channel': settings.pushChannel,
    },
    NotifyChannel.webhook => <String, Object?>{
      'enabled': settings.enabled,
      'urls': urls,
      'secret': settings.secret,
      'timeout_ms': settings.timeoutMs,
    },
    NotifyChannel.wecom => <String, Object?>{
      'enabled': settings.enabled,
      'urls': urls,
      'payload_template': settings.payloadTemplate,
    },
    NotifyChannel.onetools => <String, Object?>{
      'enabled': settings.enabled,
      'public_base_url': settings.baseUrl,
    },
  };
}

Map<String, Object?> _encodeTestBody(
  NotifyChannel channel,
  NotifyChannelSettings settings,
) {
  final urls = _encodeUrls(settings);
  return switch (channel) {
    NotifyChannel.telegram => <String, Object?>{
      'enabled': true,
      'bot_token': settings.botToken,
      'chat_id': settings.chatId,
    },
    NotifyChannel.webhook => <String, Object?>{'enabled': true, 'urls': urls},
    NotifyChannel.bark => <String, Object?>{
      'enabled': true,
      'urls': urls,
      'group': settings.group,
      'icon': settings.icon,
      'level': settings.level,
    },
    NotifyChannel.wecom => <String, Object?>{
      'enabled': true,
      'urls': urls,
      'payload_template': settings.payloadTemplate,
    },
    NotifyChannel.email => _encodeChannel(
      channel,
      settings,
    )..['enabled'] = true,
    NotifyChannel.pushplus => throw const SettingsDtoException(),
    NotifyChannel.onetools => throw const SettingsDtoException(),
  };
}

AccessPolicy _parseSecurity(Object? value) {
  final map = _shape.map(value);
  return AccessPolicy(
    mode: _optString(map['mode'], 'internal') == 'public'
        ? AccessMode.public
        : AccessMode.internal,
    allowedCidrs: _stringList(map['allowed_cidrs']),
    trustProxyHeaders: map['trust_proxy_headers'] == true,
    trustedProxyCidrs: _stringList(map['trusted_proxy_cidrs']),
    clientIp: _shape.optionalString(map['client_ip']),
    clientAllowed: map['client_allowed'] != false,
  );
}

HttpsSettings _parseHttps(Object? value) {
  final map = _shape.map(value);
  return HttpsSettings(
    enabled: map['enabled'] == true,
    httpUrl: _shape.optionalString(map['http_url']),
    httpsUrl: _shape.optionalString(map['https_url']),
    fingerprint: _shape.optionalString(map['fingerprint']),
    notAfter: _parseDateTime(map['not_after']),
    source: _shape.optionalString(map['source']),
    names: _stringList(map['names']),
    coversHost: map['covers_host'] == true,
    host: _shape.optionalString(map['host']),
  );
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) return null;
  try {
    return DateTime.parse(_shape.string(value));
  } catch (_) {
    return null;
  }
}

DeveloperQuota _parseQuota(Object? value) {
  final map = _shape.map(value);
  return DeveloperQuota(
    deviceLimit: _optInt(map['device_limit'], 1),
    maxDeviceLimit: _optInt(map['max_device_limit'], 10),
    smsHourlyLimit: _optInt(map['sms_hourly_limit'], 20),
    maxSmsHourlyLimit: _optInt(map['max_sms_hourly_limit'], 20),
  );
}

(String, List<String>) _channelUrlsFromMap(Map<Object?, Object?> map) {
  final urls = map['urls'];
  if (urls is List<Object?>) {
    final cleaned = [
      for (final item in urls)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
    if (cleaned.isEmpty) return ('', const <String>[]);
    return (cleaned.first, List<String>.unmodifiable(cleaned.skip(1)));
  }
  return (_shape.optionalString(map['url']), const <String>[]);
}

List<String> _encodeUrls(NotifyChannelSettings settings) {
  final first = settings.url.trim();
  final extras = [
    for (final item in settings.extraUrls)
      if (item.trim().isNotEmpty) item.trim(),
  ];
  if (first.isEmpty) return List<String>.unmodifiable(extras);
  return <String>[first, ...extras];
}

String _joinAddresses(Object? value) {
  if (value is List<Object?>) {
    return value.whereType<String>().join(', ');
  }
  return _shape.optionalString(value);
}

List<String> _stringList(Object? value) {
  if (value == null) return const <String>[];
  return List<String>.unmodifiable(
    _shape.list(value).whereType<String>().map((item) => item.trim()),
  );
}

String _optString(Object? value, String fallback) {
  if (value == null) return fallback;
  return _shape.string(value);
}

int _optInt(Object? value, int fallback) {
  if (value == null) return fallback;
  return _shape.integralInt(value);
}

final class SettingsDtoException implements DtoShapeException {
  const SettingsDtoException();
}

const _shape = JsonShape(SettingsDtoException.new);
