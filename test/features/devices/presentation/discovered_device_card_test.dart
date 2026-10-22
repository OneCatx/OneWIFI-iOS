import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:onewifi_android/features/devices/domain/device.dart';
import 'package:onewifi_android/features/devices/presentation/discovered_device_card.dart';

void main() {
  testWidgets('DiscoveredDeviceCard displays unregistered device correctly',
      (tester) async {
    var registerTapped = false;
    final device = DiscoveredDevice(
      hardwareKind: 'modem',
      readerName: 'Test Modem',
      deviceType: 'wifi_410',
      discoveryKey: 'key-123',
      controlPath: '/dev/ttyUSB0',
      netInterface: 'eth0',
      usbPath: '1-1.1',
      vendorId: 0x1234,
      productId: 0x5678,
      driverName: 'qmi_wwan',
      atPorts: const <String>['ttyUSB1'],
      atPort: 'ttyUSB1',
      imei: '123456789012345',
      mode: 'LTE',
      networkCapable: true,
      configured: false,
      configuredId: '',
      degraded: false,
      discoveryIssue: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscoveredDeviceCard(
            device: device,
            onRegister: () => registerTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Test Modem'), findsOneWidget);
    expect(find.text('未注册'), findsOneWidget);
    expect(find.text('注册设备'), findsOneWidget);

    await tester.tap(find.text('注册设备'));
    expect(registerTapped, true);
  });

  testWidgets('DiscoveredDeviceCard shows configured badge for registered device',
      (tester) async {
    final device = DiscoveredDevice(
      hardwareKind: 'modem',
      readerName: 'Registered Modem',
      deviceType: 'wifi_410',
      discoveryKey: 'key-456',
      controlPath: '/dev/ttyUSB2',
      netInterface: 'eth0',
      usbPath: '1-1.2',
      vendorId: 0x1234,
      productId: 0x5678,
      driverName: 'qmi_wwan',
      atPorts: const <String>['ttyUSB3'],
      atPort: 'ttyUSB3',
      imei: '987654321098765',
      mode: 'LTE',
      networkCapable: true,
      configured: true,
      configuredId: 'dev-existing',
      degraded: false,
      discoveryIssue: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscoveredDeviceCard(
            device: device,
            onRegister: () {},
          ),
        ),
      ),
    );

    expect(find.text('Registered Modem'), findsOneWidget);
    expect(find.text('已配置'), findsOneWidget);
    expect(find.text('注册设备'), findsNothing);
  });
}
