import 'package:flutter/material.dart';

import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../devices/domain/device.dart';
import '../../devices/presentation/fleet_device_card.dart';
import '../../devices/state/device_list_controller.dart';
import '../domain/sms.dart';
import '../state/sms_controller.dart';
import 'widgets/sms_composer.dart';
import 'widgets/sms_contact_button.dart';
import 'widgets/sms_contacts_section.dart';
import 'widgets/sms_otp_watch_tile.dart';
import 'widgets/sms_thread_section.dart';

final class SmsScreen extends StatefulWidget {
  const SmsScreen({required this.controller, this.devices, super.key});

  static const Key messageFieldKey = Key('sms-message-field');
  static const Key deleteThreadKey = Key('sms-delete-thread');
  final SmsController controller;

  /// 设备列表（与设备页同源），用来画同一张设备卡；不传时只按联系人里的
  /// 模组名画简卡。
  final DeviceListController? devices;

  @override
  State<SmsScreen> createState() => _SmsScreenState();
}

final class _SmsScreenState extends State<SmsScreen> {
  final TextEditingController _messageController = TextEditingController();
  String? _deviceFilter;
  int _draftVersion = 0;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_draftChanged);
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(SmsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        !identical(oldWidget.devices, widget.devices)) {
      _scheduleLoad();
    }
  }

  @override
  void dispose() {
    _messageController.removeListener(_draftChanged);
    _messageController.dispose();
    super.dispose();
  }

  void _draftChanged() => _draftVersion += 1;

  void _scheduleLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.loadContacts();
      widget.devices?.load();
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge(<Listenable>[
      widget.controller,
      ?widget.devices,
    ]),
    builder: (context, _) {
      final contacts =
          widget.controller.contacts.lastGoodData ?? const <SmsContact>[];
      final devices = _deviceNames(contacts);
      final visible = _visibleContacts(contacts);
      return RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: OneInsets.scroll(context),
              sliver: SliverMainAxisGroup(
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const OwPageHead(
                          title: '短信检测',
                          desc: '号码和 SIM 只显示尾 4，正文仍可读。',
                        ),
                        const SizedBox(height: OneSpacing.item),
                        SmsOtpWatchTile(controller: widget.controller),
                        const SizedBox(height: OneSpacing.item),
                        MetricRow(
                          children: <Widget>[
                            MetricCard(
                              label: '可选模组',
                              value: '${devices.length}',
                              sub: '在位模组，号码只显示尾 4',
                              icon: Icons.devices_other_outlined,
                              tone: MetricTone.blue,
                            ),
                            MetricCard(
                              label: '联系人',
                              value: '${visible.length}',
                              sub: _deviceFilter == null
                                  ? '全部设备'
                                  : _deviceFilter!,
                              icon: Icons.sms_outlined,
                              tone: MetricTone.green,
                            ),
                            MetricCard(
                              label: '当前会话',
                              value:
                                  widget
                                      .controller
                                      .selectedContact
                                      ?.peerDisplay ??
                                  '—',
                              sub:
                                  widget
                                          .controller
                                          .selectedContact
                                          ?.deviceName
                                          .isNotEmpty ==
                                      true
                                  ? widget
                                        .controller
                                        .selectedContact!
                                        .deviceName
                                  : '选一个联系人',
                              icon: Icons.smartphone_outlined,
                              tone: MetricTone.purple,
                            ),
                            MetricCard(
                              label: '线路',
                              value: contacts.isEmpty ? '等待' : '可发',
                              sub: contacts.isEmpty ? '先到设备页接入模组' : '模组在位就能测短信',
                              icon: Icons.cell_tower_outlined,
                              tone: MetricTone.blue,
                            ),
                          ],
                        ),
                        if (devices.isNotEmpty) ...<Widget>[
                          const SizedBox(height: OneSpacing.medium),
                          ..._deviceCards(devices, contacts.length),
                        ],
                        const SizedBox(height: OneSpacing.medium),
                        if (visible.isEmpty)
                          SmsContactsSection(
                            visible: visible,
                            controller: widget.controller,
                            devices: widget.devices,
                          )
                        else
                          SmsContactsSection.sectionHeader(
                            refreshing:
                                widget.controller.contacts.status ==
                                QueryStatus.refreshing,
                          ),
                      ],
                    ),
                  ),
                  if (visible.isNotEmpty)
                    SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final contact = visible[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: OneSpacing.item),
                          child: SmsContactButton(
                            contact: contact,
                            sourcePlate: SmsContactsSection.sourcePlate(
                              contact,
                              widget.devices,
                            ),
                            selected:
                                widget.controller.selectedContact?.watchKey ==
                                contact.watchKey,
                            onPressed: () =>
                                widget.controller.selectContact(contact),
                          ),
                        );
                      },
                    ),
                  if (widget.controller.selectedContact != null)
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SizedBox(height: OneSpacing.medium),
                          SmsThreadSection(
                            controller: widget.controller,
                            deleteThreadKey: SmsScreen.deleteThreadKey,
                            onDeleteThread: _confirmDeleteThread,
                          ),
                          const SizedBox(height: OneSpacing.medium),
                          SmsComposer(
                            controller: _messageController,
                            action: widget.controller.sendAction,
                            lastSendResult: widget.controller.lastSendResult,
                            onChanged: () => setState(() {}),
                            onSend: widget.controller.isSending
                                ? null
                                : _confirmSend,
                            messageFieldKey: SmsScreen.messageFieldKey,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  /// 下拉刷新：联系人与设备清单一起拉，任何一路失败都由各自的状态区呈现。
  Future<void> _refresh() => Future.wait<void>(<Future<void>>[
    widget.controller.loadContacts(),
    ?widget.devices?.refresh(),
  ]);

  /// WEB 短信页那排 device-card：先「全部设备」，再每台模组，选中的走变色。
  /// 有设备列表就画设备页同一张卡（铭牌 / 线路 / 运营商都在），
  /// 没有就退成只有名字的简卡。
  List<Widget> _deviceCards(List<String> names, int contactCount) {
    final fleet = widget.devices?.state.lastGoodData?.devices;
    final byName = <String, DeviceSnapshot>{
      for (final device in fleet ?? const <DeviceSnapshot>[])
        device.name: device,
    };
    return <Widget>[
      FleetSummaryCard(
        name: '全部设备',
        icon: Icons.devices_other_outlined,
        selected: _deviceFilter == null,
        plates: <String>['全部会话', '$contactCount 个联系人'],
        onTap: () => setState(() => _deviceFilter = null),
      ),
      for (final name in names) ...<Widget>[
        const SizedBox(height: OneSpacing.item),
        if (byName[name] case final device?)
          FleetDeviceCard(
            device: device,
            hardware: widget.devices?.hardwareFor(device.id),
            selectedCardName:
                widget.devices?.enabledCardNameFor(device.id) ?? '',
            brandNameplate: widget.devices?.brandNameplateFor(device.id) ?? '',
            selected: _deviceFilter == name,
            onTap: () => setState(() => _deviceFilter = name),
          )
        else
          FleetSummaryCard(
            name: name,
            selected: _deviceFilter == name,
            plates: const <String>['本机'],
            onTap: () => setState(() => _deviceFilter = name),
          ),
      ],
    ];
  }

  List<String> _deviceNames(List<SmsContact> contacts) {
    final names = <String>{};
    for (final contact in contacts) {
      if (contact.deviceName.isNotEmpty) names.add(contact.deviceName);
    }
    return names.toList(growable: false);
  }

  List<SmsContact> _visibleContacts(List<SmsContact> contacts) {
    final filter = _deviceFilter;
    if (filter == null) return contacts;
    return contacts
        .where((contact) => contact.deviceName == filter)
        .toList(growable: false);
  }

  Future<void> _confirmSend() async {
    final controller = widget.controller;
    final contact = controller.selectedContact;
    final message = _messageController.text.trim();
    final draftVersion = _draftVersion;
    final selectionVersion = controller.selectionVersion;
    if (contact == null || message.isEmpty) return;
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '发送短信?',
      message: '把这条消息发给 ${contact.peerDisplay}？结果不明确时绝不自动重试。',
      confirmLabel: '发送',
    );
    if (confirmed != true ||
        !mounted ||
        !identical(controller, widget.controller) ||
        controller.selectionVersion != selectionVersion) {
      return;
    }
    final result = await controller.sendMessage(
      message,
      expectedContact: contact,
    );
    if (!mounted || !identical(controller, widget.controller)) return;
    if (result != null &&
        result.outcome != SmsSendOutcome.failed &&
        controller.selectionVersion == selectionVersion &&
        _draftVersion == draftVersion) {
      _messageController.clear();
      setState(() {});
    }
  }

  Future<void> _confirmDeleteThread() async {
    final controller = widget.controller;
    final contact = controller.selectedContact;
    final selectionVersion = controller.selectionVersion;
    if (contact == null) return;
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '删除会话?',
      message: '删除与 ${contact.peerDisplay} 的全部短信？此操作不会自动重试。',
      confirmLabel: '删除',
    );
    if (confirmed != true ||
        !mounted ||
        !identical(controller, widget.controller) ||
        controller.selectionVersion != selectionVersion) {
      return;
    }
    await controller.deleteSelectedThread(expectedContact: contact);
  }
}
