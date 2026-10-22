import 'dart:async';

import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../../../core/state/state_failure.dart';
import '../data/sms_repository.dart';
import '../domain/sms.dart';
import '../domain/sms_code_extractor.dart';
import 'remote_otp_controller.dart';

/// Manages SMS messages, contacts, threads, and OTP code extraction.
///
/// This controller handles:
/// - Loading and displaying SMS contacts
/// - Reading message threads for a selected contact
/// - Sending SMS messages
/// - Deleting messages
/// - Watching for incoming OTP codes and automatically forwarding them
/// - Remote OTP delivery integration
///
/// The controller includes an OTP watch loop that periodically polls for new
/// messages containing verification codes and forwards them to registered sinks.
final class SmsController extends RequestNotifier {
  /// Creates an [SmsController] with the specified dependencies.
  ///
  /// Parameters:
  /// - [repository]: Repository for SMS operations
  /// - [requestRegistry]: Registry for tracking and cancelling requests
  /// - [otpSink]: Optional sink for forwarding extracted OTP codes
  /// - [remoteOtp]: Optional controller for remote OTP delivery
  /// - [otpWatchInterval]: Polling interval for OTP watch loop
  factory SmsController({
    required SmsRepository repository,
    required RequestRegistry requestRegistry,
    SmsOtpSink? otpSink,
    RemoteOtpController? remoteOtp,
    Duration otpWatchInterval = const Duration(seconds: 8),
  }) => SmsController._(
    repository,
    requestRegistry,
    otpSink,
    remoteOtp,
    otpWatchInterval,
  );

  SmsController._(
    this._repository,
    RequestRegistry requestRegistry,
    this.otpSink,
    this.remoteOtp,
    this._otpWatchInterval,
  ) : _contactsRead = RequestSlot(requestRegistry, _contactsKey),
      _threadRead = RequestSlot(requestRegistry, _threadKey),
      _otpWatch = RequestSlot(requestRegistry, 'sms.otp.watch'),
      _send = RequestSlot(requestRegistry, 'sms.send'),
      _delete = RequestSlot(requestRegistry, 'sms.delete');

  static const String _contactsKey = 'sms.contacts';
  static const String _threadKey = 'sms.thread';

  final SmsRepository _repository;
  final SmsOtpSink? otpSink;
  final RemoteOtpController? remoteOtp;
  RemoteOtpController? get remoteOtpController => remoteOtp;
  final Duration _otpWatchInterval;
  final RequestSlot _contactsRead;
  final RequestSlot _threadRead;
  final RequestSlot _otpWatch;
  final RequestSlot _send;
  final RequestSlot _delete;
  final Map<String, _OtpCursor> _otpSeen = <String, _OtpCursor>{};
  QueryState<List<SmsContact>> _contacts = const QueryState.initial(
    key: _contactsKey,
  );
  QueryState<List<SmsContact>> _otpInbox = const QueryState.initial(
    key: 'sms.otp.watch',
  );
  QueryState<SmsThread> _thread = const QueryState.initial(key: _threadKey);
  ActionState _sendAction = const ActionState.idle();
  ActionState _deleteAction = const ActionState.idle();
  SmsContact? _selectedContact;
  SmsSendResult? _lastSendResult;
  SmsOtpHit? _lastOtpHit;
  Timer? _otpTimer;
  bool _otpWatchEnabled = true;
  bool _otpPrimed = false;
  bool? _remoteOwnsOtpAlerts;
  int _watchEpoch = 0;
  int _contactsRequest = 0;
  int _contactsApplied = 0;
  Future<void>? _otpPoll;
  Future<void> _otpIngestion = Future<void>.value();
  bool _sendInFlight = false;
  String? _sendContactKey;
  int _selectionVersion = 0;

  QueryState<List<SmsContact>> get contacts => _contacts;
  
  /// Current query state for the selected contact's message thread.
  QueryState<SmsThread> get thread => _thread;
  
  /// Action state for send operations (only valid for currently selected contact).
  ActionState get sendAction => _sendContactKey == _selectedContact?.watchKey
      ? _sendAction
      : const ActionState.idle();
      
