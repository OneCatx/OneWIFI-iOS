import '../../../core/http/http_transport.dart';
import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../../../core/state/state_failure.dart';
import '../data/esim_api.dart';
import '../data/esim_repository.dart';
import '../domain/card_policy.dart';
import '../domain/esim.dart';
import '../domain/euicc_hardware.dart';
import '../domain/lpa_activation.dart';

final class EsimController extends RequestNotifier {
  factory EsimController({
    required String deviceId,
    required EsimRepository repository,
    required RequestRegistry requestRegistry,
    EuiccOverviewLoader? overviewLoader,
  }) => EsimController._(deviceId, repository, requestRegistry, overviewLoader);

  EsimController._(
    this.deviceId,
    this._repository,
    RequestRegistry requestRegistry,
    this._overviewLoader,
  ) : _read = RequestSlot(requestRegistry, 'esim.inventory:$deviceId'),
      _hardwareRead = RequestSlot(requestRegistry, 'esim.hardware:$deviceId'),
      _switch = RequestSlot(requestRegistry, 'esim.switch:$deviceId'),
      _policyRead = RequestSlot(requestRegistry, 'esim.policy:$deviceId'),
      _policySave = RequestSlot(requestRegistry, 'esim.policy.save:$deviceId'),
      _policyPeek = RequestSlot(requestRegistry, 'esim.policy.peek:$deviceId'),
      _download = RequestSlot(requestRegistry, 'esim.download:$deviceId'),
      _mutate = RequestSlot(requestRegistry, 'esim.mutate:$deviceId'),
      _inventory = QueryState<EsimInventory>.initial(
        key: 'esim.inventory:$deviceId',
      ),
      _hardware = QueryState<List<EuiccHardware>>.initial(
        key: 'esim.hardware:$deviceId',
      ),
      _policy = QueryState<CardPolicy>.initial(key: 'esim.policy:$deviceId');

  final String deviceId;
  final EsimRepository _repository;

  /// Backend API for eSIM notification rules when repository is default.
  EsimApi? get esimApi {
    final repository = _repository;
    return repository is DefaultEsimRepository ? repository.api : null;
  }

  final EuiccOverviewLoader? _overviewLoader;
  final RequestSlot _read;
  final RequestSlot _hardwareRead;
  final RequestSlot _switch;
  final RequestSlot _policyRead;
  final RequestSlot _policySave;
  final RequestSlot _policyPeek;
  final RequestSlot _download;
  final RequestSlot _mutate;
  QueryState<EsimInventory> _inventory;
  QueryState<List<EuiccHardware>> _hardware;
  QueryState<CardPolicy> _policy;
  ActionState _switchAction = const ActionState.idle();
  ActionState _policyAction = const ActionState.idle();
  EsimSwitchTarget? _policyActionTarget;
  ActionState _downloadAction = const ActionState.idle();
  ActionState _mutateAction = const ActionState.idle();
  EsimDownloadProgress? _downloadProgress;

  QueryState<EsimInventory> get inventory => _inventory;

  /// eUICC 硅片身份（厂商 / 容量 / 铭牌）。与 profile 列表分开失败：
  /// 读不到硬件不影响切卡。
  QueryState<List<EuiccHardware>> get hardware => _hardware;
  QueryState<CardPolicy> get policy => _policy;
  ActionState get switchAction => _switchAction;
  ActionState get policyAction => _policyAction;
  EsimSwitchTarget? get policyActionTarget => _policyActionTarget;
  ActionState get downloadAction => _downloadAction;
  ActionState get mutateAction => _mutateAction;
  EsimDownloadProgress? get downloadProgress => _downloadProgress;

  EsimSwitchTarget? get policyTarget {
    final profiles = _inventory.lastGoodData?.profiles;
    if (profiles == null || profiles.isEmpty) return null;
    for (final profile in profiles) {
      if (profile.active) return profile.target;
    }
    return profiles.first.target;
  }

  @override
  List<RequestSlot> get slots => <RequestSlot>[
    _read,
    _hardwareRead,
    _switch,
    _policyRead,
    _policySave,
    _policyPeek,
    _download,
    _mutate,
  ];

