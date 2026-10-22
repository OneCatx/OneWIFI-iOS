import '../../../../design/widgets/console_layout.dart';
import '../../domain/automation.dart';

String automationTaskTypeLabel(AutomationTaskType value) => switch (value) {
  AutomationTaskType.sms => '短信',
  AutomationTaskType.call => '拨打电话（已下线）',
  AutomationTaskType.publicIp => '公网 IP',
};

String automationEnvironmentLabel(AutomationEnvironment value) =>
    switch (value) {
      AutomationEnvironment.vowifi => 'VoWiFi',
      AutomationEnvironment.cellular => '蜂窝直连',
    };

({String label, PlateTone tone}) automationRunStatus(
  AutomationRunStatus value,
) => switch (value) {
  AutomationRunStatus.queued => (label: '排队中', tone: PlateTone.blue),
  AutomationRunStatus.running => (label: '执行中', tone: PlateTone.teal),
  AutomationRunStatus.success => (label: '成功', tone: PlateTone.green),
  AutomationRunStatus.failed => (label: '失败', tone: PlateTone.red),
};