  /// Action state for message deletion operations.
  ActionState get deleteAction => _deleteAction;
  
  /// Currently selected contact, if any.
  SmsContact? get selectedContact => _selectedContact;
  
  /// Result of the last send operation for the currently selected contact.
  SmsSendResult? get lastSendResult =>
      _sendContactKey == _selectedContact?.watchKey ? _lastSendResult : null;
      
  /// Whether a send operation is currently in flight.
  bool get isSending => _sendInFlight;
  
  /// Version number incremented on each contact selection change.
  int get selectionVersion => _selectionVersion;
  
  /// Most recent OTP code extracted from incoming messages.
  SmsOtpHit? get lastOtpHit => _lastOtpHit;
  
  /// Whether OTP watching is available (requires an [otpSink]).
  bool get otpWatchAvailable => otpSink != null;
  
  /// Whether OTP watching is currently enabled.
  bool get otpWatchEnabled => _otpWatchEnabled;

  @override
  List<RequestSlot> get slots => <RequestSlot>[
    _contactsRead,
    _threadRead,
    _otpWatch,
    _send,
    _delete,
  ];

  Future<void> loadContacts() {
    final request = ++_contactsRequest;
    final epoch = _watchEpoch;
    return runQuery<List<SmsContact>>(
      slot: _contactsRead,
      current: () => _contacts,
      set: (next) => _applyContacts(next, request),
      fetch: _fetchSortedContacts,
      isEmpty: (contacts) => contacts.isEmpty,
      onData: (contacts, _) =>
          request < _contactsApplied ? null : _queueOtp(contacts, epoch: epoch),
    );
  }

  /// 登录后开始盯收件箱。没有 [otpSink] 时是空操作，测试默认不盯。
  void startOtpWatch() {
    if (isDisposed || otpSink == null || !_otpWatchEnabled) return;
    remoteOtp?.setEnabled(true);
    unawaited(remoteOtp?.restore() ?? Future<void>.value());
    if (_otpTimer != null) return;
    // Priming is decided when the serialized snapshot is ingested: another
    // contacts read may establish the baseline while this request is pending.
    unawaited(pollOtpInbox());
    _otpTimer = Timer.periodic(
      _otpWatchInterval,
      (_) => unawaited(pollOtpInbox()),
    );
  }

  void stopOtpWatch() {
    remoteOtp?.setEnabled(false);
    _otpTimer?.cancel();
    _otpTimer = null;
    _watchEpoch += 1;
    _otpWatch.cancel();
    _otpPoll = null;
    _otpIngestion = Future<void>.value();
    final sink = otpSink;
    if (sink is SmsOtpDeliverySink) {
      unawaited(sink.cancelPending().catchError((Object _) {}));
    }
  }

  void setOtpWatchEnabled(bool enabled) {
    if (isDisposed || _otpWatchEnabled == enabled) return;
    _otpWatchEnabled = enabled;
    if (!enabled) {
      stopOtpWatch();
      _otpPrimed = false;
      _otpSeen.clear();
      publish(() {});
      return;
    }
    publish(() {});
    startOtpWatch();
  }

