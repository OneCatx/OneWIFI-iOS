import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/query_state.dart';
import 'package:onewifi_android/features/esim/data/esim_repository.dart';
import 'package:onewifi_android/features/esim/domain/card_policy.dart';
import 'package:onewifi_android/features/esim/domain/esim.dart';
import 'package:onewifi_android/features/esim/domain/euicc_hardware.dart';
import 'package:onewifi_android/features/esim/state/esim_controller.dart';

const String _activationCode = r'LPA:1$smdp.example.com$MATCH-1';
const ApiFailure _lateFailure = ApiFailure(
  ApiFailureKind.timeout,
  requestId: 'late',
);

void main() {
  group('after dispose()', () {
    test('load() completes silently', () async {
      final h = await _Harness.loaded();
      h.dispose();

      await expectLater(h.controller.load(), completes);

      h.expectSilent();
      expect(h.controller.inventory.status, QueryStatus.data);
      expect(h.controller.hardware.status, QueryStatus.data);
      expect(h.controller.policy.status, QueryStatus.data);
    });

    test('readChip() completes silently', () async {
      final h = await _Harness.loaded();
      h.dispose();

      await expectLater(h.controller.readChip(), completes);

      h.expectSilent();
      expect(h.controller.inventory.status, QueryStatus.data);
      expect(h.controller.hardware.status, QueryStatus.data);
    });

    test('switchProfile() on an inactive profile completes silently', () async {
      final h = await _Harness.loaded();
      h.dispose();

      await expectLater(h.controller.switchProfile(_profile()), completes);

      h.expectSilent();
      expect(h.controller.switchAction.status, ActionStatus.idle);
    });

    test('savePolicy() with a resolvable target completes silently', () async {
      final h = await _Harness.loaded();
      expect(h.controller.policyTarget, isNotNull);
      h.dispose();

      await expectLater(
        h.controller.savePolicy(apn: 'new-apn', ipVersion: CardIpVersion.ip),
        completes,
      );

      h.expectSilent();
      expect(h.controller.policyAction.status, ActionStatus.idle);
      expect(h.controller.policy.lastGoodData?.apn, 'ims');
    });

    test('peekPolicy() completes with null silently', () async {
      final h = await _Harness.loaded();
      h.dispose();

      final pending = h.controller.peekPolicy(_profile());
      await expectLater(pending, completes);

      h.expectSilent();
      expect(await pending, isNull);
      expect(h.controller.policy.status, QueryStatus.data);
      expect(h.controller.policyAction.status, ActionStatus.idle);
    });

    test('renameProfile() completes silently', () async {
      final h = await _Harness.loaded();
      h.dispose();

      await expectLater(
        h.controller.renameProfile(_profile(), 'Desk line'),
        completes,
      );

      h.expectSilent();
      expect(h.controller.mutateAction.status, ActionStatus.idle);
    });

    test('disableProfile() on an active profile completes silently', () async {
      final h = await _Harness.loaded();
      h.dispose();

      await expectLater(
        h.controller.disableProfile(_profile(active: true)),
        completes,
      );

      h.expectSilent();
      expect(h.controller.mutateAction.status, ActionStatus.idle);
    });

    test('deleteProfile() on a deletable profile completes silently', () async {
      final h = await _Harness.loaded();
      expect(_profile().canDelete, isTrue);
      h.dispose();

      await expectLater(h.controller.deleteProfile(_profile()), completes);

      h.expectSilent();
      expect(h.controller.mutateAction.status, ActionStatus.idle);
    });

    test(
      'download() with a valid activation code completes silently',
      () async {
        final h = await _Harness.loaded();
        h.dispose();

        await expectLater(h.controller.download(_activationCode), completes);

        h.expectSilent();
        expect(h.controller.downloadAction.status, ActionStatus.idle);
        expect(h.controller.downloadProgress, isNull);
      },
    );

    test('cancelDownload() returns normally without a notification', () async {
      final h = await _Harness.loaded();
      h.dispose();

      expect(h.controller.cancelDownload, returnsNormally);
      await pumpEventQueue();

      h.expectSilent();
      expect(h.controller.downloadAction.status, ActionStatus.idle);
    });

    test(
      'cancelDownload() with a download left in flight returns normally',
      () async {
        final h = await _Harness.loaded();
        h.repo.downloadGate = Completer<void>();
        final pending = h.controller.download(_activationCode);
        expect(h.controller.downloadAction.status, ActionStatus.submitting);
        h.dispose();

        expect(h.controller.cancelDownload, returnsNormally);
        await pumpEventQueue();
        h.repo.downloadGate!.complete();
        await expectLater(pending, completes);

        h.expectSilent();
        expect(h.controller.downloadAction.status, ActionStatus.submitting);
      },
    );
  });

  group('disposed while a request is in flight', () {
    test('load: late failure completes silently', () async {
      final h = _Harness();
      h.repo.readGate = Completer<EsimInventory>();
      final pending = h.controller.load();
      expect(h.repo.calls, contains('fetchProfiles'));
      expect(h.controller.inventory.status, QueryStatus.loading);
      h.dispose();

      h.repo.readGate!.completeError(_lateFailure);
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.inventory.status, QueryStatus.loading);
    });

    test('switchProfile: late failure completes silently', () async {
      final h = await _Harness.loaded();
      h.repo.switchGate = Completer<EsimSwitchResult>();
      final pending = h.controller.switchProfile(_profile());
      expect(h.controller.switchAction.status, ActionStatus.submitting);
      h.dispose();

      h.repo.switchGate!.completeError(_lateFailure);
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.switchAction.status, ActionStatus.submitting);
    });

    test('savePolicy: late success completes silently', () async {
      final h = await _Harness.loaded();
      h.repo.saveGate = Completer<CardPolicy>();
      final pending = h.controller.savePolicy(
        apn: 'new-apn',
        ipVersion: CardIpVersion.ip,
      );
      expect(h.controller.policyAction.status, ActionStatus.submitting);
      h.dispose();

      h.repo.saveGate!.complete(
        const CardPolicy(apn: 'new-apn', ipVersion: CardIpVersion.ip),
      );
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.policyAction.status, ActionStatus.submitting);
      expect(h.controller.policy.lastGoodData?.apn, 'ims');
    });

    test('peekPolicy: late success resolves to null silently', () async {
      final h = await _Harness.loaded();
      h.repo.calls.clear();
      h.repo.policyGate = Completer<CardPolicy>();
      final pending = h.controller.peekPolicy(_profile());
      expect(h.repo.calls, <String>['fetchPolicy']);
      h.dispose();

      h.repo.policyGate!.complete(
        const CardPolicy(apn: 'late-apn', ipVersion: CardIpVersion.ip),
      );
      await expectLater(pending, completes);

      h.expectSilent();
      expect(await pending, isNull);
      expect(h.controller.policy.lastGoodData?.apn, 'ims');
    });

    test('peekPolicy: late failure resolves to null silently', () async {
      final h = await _Harness.loaded();
      h.repo.calls.clear();
      h.repo.policyGate = Completer<CardPolicy>();
      final pending = h.controller.peekPolicy(_profile());
      expect(h.repo.calls, <String>['fetchPolicy']);
      h.dispose();

      h.repo.policyGate!.completeError(_lateFailure);
      await expectLater(pending, completes);

      h.expectSilent();
      expect(await pending, isNull);
    });

    test('renameProfile: late failure completes silently', () async {
      final h = await _Harness.loaded();
      h.repo.mutateGate = Completer<void>();
      final pending = h.controller.renameProfile(_profile(), 'Desk line');
      expect(h.controller.mutateAction.status, ActionStatus.submitting);
      h.dispose();

      h.repo.mutateGate!.completeError(_lateFailure);
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.mutateAction.status, ActionStatus.submitting);
    });

    test('download: late success completes silently and a late onProgress tick '
        'does not notify', () async {
      final h = await _Harness.loaded();
      h.repo.downloadGate = Completer<void>();
      final pending = h.controller.download(_activationCode);
      expect(h.controller.downloadAction.status, ActionStatus.submitting);
      expect(h.controller.downloadProgress?.step, 'start');
      expect(h.repo.onProgress, isNotNull);
      h.dispose();

      h.repo.onProgress!(
        const EsimDownloadProgress(
          step: 'download',
          message: '下载中',
          percent: 50,
        ),
      );
      expect(h.notifications, 0);
      expect(h.controller.downloadProgress?.step, 'start');

      h.repo.downloadGate!.complete();
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.downloadAction.status, ActionStatus.submitting);
      expect(h.controller.downloadProgress?.step, 'start');
    });

    test('download: late EsimDownloadFailed completes silently', () async {
      final h = await _Harness.loaded();
      h.repo.downloadGate = Completer<void>();
      final pending = h.controller.download(_activationCode);
      expect(h.controller.downloadAction.status, ActionStatus.submitting);
      h.dispose();

      h.repo.downloadGate!.completeError(const EsimDownloadFailed('late'));
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.downloadAction.status, ActionStatus.submitting);
      expect(h.controller.downloadProgress?.step, 'start');
    });

    test('download: late generic failure completes silently', () async {
      final h = await _Harness.loaded();
      h.repo.downloadGate = Completer<void>();
      final pending = h.controller.download(_activationCode);
      expect(h.controller.downloadAction.status, ActionStatus.submitting);
      h.dispose();

      h.repo.downloadGate!.completeError(_lateFailure);
      await expectLater(pending, completes);

      h.expectSilent();
      expect(h.controller.downloadAction.status, ActionStatus.submitting);
    });
  });

  group('dispose() twice', () {
    test('second dispose() returns normally without a notification', () async {
      final h = await _Harness.loaded();
      h.dispose();

      expect(h.controller.dispose, returnsNormally);
      await pumpEventQueue();

      h.expectSilent();
    });
  });

  group('peekPolicy() before dispose()', () {
    test('success returns the fetched policy without notifying', () async {
      const policy = CardPolicy(apn: 'peek-apn', ipVersion: CardIpVersion.ip);
      final h = await _Harness.loaded();
      h.repo.calls.clear();
      h.notifications = 0;
      h.repo.policyGate = Completer<CardPolicy>();
      final pending = h.controller.peekPolicy(_profile());

      h.repo.policyGate!.complete(policy);

      expect(await pending, same(policy));
      expect(h.repo.calls, <String>['fetchPolicy']);
      expect(h.notifications, 0);
      expect(h.controller.policy.lastGoodData?.apn, 'ims');
    });

    test('failure rethrows without notifying', () async {
      const failure = ApiFailure(ApiFailureKind.http, requestId: 'peek');
      final h = await _Harness.loaded();
      h.repo.calls.clear();
      h.notifications = 0;
      h.repo.policyGate = Completer<CardPolicy>();
      final pending = h.controller.peekPolicy(_profile());

      h.repo.policyGate!.completeError(failure);

      await expectLater(pending, throwsA(same(failure)));
      expect(h.repo.calls, <String>['fetchPolicy']);
      expect(h.notifications, 0);
      expect(h.controller.policy.lastGoodData?.apn, 'ims');
    });
  });
}

