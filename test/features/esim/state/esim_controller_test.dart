import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/esim/data/esim_repository.dart';
import 'package:onewifi_android/features/esim/domain/card_policy.dart';
import 'package:onewifi_android/features/esim/domain/esim.dart';
import 'package:onewifi_android/features/esim/state/esim_controller.dart';

void main() {
  test(
    'loads, switches once, and refreshes only after verified success',
    () async {
      final repository = _Repository();
      final controller = EsimController(
        deviceId: 'device-a',
        repository: repository,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.inventory.status, QueryStatus.data);
      final profile = controller.inventory.lastGoodData!.profiles.single;

      final pending = controller.switchProfile(profile);
      expect(controller.switchAction.status, ActionStatus.submitting);
      controller.switchProfile(profile);
      expect(repository.switchCalls, 1);
      repository.switchResult.complete(
        const EsimSwitchResult(
          status: EsimSwitchStatus.switched,
          verified: true,
        ),
      );
      await pending;

      expect(controller.switchAction.status, ActionStatus.succeeded);
      expect(repository.reads, <bool>[false, false]);
    },
  );

  test(
    'timeout is an unknown outcome and dispose cancels pending reads',
    () async {
      final repository = _Repository(timeoutSwitch: true, blockRead: true);
      final registry = RequestRegistry();
      final controller = EsimController(
        deviceId: 'device-b',
        repository: repository,
        requestRegistry: registry,
      );
      final load = controller.load();
      await Future<void>.delayed(Duration.zero);
      expect(repository.readCancellation, isNotNull);
      controller.dispose();
      expect(repository.readCancellation!.isCancelled, isTrue);
      repository.readResult.complete(_inventory());
      await load;

      final switchController = EsimController(
        deviceId: 'device-c',
        repository: repository,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(switchController.dispose);
      await switchController.switchProfile(_profile());
      expect(switchController.switchAction.status, ActionStatus.failed);
      expect(switchController.switchAction.isUnknownOutcome, isTrue);
    },
  );

  test(
    'dispose cancels an in-flight switch and ignores late success',
    () async {
      final repository = _Repository();
      final controller = EsimController(
        deviceId: 'device-d',
        repository: repository,
        requestRegistry: RequestRegistry(),
      );
      final pending = controller.switchProfile(_profile());
      await Future<void>.delayed(Duration.zero);
      expect(repository.switchCancellation, isNotNull);

      controller.dispose();
      expect(repository.switchCancellation!.isCancelled, isTrue);
      repository.switchResult.complete(
        const EsimSwitchResult(
          status: EsimSwitchStatus.switched,
          verified: true,
        ),
      );
      await pending;
    },
  );

  test(
    'download is single-flight and never retries a failed LPA paste',
    () async {
      final repository = _Repository();
      final controller = EsimController(
        deviceId: 'device-a',
        repository: repository,
        requestRegistry: RequestRegistry(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.download('not-a-host');
      expect(repository.downloadCalls, 1);
      await controller.download('not-a-host');
      expect(repository.downloadCalls, 2);

      controller.download('');
      controller.download('');
      expect(repository.downloadCalls, 2);
      expect(controller.downloadAction.status, ActionStatus.failed);
    },
  );

  test('rename and delete refresh inventory; disable skips inactive', () async {
    final repository = _Repository();
    final controller = EsimController(
      deviceId: 'device-mutate',
      repository: repository,
      requestRegistry: RequestRegistry(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final profile = controller.inventory.lastGoodData!.profiles.single;

    await controller.renameProfile(profile, 'Desk line');
    expect(repository.renameCalls, 1);
    expect(repository.renamedTo, 'Desk line');
    expect(controller.mutateAction.status, ActionStatus.succeeded);

    await controller.deleteProfile(profile);
    expect(repository.deleteCalls, 1);

    await controller.disableProfile(profile);
    expect(repository.disableCalls, 0);

    final active = EsimProfile(
      name: profile.name,
      provider: profile.provider,
      iccidDisplay: profile.iccidDisplay,
      active: true,
      state: EsimProfileState.enabled,
      target: profile.target,
    );
    await controller.disableProfile(active);
    expect(repository.disableCalls, 1);
    await controller.deleteProfile(active);
    expect(repository.deleteCalls, 1);
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
  _Repository({this.timeoutSwitch = false, this.blockRead = false});
  final bool timeoutSwitch;
  final bool blockRead;
  final Completer<EsimInventory> readResult = Completer<EsimInventory>();
  final Completer<EsimSwitchResult> switchResult =
      Completer<EsimSwitchResult>();
  final List<bool> reads = <bool>[];
  int switchCalls = 0;
  int downloadCalls = 0;
  int renameCalls = 0;
  int disableCalls = 0;
  int deleteCalls = 0;
  String? renamedTo;
  String? downloadSmdp;
  RequestCancellation? readCancellation;
  RequestCancellation? switchCancellation;

  @override
  Future<EsimInventory> fetchProfiles(
    String deviceId, {
    required bool refresh,
    RequestCancellation? cancellation,
  }) {
    reads.add(refresh);
    readCancellation = cancellation;
    if (blockRead && !readResult.isCompleted) return readResult.future;
    return Future<EsimInventory>.value(_inventory());
  }

  @override
  Future<EsimSwitchResult> switchProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) {
    switchCalls += 1;
    switchCancellation = cancellation;
    if (timeoutSwitch) {
      throw const ApiFailure(ApiFailureKind.timeout, requestId: 'safe-timeout');
    }
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
  }) async {
    downloadCalls += 1;
    downloadSmdp = smdp;
  }

  @override
  String aidHexOf(EsimSwitchTarget target) => '';

  @override
  Future<void> renameProfile(
    String deviceId,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  }) async {
    renameCalls += 1;
    renamedTo = name;
  }

  @override
  Future<void> disableProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    disableCalls += 1;
  }

  @override
  Future<void> deleteProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    deleteCalls += 1;
  }
}
