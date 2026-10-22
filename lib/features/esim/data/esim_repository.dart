import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../domain/card_policy.dart';
import '../domain/esim.dart';
import '../domain/euicc_hardware.dart';
import 'esim_api.dart';

/// eUICC 总览读取器（硅片身份 + 缓存 profile 名）。独立于 [EsimRepository]
/// 接口，是为了让既有的仓储假实现（测试）无需跟着改；缺省为 null 时页面只是
/// 不显示铭牌 / 容量，联系人卡回退到 ICCID 尾号。
typedef EuiccOverviewLoader =
    Future<EuiccOverview> Function(
      String deviceId, {
      RequestCancellation? cancellation,
    });

abstract interface class EsimRepository {
  Future<EsimInventory> fetchProfiles(
    String deviceId, {
    required bool refresh,
    RequestCancellation? cancellation,
  });

  Future<EsimSwitchResult> switchProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  });

  Future<CardPolicy> fetchPolicy(
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  });

  Future<CardPolicy> savePolicy(
    EsimSwitchTarget target, {
    required String apn,
    required CardIpVersion ipVersion,
    bool? networkEnabled,
    bool? vowifiEnabled,
    bool? airplaneEnabled,
    String? mbnProfile,
    CardVoicePath? voicePath,
    RequestCancellation? cancellation,
  });

  Future<void> downloadProfile(
    String deviceId, {
    required String smdp,
    String matchingId,
    String confirmationCode,
    String aidHex,
    void Function(EsimDownloadProgress progress)? onProgress,
    RequestCancellation? cancellation,
  });

  Future<void> renameProfile(
    String deviceId,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  });

  Future<void> disableProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  });

  Future<void> deleteProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  });

  String aidHexOf(EsimSwitchTarget target);
}

final class DefaultEsimRepository implements EsimRepository {
  const DefaultEsimRepository(this._api);
  final EsimApi _api;

  /// Used by eSIM notifications screen (BL-OPT-11 / DEBT-D3).
  EsimApi get api => _api;

  @override
  Future<EsimInventory> fetchProfiles(
    String deviceId, {
    required bool refresh,
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-esim-response', () async {
      final dto = await _api.fetchProfiles(
        deviceId,
        refresh: refresh,
        cancellation: cancellation,
      );
      return EsimInventory(
        hint: dto.hint,
        profiles: dto.profiles.map(_profileFromDto).toList(growable: false),
      );
    });
  }

  @override
  Future<EsimSwitchResult> switchProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-esim-response', () async {
      return await _api.switchProfile(
        deviceId,
        target,
        cancellation: cancellation,
      );
    });
  }

  @override
  Future<CardPolicy> fetchPolicy(
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-esim-response', () async {
      return await _api.fetchPolicy(target, cancellation: cancellation);
    });
  }

  @override
  Future<CardPolicy> savePolicy(
    EsimSwitchTarget target, {
    required String apn,
    required CardIpVersion ipVersion,
    bool? networkEnabled,
    bool? vowifiEnabled,
    bool? airplaneEnabled,
    String? mbnProfile,
    CardVoicePath? voicePath,
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-esim-response', () async {
      return await _api.savePolicy(
        target,
        apn: apn,
        ipVersion: ipVersion,
        networkEnabled: networkEnabled,
        vowifiEnabled: vowifiEnabled,
        airplaneEnabled: airplaneEnabled,
        mbnProfile: mbnProfile,
        voicePath: voicePath,
        cancellation: cancellation,
      );
    });
  }

  @override
  Future<void> downloadProfile(
    String deviceId, {
    required String smdp,
    String matchingId = '',
    String confirmationCode = '',
    String aidHex = '',
    void Function(EsimDownloadProgress progress)? onProgress,
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-esim-response', () async {
      await _api.downloadProfile(
        deviceId,
        smdp: smdp,
        matchingId: matchingId,
        confirmationCode: confirmationCode,
        aidHex: aidHex,
        onProgress: onProgress,
        cancellation: cancellation,
      );
    });
  }

  @override
  String aidHexOf(EsimSwitchTarget target) => EsimApi.aidHexOf(target);

  @override
  Future<void> renameProfile(
    String deviceId,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  }) {
    return guardShape('local-esim-response', () {
      return _api.renameProfile(
        deviceId,
        target,
        name: name,
        cancellation: cancellation,
      );
    });
  }

  @override
  Future<void> disableProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) {
    return guardShape('local-esim-response', () {
      return _api.disableProfile(deviceId, target, cancellation: cancellation);
    });
  }

  @override
  Future<void> deleteProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) {
    return guardShape('local-esim-response', () {
      return _api.deleteProfile(deviceId, target, cancellation: cancellation);
    });
  }

  Future<EuiccOverview> fetchOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    return guardShape('local-esim-response', () async {
      final dto = await _api.fetchOverview(
        deviceId,
        cancellation: cancellation,
      );
      return EuiccOverview(
        hardware: dto.hardware,
        profiles: dto.profiles.map(_profileFromDto).toList(growable: false),
      );
    });
  }

  static EsimProfile _profileFromDto(EsimProfileDto profile) => EsimProfile(
    name: profile.name,
    provider: profile.provider,
    iccidDisplay: profile.iccidDisplay,
    active: profile.active,
    state: profile.state,
    locked: profile.locked,
    stateText: profile.stateText,
    eidDisplay: profile.eidDisplay,
    target: profile.target,
  );
}