final class _Target implements EsimSwitchTarget {
  const _Target();
}

EsimProfile _profile({bool active = false}) => EsimProfile(
  name: 'Travel',
  provider: 'Carrier',
  iccidDisplay: '•••• 1234',
  active: active,
  state: active ? EsimProfileState.enabled : EsimProfileState.disabled,
  target: const _Target(),
);

EsimInventory _inventory() => EsimInventory(
  hint: EsimInventoryHint.none,
  profiles: <EsimProfile>[_profile()],
);

const EuiccHardware _hardware = EuiccHardware(
  index: 0,
  eidDisplay: '•••• 0001',
  chipMaker: 'Thales DIS France SAS',
  freeNvram: '',
  freeNvramBytes: null,
  nameplate: 'ESTK.me',
);

final class _Harness {
  _Harness() {
    controller = EsimController(
      deviceId: 'device-lifecycle',
      repository: repo,
      requestRegistry: RequestRegistry(),
      overviewLoader: _loadOverview,
    );
    controller.addListener(() => notifications++);
    addTearDown(controller.dispose);
  }

  static Future<_Harness> loaded() async {
    final h = _Harness();
    await h.controller.load();
    expect(h.controller.inventory.status, QueryStatus.data);
    expect(h.controller.hardware.status, QueryStatus.data);
    expect(h.controller.policy.status, QueryStatus.data);
    return h;
  }