  Future<void> pollOtpInbox({bool seed = false}) {
    if (isDisposed || otpSink == null || !_otpWatchEnabled) {
      return Future<void>.value();
    }
    // A timer tick joins the in-flight operation rather than cancelling a slow
    // but valid request every eight seconds.
    final active = _otpPoll;
    if (active != null) return active;
    final epoch = _watchEpoch;
    final request = ++_contactsRequest;
    late final Future<void> polling;
    polling =
        runQuery<List<SmsContact>>(
          slot: _otpWatch,
          current: () => _otpInbox,
          set: (next) {
            _otpInbox = next;
            if (next.status == QueryStatus.data && next.lastGoodData != null) {
              _applyContacts(
                QueryState<List<SmsContact>>.data(
                  data: next.lastGoodData!,
                  key: _contactsKey,
                ),
                request,
              );
            } else if (next.status == QueryStatus.empty &&
                request >= _contactsApplied) {
              // Empty is a successful snapshot too: older reads must not
              // revive contacts/OTPs absent from this newer result. Preserve
              // the silent-watch last-good display contract, but settle a
              // pending view because its obsolete read can no longer do so.
              _contactsApplied = request;
              if (_contacts.status == QueryStatus.loading ||
                  _contacts.status == QueryStatus.refreshing) {
                final kept = _contacts.lastGoodData;
                _setContacts(
                  kept == null
                      ? const QueryState<List<SmsContact>>.empty(
                          key: _contactsKey,
                        )
                      : QueryState<List<SmsContact>>.data(
                          data: kept,
                          key: _contactsKey,
                        ),
                );
              }
            }
          },
          silent: true,
          fetch: _fetchSortedContacts,
          isEmpty: (contacts) => contacts.isEmpty,
          onData: (contacts, _) => request < _contactsApplied
              ? null
              : _queueOtp(contacts, epoch: epoch, seed: seed),
        ).whenComplete(() {
          if (identical(_otpPoll, polling)) _otpPoll = null;
        });
    _otpPoll = polling;
    return polling;
  }

  Future<void> selectContact(SmsContact contact) async {
    if (isDisposed) return;
    _selectedContact = contact;
    _selectionVersion += 1;
    if (!_sendInFlight) {
      _lastSendResult = null;
      _sendAction = const ActionState.idle();
    }
    notifyListeners();
    await _readThread(contact, cursor: null, prepend: false);
  }

  Future<void> loadEarlier() async {
    final contact = _selectedContact;
    final current = _thread.lastGoodData;
    if (isDisposed ||
        contact == null ||
        current == null ||
        !current.hasMore ||
        _thread.status == QueryStatus.refreshing) {
      return;
    }
    await _readThread(contact, cursor: current.nextCursor, prepend: true);
  }

  Future<SmsSendResult?> sendMessage(
    String message, {
    SmsContact? expectedContact,
  }) async {
    final contact = _selectedContact;
    final text = message.trim();
    if (isDisposed ||
        contact == null ||
        text.isEmpty ||
        _sendInFlight ||
        (expectedContact != null &&
            expectedContact.watchKey != contact.watchKey)) {
      return null;
    }
    _sendInFlight = true;
    _sendContactKey = contact.watchKey;
    _lastSendResult = null;
    SmsSendResult? completed;
    try {
      await runAction<SmsSendResult>(
        slot: _send,
        current: () => _sendAction,
        set: _setSendAction,
        request: (ticket) => _repository.sendMessage(
          contact.target,
          text,
          cancellation: ticket.cancellation,
        ),
        onSuccess: (result, _) async {
          completed = result;
          _lastSendResult = result;
          if (result.outcome == SmsSendOutcome.failed) {
            return ActionState.failed(
              unknownOutcome: const StateFailure(
                StateFailureKind.unknownOutcome,
              ),
            );
          }
          _setSendAction(const ActionState.succeeded());
          await _readThread(contact, cursor: null, prepend: false);
          return null;
        },
      );
      return completed;
    } finally {
      _sendInFlight = false;
      publish(() {});
    }
  }

  Future<void> deleteSelectedThread({SmsContact? expectedContact}) async {
    final contact = _selectedContact;
    if (isDisposed ||
        contact == null ||
        _deleteAction.status == ActionStatus.submitting ||
        (expectedContact != null &&
            expectedContact.watchKey != contact.watchKey)) {
      return;
    }
    await runAction<void>(
      slot: _delete,
      current: () => _deleteAction,
      set: _setDeleteAction,
      request: (ticket) => _repository.deleteThread(
        contact.target,
        cancellation: ticket.cancellation,
      ),
      onSuccess: (_, _) async {
        if (_selectedContact?.watchKey == contact.watchKey) {
          _threadRead.cancel();
          _selectedContact = null;
          _selectionVersion += 1;
          _thread = const QueryState<SmsThread>.initial(key: _threadKey);
        }
        _setDeleteAction(const ActionState.succeeded());
        await loadContacts();
        return null;
      },
    );
  }