  Future<void> load() => _readAll(refresh: false);
  Future<void> readChip() => _readAll(refresh: true);

  Future<void> _readAll({required bool refresh}) => Future.wait<void>(
    <Future<void>>[_readInventory(refresh: refresh), _readHardware()],
  );

  Future<void> _readHardware() async {
    final loader = _overviewLoader;
    if (loader == null) return;
    await runQuery<List<EuiccHardware>>(
      slot: _hardwareRead,
      current: () => _hardware,
      set: _setHardware,
      fetch: (ticket) async =>
          (await loader(deviceId, cancellation: ticket.cancellation)).hardware,
      isEmpty: (result) => result.isEmpty,
    );
  }

  Future<bool> switchProfile(EsimProfile profile) async {
    if (profile.active) return false;
    final completed = await runAction<EsimSwitchResult>(
      slot: _switch,
      current: () => _switchAction,
      set: _setSwitch,
      request: (ticket) => _repository.switchProfile(
        deviceId,
        profile.target,
        cancellation: ticket.cancellation,
      ),
      onSuccess: (result, _) async {
        if (!result.verified) {
          return ActionState.failed(
            knownFailure: const StateFailure(StateFailureKind.generic),
          );
        }
        await _readInventory(refresh: false);
        return const ActionState.succeeded();
      },
    );
    return completed && _switchAction.status == ActionStatus.succeeded;
  }

  /// Returns true only when this invocation submitted and confirmed its save.
  Future<bool> savePolicy({
    required String apn,
    required CardIpVersion ipVersion,
    EsimSwitchTarget? target,
    bool? networkEnabled,
    bool? vowifiEnabled,
    bool? airplaneEnabled,
    String? mbnProfile,
    CardVoicePath? voicePath,
  }) async {
    final resolved = target ?? policyTarget;
    if (resolved == null ||
        isDisposed ||
        _policyAction.status == ActionStatus.submitting) {
      return false;
    }
    _policyActionTarget = resolved;
    return runAction<CardPolicy>(
      slot: _policySave,
      current: () => _policyAction,
      set: _setPolicyAction,
      request: (ticket) => _repository.savePolicy(
        resolved,
        apn: apn,
        ipVersion: ipVersion,
        networkEnabled: networkEnabled,
        vowifiEnabled: vowifiEnabled,
        airplaneEnabled: airplaneEnabled,
        mbnProfile: mbnProfile,
        voicePath: voicePath,
        cancellation: ticket.cancellation,
      ),
      onSuccess: (saved, _) {
        if (resolved == policyTarget) {
          // A read begun before this save cannot roll the confirmed value back.
          _policyRead.cancel();
          _setPolicy(
            QueryState<CardPolicy>.data(data: saved, key: _policyRead.key),
          );
        }
        return const ActionState.succeeded();
      },
    );
  }

  /// 只读探测某张卡的策略，不进 [policy] 状态、不通知。
  /// dispose / 取消 / 被后续调用顶替时返回 `null`；正常失败照常抛出。
  Future<CardPolicy?> peekPolicy(EsimProfile profile) async {
    if (isDisposed) return null;
    final ticket = _policyPeek.begin();
    try {
      final policy = await _repository.fetchPolicy(
        profile.target,
        cancellation: ticket.cancellation,
      );
      return ticket.isCurrent ? policy : null;
    } catch (_) {
      if (!ticket.isCurrent) return null;
      rethrow;
    } finally {
      ticket.end();
    }
  }

  Future<bool> renameProfile(EsimProfile profile, String name) {
    return _mutateProfile(
      (cancellation) => _repository.renameProfile(
        deviceId,
        profile.target,
        name: name,
        cancellation: cancellation,
      ),
    );
  }

  Future<bool> disableProfile(EsimProfile profile) {
    if (!profile.active) return Future<bool>.value(false);
    return _mutateProfile(
      (cancellation) => _repository.disableProfile(
        deviceId,
        profile.target,
        cancellation: cancellation,
      ),
    );
  }

  Future<bool> deleteProfile(EsimProfile profile) {
    if (!profile.canDelete) return Future<bool>.value(false);
    return _mutateProfile(
      (cancellation) => _repository.deleteProfile(
        deviceId,
        profile.target,
        cancellation: cancellation,
      ),
    );
  }

