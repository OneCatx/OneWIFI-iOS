import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';

void main() {
  test('DJ-3 camped cell keeps home SPN off the serving plate', () {
    final device = _radio(
      radioRegistered: true,
      flightMode: false,
      operatorName: 'ASDA Mobile',
      servingOperator: 'China Mobile',
      networkMode: 'LTE',
      radioBand: 'B40',
      regStatus: 5,
      regStatusText: 'registered (roaming)',
      signalRsrp: -81,
      signalDbm: -54,
      accessReady: false,
    );

    expect(device.cellularCamped, isTrue);
    expect(device.modem.operatorName, 'ASDA Mobile');
    expect(device.modem.servingOperator, 'China Mobile');
    expect(device.radioStatus, '漫游驻留');
    expect(device.radioModeLabel, 'LTE B40');
    expect(device.radioSignalLabel, '-81 dBm');
    expect(device.radioLabel, 'China Mobile · LTE B40 · 漫游驻留');
    expect(device.radioSummary, 'China Mobile · LTE B40 · -81 dBm');
    expect(device.runtime.accessReady, isFalse);
  });

  test('home registration is 已驻留 and prefers RSRP over RSSI', () {
    final device = _radio(
      radioRegistered: true,
      flightMode: false,
      servingOperator: 'China Mobile',
      networkMode: 'LTE',
      radioBand: 'B3',
      regStatus: 1,
      regStatusText: 'registered',
      signalRsrp: -96,
      signalDbm: -73,
    );

    expect(device.radioStatus, '已驻留');
    expect(device.radioSignalLabel, '-96 dBm');
    expect(device.radioLabel, 'China Mobile · LTE B3 · 已驻留');
  });

  test('DJ-1 flight-mode VoWiFi is not a camped cellular cell', () {
    final device = _radio(
      radioRegistered: true,
      flightMode: true,
      vowifiActive: true,
      operatorName: 'ASDA Mobile',
      servingOperator: 'China Mobile',
      accessReady: true,
    );

    expect(device.cellularCamped, isFalse);
    expect(device.radioLabel, 'China Mobile · LTE B3 · 已驻留');
  });

  test('no radio plate when the modem has not registered', () {
    final device = _radio(
      radioRegistered: false,
      flightMode: false,
      servingOperator: 'China Mobile',
      signalRsrp: -81,
    );

    expect(device.cellularCamped, isFalse);
    expect(device.radioStatus, '');
    expect(device.radioLabel, '');
  });
}

DeviceSnapshot _radio({
  required bool radioRegistered,
  required bool flightMode,
  String operatorName = 'ASDA Mobile',
  String servingOperator = '',
  String networkMode = 'LTE',
  String radioBand = 'B3',
  int regStatus = 1,
  String regStatusText = 'registered',
  int? signalRsrp,
  int signalDbm = 0,
  bool vowifiActive = false,
  bool accessReady = false,
}) => DeviceSnapshot(
  id: 'quectel-0125-2-1-2',
  name: 'DJ-3',
  type: DeviceType.dji4g,
  healthy: true,
  physicalPresent: true,
  controlOnline: true,
  radioLive: true,
  radioRegistered: radioRegistered,
  lifecyclePhase: DeviceLifecyclePhase.ready,
  lifecycleReasonCategory: DeviceReasonCategory.none,
  networkEnabled: true,
  networkConnected: false,
  vowifiEnabled: vowifiActive,
  vowifiActive: vowifiActive,
  smsEnabled: true,
  flightMode: flightMode,
  developerEnabled: false,
  modem: DeviceModem(
    operatorName: operatorName,
    servingOperator: servingOperator,
    model: 'RG255C',
    firmware: null,
    networkMode: networkMode,
    radioBand: radioBand,
    signalDbm: signalDbm,
    signalRsrp: signalRsrp,
    signalRsrq: null,
    signalSinr: 0,
    simPresent: true,
    serviceBlocked: false,
    blockedCategory: DeviceBlockedCategory.none,
    regStatus: regStatus,
    regStatusText: regStatusText,
  ),
  identities: const DeviceIdentityDisplays(
    imeiDisplay: null,
    iccidDisplay: null,
    imsiDisplay: null,
    phoneDisplay: null,
  ),
  runtime: DeviceRuntime(
    phase: DeviceRuntimePhase.idle,
    simReady: false,
    accessReady: accessReady,
    tunnelReady: false,
    imsReady: false,
    smsReady: false,
  ),
);
