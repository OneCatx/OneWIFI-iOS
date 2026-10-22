import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/design/widgets/nameplate.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/presentation/fleet_device_card.dart';
import 'package:onewifi_android/features/esim/domain/euicc_hardware.dart';

void main() {
  testWidgets('slot and capacity share one nameplate under the brand', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.dark(),
        home: Scaffold(
          body: FleetDeviceCard(
            device: _device(),
            selectedCardName: 'One NZ',
            hardware: const <EuiccHardware>[
              EuiccHardware(
                index: 0,
                eidDisplay: '•••• 8901',
                chipMaker: 'G+D',
                freeNvram: '634.55 KB',
                freeNvramBytes: 649779,
                nameplate: 'eSIM 实体卡',
              ),
            ],
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('One NZ'), findsOneWidget);
    expect(find.text('eSIM 实体卡'), findsOneWidget);
    expect(find.text('eSIM 1'), findsOneWidget);
    expect(find.text('可用 634.55 KB'), findsOneWidget);
    final slot = tester.widget<Nameplate>(
      find.widgetWithText(Nameplate, 'eSIM 1'),
    );
    expect(slot.detail, '可用 634.55 KB');
    expect(
      (tester.getTopLeft(find.text('eSIM 1')).dy -
              tester.getTopLeft(find.text('可用 634.55 KB')).dy)
          .abs(),
      lessThan(1),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Nameplate && widget.label.startsWith('可用'),
      ),
      findsNothing,
    );
  });

  testWidgets('domestic card shows 国内卡 and hides eSIM slots', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.dark(),
        home: Scaffold(
          body: FleetDeviceCard(
            device: _device(),
            selectedCardName: '长江移动',
            brandNameplate: '国内卡',
            hardware: const <EuiccHardware>[
              EuiccHardware(
                index: 0,
                eidDisplay: '',
                chipMaker: '',
                freeNvram: '',
                freeNvramBytes: null,
                nameplate: 'Nekoko联名',
              ),
            ],
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('国内卡'), findsOneWidget);
    expect(find.text('长江移动'), findsOneWidget);
    expect(find.text('Nekoko联名'), findsNothing);
    expect(find.text('eSIM 1'), findsNothing);
  });

  testWidgets('two slots are two nameplate rows', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.dark(),
        home: Scaffold(
          body: FleetDeviceCard(
            device: _device(),
            hardware: const <EuiccHardware>[
              EuiccHardware(
                index: 0,
                eidDisplay: '•••• 8901',
                chipMaker: 'G+D',
                freeNvram: '100 KB',
                freeNvramBytes: 102400,
                nameplate: 'Nekoko联名',
              ),
              EuiccHardware(
                index: 1,
                eidDisplay: '•••• 8902',
                chipMaker: 'G+D',
                freeNvram: '200 KB',
                freeNvramBytes: 204800,
                nameplate: 'Nekoko联名',
              ),
            ],
            onTap: () {},
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('eSIM 2')).dy,
      greaterThan(tester.getTopLeft(find.text('eSIM 1')).dy),
    );
    expect(
      (tester.getTopLeft(find.text('eSIM 2')).dy -
              tester.getTopLeft(find.text('可用 200 KB')).dy)
          .abs(),
      lessThan(1),
    );
  });
}

DeviceSnapshot _device() => DeviceSnapshot(
  id: 'm1',
  name: '模组',
  type: DeviceType.pcieEc20Ec25,
  healthy: true,
  physicalPresent: true,
  controlOnline: true,
  radioLive: true,
  radioRegistered: false,
  lifecyclePhase: DeviceLifecyclePhase.ready,
  lifecycleReasonCategory: DeviceReasonCategory.none,
  networkEnabled: true,
  networkConnected: false,
  vowifiEnabled: true,
  vowifiActive: false,
  smsEnabled: true,
  flightMode: false,
  developerEnabled: false,
  modem: const DeviceModem(
    operatorName: 'Carrier',
    model: 'EC25',
    firmware: 'fw',
    networkMode: 'LTE',
    radioBand: 'B3',
    signalDbm: -70,
    signalRsrp: null,
    signalRsrq: null,
    signalSinr: 0,
    simPresent: true,
    serviceBlocked: false,
    blockedCategory: DeviceBlockedCategory.none,
  ),
  identities: const DeviceIdentityDisplays(
    imeiDisplay: '•••• 1234',
    iccidDisplay: null,
    imsiDisplay: null,
    phoneDisplay: null,
  ),
  runtime: const DeviceRuntime(
    phase: DeviceRuntimePhase.idle,
    simReady: false,
    accessReady: false,
    tunnelReady: false,
    imsReady: false,
    smsReady: false,
  ),
);