  Future<List<SmsContact>> _fetchSortedContacts(RequestTicket ticket) async {
    final result = await _repository.fetchContacts(
      cancellation: ticket.cancellation,
    );
    final contacts = List<SmsContact>.of(result)
      ..sort((left, right) {
        final leftTime = left.lastTimestamp?.millisecondsSinceEpoch ?? 0;
        final rightTime = right.lastTimestamp?.millisecondsSinceEpoch ?? 0;
        return rightTime.compareTo(leftTime);
      });
    return List<SmsContact>.unmodifiable(contacts);
  }

  Future<void> _queueOtp(
    List<SmsContact> contacts, {
    required int epoch,
    bool seed = false,
  }) {
    final queued = _otpIngestion.then(
      (_) => _ingestOtp(contacts, epoch: epoch, seed: seed || !_otpPrimed),
    );
    _otpIngestion = queued;
    return queued;
  }

  bool _isWatching(int epoch) =>
      !isDisposed && _otpWatchEnabled && _watchEpoch == epoch;

  Future<void> _ingestOtp(
    List<SmsContact> contacts, {
    required int epoch,
    required bool seed,
  }) async {
    final sink = otpSink;
    if (sink == null || !_isWatching(epoch)) return;
    Future<bool> observeOwnership() async {
      final bool remoteOwns;
      try {
        remoteOwns = await remoteOtp?.ownsPollingAlerts() ?? false;
      } catch (_) {
        // Unknown ownership must not create a duplicate or consume the batch.
        // Return normally so the serialized queue can retry the next snapshot.
        return false;
      }
      if (!_isWatching(epoch)) return false;
      // Keep this observation across stop/start: disconnecting while paused
      // must seed history that arrived while remote alerts owned this inbox.
      seed = seed || (_remoteOwnsOtpAlerts == true && !remoteOwns);
      _remoteOwnsOtpAlerts = remoteOwns;
      return true;
    }

    if (!await observeOwnership() || !_isWatching(epoch)) return;
    var ownershipNeedsRefresh = false;
    final oldestFirst = List<SmsContact>.of(contacts)
      ..sort((left, right) {
        final byTime = (left.lastTimestamp?.millisecondsSinceEpoch ?? 0)
            .compareTo(right.lastTimestamp?.millisecondsSinceEpoch ?? 0);
        return byTime != 0
            ? byTime
            : (left.lastSmsId ?? 0).compareTo(right.lastSmsId ?? 0);
      });
    for (final contact in oldestFirst) {
      if (!_isWatching(epoch)) return;
      final key = contact.watchKey;
      if (_otpSeen[key]?.accepts(contact) == false) continue;
      final code = SmsCodeExtractor.extract(contact.preview);
      if (ownershipNeedsRefresh &&
          contact.direction == SmsDirection.inbound &&
          code != null) {
        if (!await observeOwnership() || !_isWatching(epoch)) return;
        ownershipNeedsRefresh = false;
      }
      if (seed ||
          _remoteOwnsOtpAlerts == true ||
          contact.direction != SmsDirection.inbound ||
          code == null) {
        _rememberOtp(contact);
        continue;
      }
      final hit = SmsOtpHit(
        code: code,
        senderDisplay: contact.peerDisplay,
        deviceName: contact.deviceName,
      );
      bool delivered;
      try {
        if (sink is SmsOtpDeliverySink) {
          delivered = await sink.deliver(hit);
        } else {
          await sink.present(hit);
          delivered = true;
        }
      } catch (_) {
        // Keep this and all newer messages unconsumed. Retrying the snapshot
        // preserves oldest-first order and cannot permanently lose the batch.
        return;
      }
      if (!_isWatching(epoch)) return;
      ownershipNeedsRefresh = true;
      _rememberOtp(contact);
      if (delivered) {
        _lastOtpHit = hit;
        notifyListeners();
      }
    }
    if (_isWatching(epoch)) _otpPrimed = true;
  }

  void _rememberOtp(SmsContact contact) {
    final cursor = _otpSeen[contact.watchKey];
    if (cursor == null) {
      _otpSeen[contact.watchKey] = _OtpCursor(contact);
    } else {
      cursor.remember(contact);
    }
  }