  final _Repository repo = _Repository();
  late final EsimController controller;
  int notifications = 0;

  Future<EuiccOverview> _loadOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    repo.calls.add('overview');
    return EuiccOverview(
      hardware: const <EuiccHardware>[_hardware],
      profiles: const <EsimProfile>[],
    );
  }

  void dispose() {
    controller.dispose();
    notifications = 0;
    repo.calls.clear();
  }

  void expectSilent() {
    expect(notifications, 0);
    expect(repo.calls, isEmpty);
  }
}

final class _Repository implements EsimRepository {
  final List<String> calls = <String>[];
  Completer<EsimInventory>? readGate;
  Completer<EsimSwitchResult>? switchGate;
  Completer<CardPolicy>? policyGate;
  Completer<CardPolicy>? saveGate;
  Completer<void>? mutateGate;
  Completer<void>? downloadGate;
  void Function(EsimDownloadProgress progress)? onProgress;

  @override
  Future<EsimInventory> fetchProfiles(
    String deviceId, {
    required bool refresh,
    RequestCancellation? cancellation,
  }) {
    calls.add('fetchProfiles');
    final gate = readGate;
    if (gate != null) return gate.future;
    return Future<EsimInventory>.value(_inventory());
  }

  @override
  Future<EsimSwitchResult> switchProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) {
    calls.add('switchProfile');
    final gate = switchGate;
    if (gate != null) return gate.future;
    return Future<EsimSwitchResult>.value(
      const EsimSwitchResult(status: EsimSwitchStatus.switched, verified: true),
    );
  }

  @override
  Future<CardPolicy> fetchPolicy(
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) {
    calls.add('fetchPolicy');
    final gate = policyGate;
    if (gate != null) return gate.future;
    return Future<CardPolicy>.value(
      const CardPolicy(apn: 'ims', ipVersion: CardIpVersion.ipv4v6),
    );
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
  }) {
    calls.add('savePolicy');
    final gate = saveGate;
    if (gate != null) return gate.future;
    return Future<CardPolicy>.value(CardPolicy(apn: apn, ipVersion: ipVersion));
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
  }) {
    calls.add('downloadProfile');
    this.onProgress = onProgress;
    final gate = downloadGate;
    if (gate != null) return gate.future;
    return Future<void>.value();
  }

  @override
  String aidHexOf(EsimSwitchTarget target) {
    calls.add('aidHexOf');
    return '';
  }

  @override
  Future<void> renameProfile(
    String deviceId,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  }) {
    calls.add('renameProfile');
    return _mutate();
  }

  @override
  Future<void> disableProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) {
    calls.add('disableProfile');
    return _mutate();
  }

  @override
  Future<void> deleteProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) {
    calls.add('deleteProfile');
    return _mutate();
  }

  Future<void> _mutate() {
    final gate = mutateGate;
    if (gate != null) return gate.future;
    return Future<void>.value();
  }
}
