import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/features/esim/data/esim_repository.dart';
import 'package:onewifi_android/features/esim/domain/card_policy.dart';
import 'package:onewifi_android/features/esim/domain/esim.dart';
import 'package:onewifi_android/features/esim/state/esim_controller.dart';

// B1-04：仓储返回 verified=false 时 onSuccess 返回 null 且不落终态，按钮永久 busy。
// 生产 EsimApi 会先抛错，这条只兜控制器契约。
void main() {
  test('switchProfile 收到 verified=false 后不得停在 submitting', () async {
    final repository = _Repository();
    final controller = EsimController(
      deviceId: 'device-o1',
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final profile = controller.inventory.lastGoodData!.profiles.single;

    final pending = controller.switchProfile(profile);
    repository.switchResult.complete(
      const EsimSwitchResult(
        status: EsimSwitchStatus.switched,
        verified: false,
      ),
    );
    await pending;

    expect(controller.switchAction.status, isNot(ActionStatus.submitting));
  });

  test('verified=false 之后再点切卡必须再次发出请求', () async {
    final repository = _Repository();
    final controller = EsimController(
      deviceId: 'device-o1',
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final profile = controller.inventory.lastGoodData!.profiles.single;

    final first = controller.switchProfile(profile);
    repository.switchResult.complete(
      const EsimSwitchResult(
        status: EsimSwitchStatus.switched,
        verified: false,
      ),
    );
    await first;
    expect(repository.switchCalls, 1);

    repository.resetSwitch();
    final second = controller.switchProfile(profile);
    expect(repository.switchCalls, 2);
    repository.switchResult.complete(
      const EsimSwitchResult(status: EsimSwitchStatus.switched, verified: true),
    );
    await second;
  });
}

final class _Target implements EsimSwitchTarget {
  const _Target();
}

EsimProfile _profile() => const EsimProfile(
  name: 'Travel',
  provider: 'Carrier',
  iccidDisplay: '•••• 1234',
  active: false,
  state: EsimProfileState.disabled,
  target: _Target(),
);

EsimInventory _inventory() => EsimInventory(
  hint: EsimInventoryHint.none,
  profiles: <EsimProfile>[_profile()],
);

final class _Repository implements EsimRepository {
  Completer<EsimSwitchResult> switchResult = Completer<EsimSwitchResult>();
  int switchCalls = 0;

  void resetSwitch() => switchResult = Completer<EsimSwitchResult>();

  @override
  Future<EsimInventory> fetchProfiles(
    String deviceId, {
    required bool refresh,
    RequestCancellation? cancellation,
  }) async => _inventory();

  @override
  Future<EsimSwitchResult> switchProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) {
    switchCalls += 1;
    return switchResult.future;
  }

  @override
  Future<CardPolicy> fetchPolicy(
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async => const CardPolicy(apn: 'ims', ipVersion: CardIpVersion.ipv4v6);

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
  }) async => CardPolicy(apn: apn, ipVersion: ipVersion);

  @override
  Future<void> downloadProfile(
    String deviceId, {
    required String smdp,
    String matchingId = '',
    String confirmationCode = '',
    String aidHex = '',
    void Function(EsimDownloadProgress progress)? onProgress,
    RequestCancellation? cancellation,
  }) async {}

  @override
  String aidHexOf(EsimSwitchTarget target) => '';

  @override
  Future<void> renameProfile(
    String deviceId,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<void> disableProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {}

  @override
  Future<void> deleteProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {}
}