  void _applyContacts(QueryState<List<SmsContact>> next, int request) {
    if (request < _contactsApplied) return;
    if (next.status != QueryStatus.loading &&
        next.status != QueryStatus.refreshing) {
      _contactsApplied = request;
    }
    _setContacts(next);
  }

  Future<void> _readThread(
    SmsContact contact, {
    required SmsThreadCursor? cursor,
    required bool prepend,
  }) async {
    if (isDisposed || !identical(_selectedContact, contact)) return;
    final ticket = _threadRead.begin();
    final previous = prepend ? _thread.lastGoodData : null;
    _setThread(QueryState.pending(previous: previous, key: _threadKey));
    // 线程结果还要求用户没有切走会话：代际一致但联系人换了同样作废。
    bool stillWanted() =>
        ticket.isCurrent && identical(_selectedContact, contact);
    try {
      final page = await _repository.fetchThread(
        contact.target,
        cursor: cursor,
        cancellation: ticket.cancellation,
      );
      if (!stillWanted()) return;
      final messages = prepend
          ? _mergeMessages(
              page.messages,
              previous?.messages ?? const <SmsMessage>[],
            )
          : page.messages;
      final value = SmsThread(
        messages: messages,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
      _setThread(
        value.messages.isEmpty
            ? const QueryState<SmsThread>.empty(key: _threadKey)
            : QueryState<SmsThread>.data(data: value, key: _threadKey),
      );
    } catch (error) {
      if (!stillWanted()) return;
      _setThread(
        QueryState.failedAfter(error, previous: previous, key: _threadKey),
      );
    } finally {
      ticket.end();
    }
  }

  static List<SmsMessage> _mergeMessages(
    List<SmsMessage> older,
    List<SmsMessage> newer,
  ) {
    final byId = <String, SmsMessage>{};
    for (final message in <SmsMessage>[...older, ...newer]) {
      byId[message.stableId] = message;
    }
    final result = byId.values.toList()
      ..sort((left, right) {
        final leftTime = left.timestamp?.millisecondsSinceEpoch ?? 0;
        final rightTime = right.timestamp?.millisecondsSinceEpoch ?? 0;
        final byTime = leftTime.compareTo(rightTime);
        return byTime != 0 ? byTime : left.numericId.compareTo(right.numericId);
      });
    return List<SmsMessage>.unmodifiable(result);
  }

  void _setContacts(QueryState<List<SmsContact>> next) =>
      publish(() => _contacts = next);

  void _setThread(QueryState<SmsThread> next) => publish(() => _thread = next);

  void _setSendAction(ActionState next) => publish(() => _sendAction = next);

  void _setDeleteAction(ActionState next) =>
      publish(() => _deleteAction = next);

  @override
  void dispose() {
    stopOtpWatch();
    remoteOtp?.dispose();
    super.dispose();
  }
}

/// A per-conversation high-water mark. Legacy peers have no durable id, so all
/// bodies at the current timestamp are retained to reject same-time rollbacks.
final class _OtpCursor {
  _OtpCursor(this.latest) {
    _legacyBodies.add((latest.preview, latest.direction));
  }

  SmsContact latest;
  final Set<(String, SmsDirection)> _legacyBodies = {};

  bool accepts(SmsContact next) {
    final nextId = next.lastSmsId;
    final seenId = latest.lastSmsId;
    if (nextId != null && seenId != null) return nextId > seenId;
    if (seenId != null) return false; // Never downgrade a server identity.
    final nextTime = next.lastTimestamp?.millisecondsSinceEpoch ?? 0;
    final seenTime = latest.lastTimestamp?.millisecondsSinceEpoch ?? 0;
    if (nextTime != seenTime) return nextTime > seenTime;
    return !_legacyBodies.contains((next.preview, next.direction));
  }

  void remember(SmsContact next) {
    if (next.lastTimestamp != latest.lastTimestamp) _legacyBodies.clear();
    _legacyBodies.add((next.preview, next.direction));
    latest = next;
  }
}