  Future<bool> _mutateProfile(
    Future<void> Function(RequestCancellation? cancellation) body,
  ) async {
    return runAction<void>(
      slot: _mutate,
      current: () => _mutateAction,
      set: _setMutate,
      request: (ticket) => body(ticket.cancellation),
      onSuccess: (_, _) async {
        await _readInventory(refresh: false);
        return const ActionState.succeeded();
      },
    );
  }

  Future<void> download(String activationCode) async {
    if (isDisposed || _downloadAction.status == ActionStatus.submitting) {
      return;
    }
    final activation = parseLpaActivationCode(activationCode);
    if (!activation.hasSmdp) {
      _downloadProgress = const EsimDownloadProgress(
        step: 'error',
        message: '需要有效的 SM-DP+ 地址或 LPA 激活码',
        percent: -1,
      );
      _setDownload(
        ActionState.failed(
          knownFailure: const StateFailure(StateFailureKind.generic),
        ),
      );
      return;
    }
    final target = policyTarget;
    final ticket = _download.begin();
    _downloadProgress = const EsimDownloadProgress(
      step: 'start',
      message: '开始下载',
      percent: 0,
    );
    _setDownload(const ActionState.submitting());
    try {
      await _repository.downloadProfile(
        deviceId,
        smdp: activation.smdp,
        matchingId: activation.matchingId,
        confirmationCode: activation.confirmationCode,
        aidHex: target == null ? '' : _repository.aidHexOf(target),
        onProgress: (progress) {
          if (!ticket.isCurrent) return;
          _downloadProgress = progress;
          notifyListeners();
        },
        cancellation: ticket.cancellation,
      );
      if (!ticket.isCurrent) return;
      _setDownload(const ActionState.succeeded());
      await _readInventory(refresh: false);
    } on EsimDownloadFailed catch (error) {
      if (!ticket.isCurrent) return;
      _downloadProgress = EsimDownloadProgress(
        step: 'error',
        message: error.message,
        percent: -1,
      );
      _setDownload(
        ActionState.failed(
          knownFailure: const StateFailure(StateFailureKind.generic),
        ),
      );
    } catch (error) {
      if (!ticket.isCurrent) return;
      _setDownload(ActionState.fromError(error));
    } finally {
      ticket.end();
    }
  }

  void cancelDownload() {
    if (!_download.isActive) return;
    _download.cancel();
    _setDownload(const ActionState.idle());
  }

  Future<void> _loadPolicy() async {
    final target = policyTarget;
    if (target == null) return;
    await runQuery<CardPolicy>(
      slot: _policyRead,
      current: () => _policy,
      set: _setPolicy,
      fetch: (ticket) =>
          _repository.fetchPolicy(target, cancellation: ticket.cancellation),
    );
  }

  Future<void> _readInventory({required bool refresh}) =>
      runQuery<EsimInventory>(
        slot: _read,
        current: () => _inventory,
        set: _setInventory,
        fetch: (ticket) => _repository.fetchProfiles(
          deviceId,
          refresh: refresh,
          cancellation: ticket.cancellation,
        ),
        isEmpty: (result) =>
            result.profiles.isEmpty && result.hint == EsimInventoryHint.none,
        onData: (_, _) => _loadPolicy(),
      );

  void _setInventory(QueryState<EsimInventory> next) => publish(() {
    final previousTarget = policyTarget;
    _inventory = next;
    if (previousTarget != policyTarget) {
      _policyRead.cancel();
      _policy = QueryState<CardPolicy>.initial(key: _policyRead.key);
    }
  });

  void _setHardware(QueryState<List<EuiccHardware>> next) =>
      publish(() => _hardware = next);

  void _setSwitch(ActionState next) => publish(() => _switchAction = next);

  void _setPolicy(QueryState<CardPolicy> next) => publish(() => _policy = next);

  void _setPolicyAction(ActionState next) =>
      publish(() => _policyAction = next);

  void _setDownload(ActionState next) => publish(() => _downloadAction = next);

  void _setMutate(ActionState next) => publish(() => _mutateAction = next);
}
