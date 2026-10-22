import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/gateway_settings.dart';
import 'activation_channel.dart';

/// 产品授权：生产走原生通道打阿里云；测试用内存实现。
abstract interface class ProductLicenseStore {
  Future<ProductLicense> read();

  Future<void> write(ProductLicense license);

  Future<ProductLicense> activate(String key);

  Future<ProductLicense> deactivate();
}

final class LicenseActivateException implements Exception {
  LicenseActivateException(this.message);

  final String message;

  @override
  String toString() => message;
}

ProductLicenseStore createProductLicenseStore() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return SharedPreferencesProductLicenseStore();
  }
  return ChannelProductLicenseStore();
}

final class MemoryProductLicenseStore implements ProductLicenseStore {
  MemoryProductLicenseStore([this._license = const ProductLicense()]);

  ProductLicense _license;

  @override
  Future<ProductLicense> read() async => _license;

  @override
  Future<void> write(ProductLicense license) async {
    _license = license;
  }

  @override
  Future<ProductLicense> activate(String key) async {
    final next = ProductLicense(key: key.trim(), activated: true);
    await write(next);
    return next;
  }

  @override
  Future<ProductLicense> deactivate() async {
    const next = ProductLicense();
    await write(next);
    return next;
  }
}

final class ChannelProductLicenseStore implements ProductLicenseStore {
  @override
  Future<ProductLicense> read() async {
    final state = await ActivationChannel.tryGetState();
    if (state == null) {
      throw LicenseReadException('无法读取激活状态');
    }
    return ProductLicense(
      key: state.code?.trim() ?? '',
      activated: state.activated,
      membershipBadge: state.membershipBadge?.trim() ?? '',
    );
  }

  @override
  Future<void> write(ProductLicense license) async {
    if (!license.activated) {
      await ActivationChannel.deactivate();
    }
  }

  @override
  Future<ProductLicense> activate(String key) async {
    final result = await ActivationChannel.activate(key.trim());
    if (!result.ok) {
      throw LicenseActivateException(result.message ?? '授权绑定失败');
    }
    return ProductLicense(
      key: (result.code ?? key).trim(),
      activated: result.activated,
    );
  }

  @override
  Future<ProductLicense> deactivate() async {
    final result = await ActivationChannel.deactivate();
    if (!result.ok) {
      throw LicenseActivateException(result.message ?? '解除激活失败');
    }
    return const ProductLicense();
  }
}

final class SharedPreferencesProductLicenseStore
    implements ProductLicenseStore {
  SharedPreferencesProductLicenseStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String storageKey = 'onewifi.product-license';

  final SharedPreferencesAsync _preferences;

  @override
  Future<ProductLicense> read() async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return const ProductLicense();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const ProductLicense();
      final key = decoded['key'] is String
          ? (decoded['key'] as String).trim()
          : '';
      final activated = decoded['activated'] == true && key.isNotEmpty;
      return ProductLicense(key: key, activated: activated);
    } on FormatException {
      return const ProductLicense();
    }
  }

  @override
  Future<void> write(ProductLicense license) async {
    final key = license.key.trim();
    await _preferences.setString(
      storageKey,
      jsonEncode(<String, Object?>{
        'key': key,
        'activated': license.activated && key.isNotEmpty,
      }),
    );
  }

  @override
  Future<ProductLicense> activate(String key) async {
    final next = ProductLicense(key: key.trim(), activated: true);
    await write(next);
    return next;
  }

  @override
  Future<ProductLicense> deactivate() async {
    const next = ProductLicense();
    await write(next);
    return next;
  }
}
