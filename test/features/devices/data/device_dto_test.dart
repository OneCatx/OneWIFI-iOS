import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/security/redaction.dart';
import 'package:onewifi_android/features/devices/data/device_dto.dart';
import 'package:onewifi_android/features/devices/domain/device.dart';

void main() {
  test('parses a complete fleet into approved safe fields only', () {
    final identities = _Identities.generate();
    final nestedSecret = _runtimeSecret(67, 13);
    final dto = DeviceFleetDto.fromData(<String, Object?>{
      'device_limit': 4,
      'devices': <Object?>[
        _deviceFixture(identities: identities, nestedSecret: nestedSecret),
      ],
    });

    expect(dto.deviceLimit, 4);
    final device = dto.devices.single;
    expect(device.id, 'configured-device');
    expect(device.name, 'Workshop modem');
    expect(device.type, DeviceType.pcieEc20Ec25);
    expect(device.lifecyclePhase, DeviceLifecyclePhase.ready);
    expect(device.lifecycleReasonCategory, DeviceReasonCategory.none);
    expect(device.runtime.phase, DeviceRuntimePhase.imsReady);
    // WEB 同款：SPN 优先于 operator。
    expect(device.modem.operatorName, 'One');
    expect(device.modem.servingOperator, 'One Carrier');
    expect(device.modem.model, 'EC25');
    expect(device.modem.signalDbm, -73);
    expect(device.identities.imeiDisplay, Redaction.maskTail4(identities.imei));
    expect(
      device.identities.iccidDisplay,
      Redaction.maskTail4(identities.iccid),
    );
    expect(device.identities.imsiDisplay, Redaction.maskTail4(identities.imsi));
    expect(
      device.identities.phoneDisplay,
      Redaction.maskTail4(identities.phone),
    );
    expect(device.identities.imeiReveal, identities.imei);
    expect(device.identities.iccidReveal, identities.iccid);
    expect(device.identities.imsiReveal, identities.imsi);
    expect(device.identities.phoneReveal, identities.phone);

    final approvedValues = <Object?>[
      device.id,
      device.name,
      device.type,
      device.healthy,
      device.physicalPresent,
      device.controlOnline,
      device.radioLive,
      device.radioRegistered,
      device.lifecyclePhase,
      device.lifecycleReasonCategory,
      device.networkEnabled,
      device.networkConnected,
      device.vowifiEnabled,
      device.vowifiActive,
      device.smsEnabled,
      device.flightMode,
      device.developerEnabled,
      device.modem.operatorName,
      device.modem.servingOperator,
      device.modem.model,
      device.modem.firmware,
      device.modem.networkMode,
      device.modem.radioBand,
      device.modem.signalDbm,
      device.modem.signalRsrp,
      device.modem.signalRsrq,
      device.modem.signalSinr,
      device.modem.simPresent,
      device.modem.serviceBlocked,
      device.modem.blockedCategory,
      device.modem.regStatus,
      device.modem.regStatusText,
      device.identities.imeiDisplay,
      device.identities.iccidDisplay,
      device.identities.imsiDisplay,
      device.identities.phoneDisplay,
      device.runtime.phase,
      device.runtime.simReady,
      device.runtime.accessReady,
      device.runtime.tunnelReady,
      device.runtime.imsReady,
      device.runtime.smsReady,
    ];
    for (final secret in <String>[
      identities.imei,
      identities.iccid,
      identities.imsi,
      identities.phone,
      nestedSecret,
    ]) {
      expect(approvedValues.contains(secret), isFalse);
    }
  });

  test('accepts an empty fleet and absent no-snapshot modem fields', () {
    expect(
      DeviceFleetDto.fromData(const <String, Object?>{
        'device_limit': 0,
        'devices': <Object?>[],
      }).devices,
      isEmpty,
    );

    final identities = _Identities.generate();
    final fixture = _deviceFixture(
      identities: identities,
      nestedSecret: _runtimeSecret(59, 17),
      physicalPresent: false,
    );
    final modem = fixture['modem']! as Map<String, Object?>;
    modem
      ..remove('imsi')
      ..remove('firmware')
      ..remove('network_duplex')
      ..remove('signal_rsrp')
      ..remove('signal_rsrq')
      ..remove('ps_attached')
      ..remove('operating_mode');
    final runtime = fixture['vowifi_runtime']! as Map<String, Object?>;
    runtime.remove('carrier_profile_from');

    final device = DeviceFleetDto.fromData(<String, Object?>{
      'device_limit': 1,
      'devices': <Object?>[fixture],
    }).devices.single;

    expect(device.physicalPresent, isFalse);
    expect(device.lifecyclePhase, DeviceLifecyclePhase.missing);
    expect(device.modem.firmware, isNull);
    expect(device.modem.signalRsrp, isNull);
    expect(device.modem.signalRsrq, isNull);
    expect(device.identities.imsiDisplay, isNotNull);
  });

  test('resolves the operator name with the WEB fallback chain', () {
    String resolve(void Function(Map<String, Object?> modem) mutate) {
      final fixture = _deviceFixture(
        identities: _Identities.generate(),
        nestedSecret: _runtimeSecret(61, 19),
      );
      mutate(fixture['modem']! as Map<String, Object?>);
      return DeviceFleetDto.fromData(<String, Object?>{
        'device_limit': 1,
        'devices': <Object?>[fixture],
      }).devices.single.modem.operatorName;
    }

    expect(resolve((_) {}), 'One');
    expect(resolve((m) => m['native_spn'] = '  '), 'One Carrier');
    expect(
      resolve((m) {
        m['native_spn'] = '';
        m['operator'] = '';
        m['home_carrier_name'] = 'Home Carrier';
      }),
      'Home Carrier',
    );
    expect(
      resolve((m) {
        m['native_spn'] = '';
        m['operator'] = '';
        m['home_carrier_name'] = '';
      }),
      '00101',
    );
    expect(
      resolve((m) {
        m['native_spn'] = '';
        m['operator'] = '';
        m['home_carrier_name'] = '';
        m['native_mcc'] = '';
        m['sim_inserted'] = false;
      }),
      '未插 SIM',
    );
    expect(
      resolve((m) {
        m['native_spn'] = '';
        m['operator'] = '';
        m['home_carrier_name'] = '';
        m['native_mnc'] = '';
      }),
      '',
    );
  });

  test('keeps serving operator off the home SPN for a camped cell', () {
    final fixture = _deviceFixture(
      identities: _Identities.generate(),
      nestedSecret: _runtimeSecret(62, 20),
    );
    fixture['radio_registered'] = true;
    fixture['flight_mode'] = false;
    fixture['vowifi_active'] = false;
    fixture['network_connected'] = false;
    final modem = fixture['modem']! as Map<String, Object?>;
    modem['operator'] = 'China Mobile';
    modem['native_spn'] = 'ASDA Mobile';
    modem['network_mode'] = 'LTE';
    modem['radio_band'] = 'B40';
    modem['reg_status'] = 5;
    modem['reg_status_text'] = 'registered (roaming)';
    modem['signal_rsrp'] = -81;
    modem['signal_dbm'] = -54;
    final runtime = fixture['vowifi_runtime']! as Map<String, Object?>;
    runtime['access_ready'] = false;
    runtime['sim_ready'] = false;
    runtime['tunnel_ready'] = false;
    runtime['ims_ready'] = false;
    runtime['sms_ready'] = false;
    runtime['phase'] = 'idle';

    final device = DeviceFleetDto.fromData(<String, Object?>{
      'device_limit': 1,
      'devices': <Object?>[fixture],
    }).devices.single;

    expect(device.modem.operatorName, 'ASDA Mobile');
    expect(device.modem.servingOperator, 'China Mobile');
    expect(device.modem.regStatus, 5);
    expect(device.modem.regStatusText, 'registered (roaming)');
    expect(device.modem.signalRsrp, -81);
    expect(device.modem.networkMode, 'LTE');
    expect(device.modem.radioBand, 'B40');
    expect(device.runtime.accessReady, isFalse);
    expect(device.radioRegistered, isTrue);
    expect(device.flightMode, isFalse);
  });

  test('accepts a stored runtime null carrier profile source', () {
    final fixture = _deviceFixture(
      identities: _Identities.generate(),
      nestedSecret: _runtimeSecret(60, 18),
    );
    final runtime = fixture['vowifi_runtime']! as Map<String, Object?>;
    runtime['carrier_profile_from'] = null;

    final device = DeviceFleetDto.fromData(<String, Object?>{
      'device_limit': 1,
      'devices': <Object?>[fixture],
    }).devices.single;

    expect(device.runtime.phase, DeviceRuntimePhase.imsReady);
  });

  test('requires exactly one matching device in a detail envelope', () {
    final identities = _Identities.generate();
    final valid = _deviceFixture(
      identities: identities,
      nestedSecret: _runtimeSecret(61, 19),
      detail: true,
    );

    final detail = DeviceDetailDto.fromData(<String, Object?>{
      'devices': <Object?>[valid],
    }, expectedDeviceId: 'configured-device');
    expect(detail.device.id, 'configured-device');
    expect(detail.traffic.available, isTrue);
    expect(detail.traffic.rxBytes, 1024);
    expect(detail.traffic.txRateBytesPerSecond, 4096);
    expect(detail.traffic.status, DeviceTrafficStatus.ready);

    for (final devices in <List<Object?>>[
      <Object?>[],
      <Object?>[valid, valid],
      <Object?>[
        <String, Object?>{...valid, 'id': 'another-device'},
      ],
    ]) {
      expect(
        () => DeviceDetailDto.fromData(<String, Object?>{
          'devices': devices,
        }, expectedDeviceId: 'configured-device'),
        throwsA(isA<DeviceDtoException>()),
      );
    }
  });

  test('treats a physically missing detail and empty traffic as success', () {
    final fixture =
        _deviceFixture(
            identities: _Identities.generate(),
            nestedSecret: _runtimeSecret(71, 23),
            physicalPresent: false,
            detail: true,
          )
          ..['traffic'] = <String, Object?>{}
          ..['traffic_raw'] = <String, Object?>{}
          ..['traffic_meta'] = <String, Object?>{};

    final detail = DeviceDetailDto.fromData(<String, Object?>{
      'devices': <Object?>[fixture],
    }, expectedDeviceId: 'configured-device');

    expect(detail.device.physicalPresent, isFalse);
    expect(detail.device.radioLive, isFalse);
    expect(detail.traffic.available, isFalse);
    expect(detail.traffic.status, DeviceTrafficStatus.unavailable);
    expect(detail.traffic.rxBytes, isNull);
    expect(detail.traffic.txBytes, isNull);
    expect(detail.traffic.rxRateBytesPerSecond, isNull);
    expect(detail.traffic.txRateBytesPerSecond, isNull);
  });

  test('preserves integers above 2^53 through the int64 boundary', () {
    const aboveDoublePrecision = 9007199254740993;
    const maxInt64 = 9223372036854775807;
    final fixture = _deviceFixture(
      identities: _Identities.generate(),
      nestedSecret: _runtimeSecret(71, 25),
      detail: true,
    );
    fixture['traffic_raw'] = <String, Object?>{
      'rx': aboveDoublePrecision,
      'tx': maxInt64,
      'rate': 0,
      'rate_tx': 0.0,
    };

    final detail = DeviceDetailDto.fromData(<String, Object?>{
      'devices': <Object?>[fixture],
    }, expectedDeviceId: 'configured-device');

    expect(detail.traffic.rxBytes, aboveDoublePrecision);
    expect(detail.traffic.txBytes, maxInt64);
    expect(detail.traffic.rxRateBytesPerSecond, 0);
    expect(detail.traffic.txRateBytesPerSecond, 0);
  });

  test('rejects unknown lifecycle and runtime phases', () {
    final base = _deviceFixture(
      identities: _Identities.generate(),
      nestedSecret: _runtimeSecret(73, 29),
    );
    final runtime = base['vowifi_runtime']! as Map<String, Object?>;
    final invalid = <Map<String, Object?>>[
      <String, Object?>{...base, 'lifecycle_phase': 'invented'},
      <String, Object?>{
        ...base,
        'vowifi_runtime': <String, Object?>{...runtime, 'phase': 'invented'},
      },
    ];

    for (final device in invalid) {
      expect(
        () => DeviceFleetDto.fromData(<String, Object?>{
          'device_limit': 1,
          'devices': <Object?>[device],
        }),
        throwsA(isA<DeviceDtoException>()),
      );
    }
  });

  test('rejects wrong required and optional-present field types', () {
    final base = _deviceFixture(
      identities: _Identities.generate(),
      nestedSecret: _runtimeSecret(79, 31),
    );
    final modem = base['modem']! as Map<String, Object?>;
    final runtime = base['vowifi_runtime']! as Map<String, Object?>;
    final invalid = <Object?>[
      <String, Object?>{'device_limit': '1', 'devices': <Object?>[]},
      <String, Object?>{
        'device_limit': 1,
        'devices': <Object?>[
          <String, Object?>{...base, 'physical_present': 'true'},
        ],
      },
      <String, Object?>{
        'device_limit': 1,
        'devices': <Object?>[
          <String, Object?>{
            ...base,
            'modem': <String, Object?>{...modem, 'firmware': 7},
          },
        ],
      },
      <String, Object?>{
        'device_limit': 1,
        'devices': <Object?>[
          <String, Object?>{
            ...base,
            'modem': <String, Object?>{...modem, 'signal_rsrp': '-96'},
          },
        ],
      },
      <String, Object?>{
        'device_limit': 1,
        'devices': <Object?>[
          <String, Object?>{
            ...base,
            'vowifi_runtime': <String, Object?>{
              ...runtime,
              'sim_ready': 'true',
            },
          },
        ],
      },
    ];

    for (final value in invalid) {
      expect(
        () => DeviceFleetDto.fromData(value),
        throwsA(isA<DeviceDtoException>()),
      );
    }
  });

  test('validates every required broad-wire field before discarding it', () {
    const requiredStrings = <String, List<String>>{
      'top': <String>[
        'id',
        'name',
        'device_type',
        'public_ip',
        'private_ip',
        'interface',
        'esim_transport',
        'local_phone',
        'phone_number_source',
        'registration_state_label',
        'lifecycle_reason',
      ],
      'modem': <String>[
        'operator',
        'native_mcc',
        'native_mnc',
        'native_spn',
        'operator_country_code',
        'card_mcc',
        'card_mnc',
        'card_country',
        'home_carrier_name',
        'home_carrier_plmn',
        'home_carrier_country_code',
        'blocked_reason',
        'network_mode',
        'radio_band',
        'reg_status_text',
        'phone_number_source',
        'model',
        'imei',
        'iccid',
        'phone_number',
      ],
      'runtime': <String>[
        'device_id',
        'phase',
        'dataplane_mode',
        'iccid',
        'imsi',
        'reg_status_text',
        'network_mode',
        'local_phone',
        'phone_number_source',
        'last_error_class',
        'last_error',
        'last_reason',
        'updated_at',
      ],
      'detail': <String>[
        'at_port',
        'audio_device',
        'backend_mode',
        'control_device',
      ],
    };
    const requiredBools = <String, List<String>>{
      'top': <String>[
        'running',
        'healthy',
        'control_online',
        'physical_present',
        'worker_running',
        'data_connected',
        'radio_registered',
        'sms_enabled',
        'network_enabled',
        'developer_enabled',
        'network_connected',
        'vowifi_enabled',
        'vowifi_active',
        'flight_mode',
      ],
      'modem': <String>['service_blocked', 'sim_inserted'],
      'runtime': <String>[
        'enabled',
        'active',
        'sim_ready',
        'access_ready',
        'tunnel_ready',
        'ims_ready',
        'sms_ready',
      ],
      'detail': <String>['radio_live_ok'],
    };
    const requiredInts = <String, List<String>>{
      'top': <String>['proxy_port'],
      'modem': <String>[
        'radio_channel',
        'signal_dbm',
        'signal_sinr',
        'reg_status',
      ],
      'runtime': <String>['reg_status'],
    };
    const requiredMaps = <String, List<String>>{
      'top': <String>['modem', 'vowifi_runtime', 'esim_switch'],
    };

    for (final entry in requiredStrings.entries) {
      for (final key in entry.value) {
        _expectRequiredWireFieldRejected(entry.key, key, wrongValue: 7);
      }
    }
    for (final entry in requiredBools.entries) {
      for (final key in entry.value) {
        _expectRequiredWireFieldRejected(entry.key, key, wrongValue: 'true');
      }
    }
    for (final entry in requiredInts.entries) {
      for (final key in entry.value) {
        _expectRequiredWireFieldRejected(entry.key, key, wrongValue: '1');
      }
    }
    for (final entry in requiredMaps.entries) {
      for (final key in entry.value) {
        _expectRequiredWireFieldRejected(entry.key, key, wrongValue: 'map');
      }
    }
  });

  test('optional snapshot fields reject a present wrong type', () {
    const cases = <(String, String, Object?)>[
      ('modem', 'network_duplex', 7),
      ('modem', 'firmware', 7),
      ('modem', 'imsi', 7),
      ('modem', 'signal_rsrp', '-96'),
      ('modem', 'signal_rsrq', '-11'),
      ('modem', 'ps_attached', 'true'),
      ('modem', 'operating_mode', '1'),
      ('runtime', 'carrier_profile_from', 7),
    ];

    for (final entry in cases) {
      final fixture = _deviceFixture(
        identities: _Identities.generate(),
        nestedSecret: _runtimeSecret(83, entry.$2.length),
      );
      _wireScope(fixture, entry.$1)[entry.$2] = entry.$3;
      expect(
        () => _parseFleetDevice(fixture),
        throwsA(isA<DeviceDtoException>()),
        reason: '${entry.$1}.${entry.$2}',
      );
    }
  });

  test(
    'normalizes finite integral JSON numbers and rejects unsafe traffic',
    () {
      final valid = _deviceFixture(
        identities: _Identities.generate(),
        nestedSecret: _runtimeSecret(83, 37),
        detail: true,
      );
      valid['traffic_raw'] = <String, Object?>{
        'rx': 1024.0,
        'tx': 2048.0,
        'rate': 3072.0,
        'rate_tx': 4096.0,
      };
      final parsed = DeviceDetailDto.fromData(<String, Object?>{
        'devices': <Object?>[valid],
      }, expectedDeviceId: 'configured-device');
      expect(parsed.traffic.rxBytes, 1024);
      expect(parsed.traffic.rxRateBytesPerSecond, 3072);

      for (final bad in <Object?>[
        -1,
        1.5,
        double.nan,
        double.infinity,
        '1024',
      ]) {
        final fixture = _deviceFixture(
          identities: _Identities.generate(),
          nestedSecret: _runtimeSecret(89, 41),
          detail: true,
        );
        final traffic = fixture['traffic_raw']! as Map<String, Object?>;
        traffic['rx'] = bad;
        expect(
          () => DeviceDetailDto.fromData(<String, Object?>{
            'devices': <Object?>[fixture],
          }, expectedDeviceId: 'configured-device'),
          throwsA(isA<DeviceDtoException>()),
        );
      }
    },
  );

  test('rejects unknown sampler status and sanitizes reported reasons', () {
    final secret = _runtimeSecret(97, 43);
    final blocked = _deviceFixture(
      identities: _Identities.generate(),
      nestedSecret: secret,
      detail: true,
    )..['lifecycle_reason'] = secret;
    final modem = blocked['modem']! as Map<String, Object?>;
    modem
      ..['service_blocked'] = true
      ..['blocked_reason'] = secret;

    final parsed = DeviceDetailDto.fromData(<String, Object?>{
      'devices': <Object?>[blocked],
    }, expectedDeviceId: 'configured-device');
    expect(
      parsed.device.lifecycleReasonCategory,
      DeviceReasonCategory.reported,
    );
    expect(parsed.device.modem.blockedCategory, DeviceBlockedCategory.reported);

    blocked['traffic_meta'] = <String, Object?>{'status': 'invented'};
    expect(
      () => DeviceDetailDto.fromData(<String, Object?>{
        'devices': <Object?>[blocked],
      }, expectedDeviceId: 'configured-device'),
      throwsA(isA<DeviceDtoException>()),
    );
  });

  test('maps esim_switch onto the five fixed switch stages by key', () {
    final fixture = _deviceFixture(
      identities: _Identities.generate(),
      nestedSecret: _runtimeSecret(17, 5),
    );
    // 空闲快照：后端不上报 steps 时全部 pending。
    expect(_parseFleetDevice(fixture).esimSwitch.active, isFalse);
    expect(
      _parseFleetDevice(fixture).esimSwitch.stages,
      everyElement(DeviceSwitchStageState.pending),
    );

    fixture['esim_switch'] = <String, Object?>{
      'active': true,
      'step': 3,
      'status': 'running',
      'steps': <Object?>[
        // 乱序 + 多余步骤，必须按 key 对位而不是按下标。
        <String, Object?>{'key': 'write', 'ready': false, 'pending': true},
        <String, Object?>{'key': 'stop', 'ready': true, 'pending': false},
        <String, Object?>{'key': 'flight', 'ready': true},
        <String, Object?>{'key': 'extra', 'ready': true},
      ],
    };
    final running = _parseFleetDevice(fixture).esimSwitch;
    expect(running.active, isTrue);
    expect(running.stages, <DeviceSwitchStageState>[
      DeviceSwitchStageState.ready,
      DeviceSwitchStageState.ready,
      DeviceSwitchStageState.running,
      DeviceSwitchStageState.pending,
      DeviceSwitchStageState.pending,
    ]);

    fixture['esim_switch'] = <String, Object?>{
      'active': false,
      'steps': <Object?>[
        <String, Object?>{'key': 'stop', 'ready': true},
        <String, Object?>{'key': 'flight', 'failed': true, 'ready': true},
      ],
    };
    final failed = _parseFleetDevice(fixture).esimSwitch;
    expect(failed.active, isFalse);
    expect(failed.stages[1], DeviceSwitchStageState.failed);
  });

  test(
    'distinguishes unavailable traffic from real available zero traffic',
    () {
      final missing =
          _deviceFixture(
              identities: _Identities.generate(),
              nestedSecret: _runtimeSecret(91, 47),
              detail: true,
            )
            ..remove('traffic')
            ..remove('traffic_raw')
            ..remove('traffic_meta');
      final unavailable = _parseDetailDevice(missing).traffic;
      expect(unavailable.available, isFalse);
      expect(unavailable.status, DeviceTrafficStatus.unavailable);
      expect(unavailable.rxBytes, isNull);
      expect(unavailable.txBytes, isNull);
      expect(unavailable.rxRateBytesPerSecond, isNull);
      expect(unavailable.txRateBytesPerSecond, isNull);

      final zero =
          _deviceFixture(
              identities: _Identities.generate(),
              nestedSecret: _runtimeSecret(93, 49),
              detail: true,
            )
            ..['traffic'] = <String, Object?>{
              'rx': '0 B',
              'tx': '0 B',
              'rate': '0 B/s',
              'rate_tx': '0 B/s',
            }
            ..['traffic_raw'] = <String, Object?>{
              'rx': 0,
              'tx': 0,
              'rate': 0,
              'rate_tx': 0,
            }
            ..['traffic_meta'] = <String, Object?>{'status': ''};
      final available = _parseDetailDevice(zero).traffic;
      expect(available.available, isTrue);
      expect(available.status, DeviceTrafficStatus.ready);
      expect(available.rxBytes, 0);
      expect(available.txBytes, 0);
      expect(available.rxRateBytesPerSecond, 0);
      expect(available.txRateBytesPerSecond, 0);

      final domainSource = File(
        'lib/features/devices/domain/device.dart',
      ).readAsStringSync();
      expect(domainSource.contains('const DeviceTraffic({'), isFalse);
      expect(domainSource.contains('const DeviceTraffic._'), isTrue);
    },
  );

  test('rejects contradictory public traffic construction in release', () {
    expect(
      () => DeviceTraffic.available(
        rxBytes: -1,
        txBytes: 0,
        rxRateBytesPerSecond: 0,
        txRateBytesPerSecond: 0,
        status: DeviceTrafficStatus.ready,
      ),
      throwsArgumentError,
    );
    expect(
      () => DeviceTraffic.available(
        rxBytes: 0,
        txBytes: 0,
        rxRateBytesPerSecond: 0,
        txRateBytesPerSecond: 0,
        status: DeviceTrafficStatus.unavailable,
      ),
      throwsArgumentError,
    );
  });

  test('treats any missing or empty traffic object as unavailable', () {
    final mutations = <void Function(Map<String, Object?>)>[
      (device) => device.remove('traffic'),
      (device) => device.remove('traffic_raw'),
      (device) => device.remove('traffic_meta'),
      (device) => device['traffic'] = <String, Object?>{},
      (device) => device['traffic_raw'] = <String, Object?>{},
      (device) => device['traffic_meta'] = <String, Object?>{},
    ];

    for (var index = 0; index < mutations.length; index += 1) {
      final fixture = _deviceFixture(
        identities: _Identities.generate(),
        nestedSecret: _runtimeSecret(97, index + 51),
        detail: true,
      );
      mutations[index](fixture);
      final traffic = _parseDetailDevice(fixture).traffic;
      expect(traffic.available, isFalse, reason: 'traffic mutation $index');
      expect(traffic.status, DeviceTrafficStatus.unavailable);
      expect(traffic.rxBytes, isNull);
      expect(traffic.txBytes, isNull);
      expect(traffic.rxRateBytesPerSecond, isNull);
      expect(traffic.txRateBytesPerSecond, isNull);
    }
  });

  test('rejects malformed populated traffic objects', () {
    final mutations = <void Function(Map<String, Object?>)>[
      (device) => device['traffic'] = 'formatted traffic',
      (device) => device['traffic_raw'] = 'raw traffic',
      (device) => device['traffic_meta'] = 'traffic metadata',
      (device) {
        final raw = device['traffic_raw']! as Map<String, Object?>;
        raw.remove('rate_tx');
      },
      (device) {
        final formatted = device['traffic']! as Map<String, Object?>;
        formatted['rate_tx'] = 0;
      },
    ];

    for (var index = 0; index < mutations.length; index += 1) {
      final fixture = _deviceFixture(
        identities: _Identities.generate(),
        nestedSecret: _runtimeSecret(97, index + 51),
        detail: true,
      );
      mutations[index](fixture);
      expect(
        () => _parseDetailDevice(fixture),
        throwsA(isA<DeviceDtoException>()),
        reason: 'malformed traffic mutation $index',
      );
    }
  });

  test(
    'production fields and constructor formals stay on the safe whitelist',
    () {
      for (final path in _devicePublicShapePaths) {
        final source = File(path).readAsStringSync();
        expect(_hasOnlyApprovedProductionShape(source), isTrue, reason: path);
      }
    },
  );

  test('privacy shape guard ignores nested initializer commas', () {
    final source = File(
      'lib/features/devices/data/device_api.dart',
    ).readAsStringSync();
    const anchor = "  static const String _devicesRoute = '/api/devices';";
    const replacements = <String>[
      "  static final String _devicesRoute = <String>['/api', 'devices'].join('/');",
      "  static final String _devicesRoute = <String, String>{'path': '/api', 'part': 'devices'}['path']!;",
      "  static final String _devicesRoute = ('/api', part: 'devices').\$1;",
      "  static final String _devicesRoute = String.fromCharCodes(<int>[47, 97]);",
      "  static final String _devicesRoute = <void Function(int, int), String>{}.isEmpty ? '/api/devices' : '/api/devices';",
      "  static final String _devicesRoute = <void Function(void Function(int, int)?), String>{}.isEmpty ? '/api/devices' : '/api/devices';",
      "  static final String _devicesRoute = <void Function(int /* left */, int), String>{}.isEmpty ? '/api/devices' : '/api/devices';",
      "  static final String _devicesRoute = <void Function(\n      int, // left, <ignored>\n      int\n    ), String>{}.isEmpty ? '/api/devices' : '/api/devices';",
      "  static final String _devicesRoute = <void Function([int left, int? right]), String>{}.isEmpty ? '/api/devices' : '/api/devices';",
      "  static final String _devicesRoute = <void Function({required int left, int? right}), String>{}.isEmpty ? '/api/devices' : '/api/devices';",
      "  static final String _devicesRoute = <void Function(({int left, int right}) value), String>{}.isEmpty ? '/api/devices' : '/api/devices';",
      "  static final String _devicesRoute = <void Function(List<Map<String /* key, <ignored> */, int>> values), String>{}.isEmpty ? '/api/devices' : '/api/devices';",
      "  static final String _devicesRoute = <void Function(int /* outer /* inner */ still outer */, int), String>{}.isEmpty ? '/api/devices' : '/api/devices';",
      "  static final String _devicesRoute = <void Function(int /* outer, <ignored> 'quote' /* inner, > \" */ still outer */, int), String>{}.isEmpty ? '/api/devices' : '/api/devices';",
      "  static final String _devicesRoute = r'\\,still-safe';",
      "  static final String _devicesRoute = R\"\\,still-safe\";",
      "  static final String _devicesRoute = r'''\\,still-safe''';",
      "  static final String _devicesRoute = 'escaped\\',still-safe';",
    ];

    for (final replacement in replacements) {
      final mutatedSource = _replaceSourceAnchor(source, anchor, replacement);
      expect(
        _hasOnlyApprovedProductionShape(mutatedSource),
        isTrue,
        reason: replacement,
      );
    }
  });

  test('privacy shape guard catches source mutations on the actual files', () {
    final source = File(
      'lib/features/devices/data/device_dto.dart',
    ).readAsStringSync();
    final mutations = <(String, String Function(String))>[
      (
        'final raw runtime member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  final Map<String, Object?> rawRuntime;\n',
        ),
      ),
      (
        'final carrier profile member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  final Object? carrierProfile;\n',
        ),
      ),
      (
        'final raw payload member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  final Object? rawPayload;\n',
        ),
      ),
      (
        'record raw payload member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  final ({Map<String, Object?> rawPayload}) runtimeRecord;\n',
        ),
      ),
      (
        'this-formal raw payload',
        (value) => _replaceSourceAnchor(
          value,
          'required this.traffic',
          'required this.traffic, required this.rawPayload',
        ),
      ),
      (
        'ordinary raw payload constructor formal',
        (value) => _replaceSourceAnchor(
          value,
          'required this.traffic',
          'required this.traffic, required Object? rawPayload',
        ),
      ),
      (
        'ordinary IMEI constructor formal',
        (value) => _replaceSourceAnchor(
          value,
          'required this.traffic',
          'required this.traffic, required String imei',
        ),
      ),
      (
        'mutable raw payload member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  Object? rawPayload;\n',
        ),
      ),
      (
        'mutable ICCID member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  String iccid;\n',
        ),
      ),
      (
        'late raw runtime member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  late Object? rawRuntime;\n',
        ),
      ),
      (
        'late final raw runtime member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  late final Object? rawRuntime;\n',
        ),
      ),
      (
        'late tunnel member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  late Object? tunnel;\n',
        ),
      ),
      (
        'static carrier profile member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  static Object? carrierProfile;\n',
        ),
      ),
      (
        'static imscore member',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  static Object? imscore;\n',
        ),
      ),
      (
        'static final IMSI member with initializer',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          "  static final String imsi = '';\n",
        ),
      ),
      (
        'ordinary IMSI constructor formal with default',
        (value) => _replaceSourceAnchor(
          value,
          'required this.traffic',
          "required this.traffic, String imsi = ''",
        ),
      ),
      (
        'multi-declarator IMSI member',
        (value) => _replaceSourceAnchor(
          value,
          '  final String id;\n',
          "  final String id, imsi = '';\n",
        ),
      ),
      (
        'multiline multi-declarator IMSI member',
        (value) => _replaceSourceAnchor(
          value,
          '  final String id;\n',
          "  final String id,\n      imsi = '';\n",
        ),
      ),
      (
        'initialized multi-declarator IMSI member',
        (value) => _replaceSourceAnchor(
          value,
          '  final String id;\n',
          "  final String id = '', imsi = '';\n",
        ),
      ),
      (
        'multiline initialized multi-declarator IMSI member',
        (value) => _replaceSourceAnchor(
          value,
          '  final String id;\n',
          "  final String id = '',\n      imsi = '';\n",
        ),
      ),
      (
        'raw single-quoted initialized multi-declarator IMSI member',
        (value) => _replaceSourceAnchor(
          value,
          '  final String id;\n',
          "  final String id = r'\\', imsi = '';\n",
        ),
      ),
      (
        'raw double-quoted initialized multi-declarator IMSI member',
        (value) => _replaceSourceAnchor(
          value,
          '  final String id;\n',
          "  final String id = R\"\\\", imsi = '';\n",
        ),
      ),
      (
        'raw triple-quoted initialized multi-declarator IMSI member',
        (value) => _replaceSourceAnchor(
          value,
          '  final String id;\n',
          "  final String id = r'''\\''', imsi = '';\n",
        ),
      ),
      (
        'computed IMSI getter',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          "  String get imsi => '';\n",
        ),
      ),
      (
        'multiline computed IMSI getter',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          "  String get imsi =>\n      '';\n",
        ),
      ),
      (
        'computed IMSI setter',
        (value) => _insertAfterSourceAnchor(
          value,
          'final class DeviceFleetDto {\n',
          '  set imsi(String value) {}\n',
        ),
      ),
    ];

    expect(_hasOnlyApprovedProductionShape(source), isTrue);
    for (final mutation in mutations) {
      final mutatedSource = mutation.$2(source);
      expect(mutatedSource, isNot(source), reason: mutation.$1);
      expect(
        _hasOnlyApprovedProductionShape(mutatedSource),
        isFalse,
        reason: mutation.$1,
      );
    }
  });
}

const _devicePublicShapePaths = <String>[
  'lib/features/devices/domain/device.dart',
  'lib/features/devices/data/device_api.dart',
  'lib/features/devices/data/device_dto.dart',
  'lib/features/devices/data/device_repository.dart',
];

const _approvedProductionFields = <String, Set<String>>{
  '_transport': <String>{'HttpTransport'},
  '_api': <String>{'DeviceApi'},
  '_devicesRoute': <String>{'String'},
  '_deviceOverviewRoute': <String>{'String'},
  'deviceLimit': <String>{'int'},
  'devices': <String>{'List<DeviceSnapshot>', 'List<DeviceSnapshotDto>'},
  'device': <String>{'DeviceSnapshot', 'DeviceSnapshotDto'},
  'traffic': <String>{'DeviceTraffic', 'DeviceTrafficDto'},
  // Storage capacities contain counts only, not SMS content or identities.
  'smsStorage': <String>{'DeviceSmsStorage?'},
  'sm': <String>{'DeviceSmsMailbox'},
  'me': <String>{'DeviceSmsMailbox'},
  'used': <String>{'int'},
  'total': <String>{'int'},
  'id': <String>{'String'},
  'name': <String>{'String'},
  'type': <String>{'DeviceType'},
  'healthy': <String>{'bool'},
  'physicalPresent': <String>{'bool'},
  'controlOnline': <String>{'bool'},
  'radioLive': <String>{'bool?'},
  'radioRegistered': <String>{'bool'},
  'lifecyclePhase': <String>{'DeviceLifecyclePhase'},
  'lifecycleReasonCategory': <String>{'DeviceReasonCategory'},
  'networkEnabled': <String>{'bool'},
  'networkConnected': <String>{'bool'},
  'vowifiEnabled': <String>{'bool'},
  'vowifiActive': <String>{'bool'},
  'smsEnabled': <String>{'bool'},
  'flightMode': <String>{'bool'},
  'developerEnabled': <String>{'bool'},
  'modem': <String>{'DeviceModem', 'DeviceModemDto'},
  'identities': <String>{'DeviceIdentityDisplays', 'DeviceIdentityDisplaysDto'},
  'runtime': <String>{'DeviceRuntime', 'DeviceRuntimeDto'},
  // 网关 `esim_switch` 切卡进度：只有 active 标志与五段枚举状态，不含 ICCID。
  'esimSwitch': <String>{'DeviceEsimSwitch', 'DeviceEsimSwitchDto'},
  'active': <String>{'bool'},
  'stages': <String>{'List<DeviceSwitchStageState>'},
  'operatorName': <String>{'String'},
  'servingOperator': <String>{'String'},
  'regStatus': <String>{'int'},
  'regStatusText': <String>{'String'},
  'model': <String>{'String'},
  'firmware': <String>{'String?'},
  'networkMode': <String>{'String'},
  'radioBand': <String>{'String'},
  'signalDbm': <String>{'int'},
  'signalRsrp': <String>{'int?'},
  'signalRsrq': <String>{'int?'},
  'signalSinr': <String>{'int'},
  'simPresent': <String>{'bool'},
  'serviceBlocked': <String>{'bool'},
  'blockedCategory': <String>{'DeviceBlockedCategory'},
  'imeiDisplay': <String>{'String?'},
  'iccidDisplay': <String>{'String?'},
  'imsiDisplay': <String>{'String?'},
  'phoneDisplay': <String>{'String?'},
  // 眼睛揭开用的全文。不叫 imei/iccid/imsi，避免和生产禁名撞车；
  // 只活在身份类型上，默认 UI 仍走 Display。
  'imeiReveal': <String>{'String?'},
  'iccidReveal': <String>{'String?'},
  'imsiReveal': <String>{'String?'},
  'phoneReveal': <String>{'String?'},
  'phase': <String>{'DeviceRuntimePhase'},
  'simReady': <String>{'bool'},
  'accessReady': <String>{'bool'},
  'tunnelReady': <String>{'bool'},
  'imsReady': <String>{'bool'},
  'smsReady': <String>{'bool'},
  // WEB 运行状态「详情」三项：dataplane_mode / last_reason / last_error_class
  // 都是分类枚举文本；含明文栈的 last_error 仍不允许进入任何数据类。
  'dataPlane': <String>{'String'},
  'lastReason': <String>{'String'},
  'errorCategory': <String>{'String'},
  'available': <String>{'bool'},
  'rxBytes': <String>{'int?'},
  'txBytes': <String>{'int?'},
  'rxRateBytesPerSecond': <String>{'int?'},
  'txRateBytesPerSecond': <String>{'int?'},
  'status': <String>{'DeviceTrafficStatus'},
};

final _classMemberDeclarationPattern = RegExp(
  r'^ {2}(?!(?:return|throw|if|else|for|while|do|switch|case|default|break|'
  r'continue|try|catch|finally|assert|yield)\b)'
  r'(?:(?:external|static|late|final|const)\s+)*'
  r'(?!(?:external|static|late|final|const)\b)'
  r'([A-Za-z_(][A-Za-z0-9_<>,? {}:()\[\]]*?)\s+'
  r'([A-Za-z_][A-Za-z0-9_]*)\s*(?:=[^;]*)?;\s*$',
  multiLine: true,
);

final _formattedClassBodyPattern = RegExp(
  r'^(?:(?:abstract|base|final|interface|sealed)\s+)*class\s+'
  r'[A-Za-z_][A-Za-z0-9_]*[^\{]*\{\r?\n([\s\S]*?)^\}',
  multiLine: true,
);

final _classFieldStartPattern = RegExp(
  r'^ {2}(?:(?:external|static|late|final|const)[ \t]+)*'
  r'(?!(?:external|static|late|final|const)\b)'
  r'[A-Za-z_(][A-Za-z0-9_<>,? {}:()\[\]]*?[ \t]+'
  r'[A-Za-z_][A-Za-z0-9_]*[ \t]*(?=[=,;])',
  multiLine: true,
);

final _computedMemberDeclarationPattern = RegExp(
  r'^ {2}(?:(?:external|static)\s+)*(?:'
  r'[A-Za-z_(][A-Za-z0-9_<>,? {}:()\[\]]*?\s+get\s+'
  r'[A-Za-z_][A-Za-z0-9_]*\b|'
  r'set\s+[A-Za-z_][A-Za-z0-9_]*\s*\()',
  multiLine: true,
);

final _constructorFormalPattern = RegExp(
  r'\bthis\.([A-Za-z_][A-Za-z0-9_]*)\b(?!\s*\()',
);

final _ordinaryFormalPattern = RegExp(
  r'(?:[({,\[]\s*)(?:required\s+)?(?:covariant\s+)?'
  r'([A-Za-z_(][A-Za-z0-9_<>,? {}:()\[\]]*)\s+'
  r'([A-Za-z_][A-Za-z0-9_]*)\s*'
  r'(?:=\s*[^,)}]*)?\s*(?=[,)}])',
);

final _forbiddenProductionNamePattern = RegExp(
  r'^(?:raw.*|carrierProfile.*|imei|iccid|imsi|msisdn|localPhone|phoneNumber|'
  r'local_phone|tunnel|imscore|smsip|atPort|controlDevice|audioDevice|'
  r'backendMessage|simPin|apn)$',
  caseSensitive: false,
);

bool _isPrivacyExemptClass(String classSource) {
  // Discovery / rescan payloads intentionally carry hardware paths and IMEI for
  // registration; fleet/snapshot DTOs remain under the privacy shape guard.
  return RegExp(r'class\s+Discovered\w*').hasMatch(classSource) ||
      RegExp(r'class\s+DeviceRescan\w*').hasMatch(classSource);
}

bool _isConstructorParameterContext(String classSource, int offset) {
  var depth = 0;
  for (var index = offset; index >= 0; index -= 1) {
    final code = classSource.codeUnitAt(index);
    if (code == 0x29 /* ) */) {
      depth += 1;
      continue;
    }
    if (code != 0x28 /* ( */) continue;
    if (depth > 0) {
      depth -= 1;
      continue;
    }
    final lineStart = classSource.lastIndexOf('\n', index) + 1;
    final snippet = classSource.substring(lineStart, index).trim();
    return RegExp(
      r'^(?:const|factory)\s+[A-Za-z_][A-Za-z0-9_]*'
      r'(?:\.[A-Za-z_][A-Za-z0-9_]*)?$|'
      r'^[A-Z][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?$',
    ).hasMatch(snippet);
  }
  return false;
}

bool _hasOnlyApprovedProductionShape(String source) {
  for (final classMatch in _formattedClassBodyPattern.allMatches(source)) {
    final fullClass = classMatch.group(0)!;
    if (_isPrivacyExemptClass(fullClass)) continue;
    final classBody = classMatch.group(1)!;
    if (_hasMultiDeclaratorMember(classBody) ||
        _computedMemberDeclarationPattern.hasMatch(classBody)) {
      return false;
    }
    for (final match in _classMemberDeclarationPattern.allMatches(classBody)) {
      final type = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
      final name = match.group(2)!;
      if (!(_approvedProductionFields[name]?.contains(type) ?? false)) {
        return false;
      }
    }
    for (final match in _constructorFormalPattern.allMatches(fullClass)) {
      if (!_approvedProductionFields.containsKey(match.group(1))) return false;
    }
    for (final match in _ordinaryFormalPattern.allMatches(fullClass)) {
      final name = match.group(2)!;
      if (!_forbiddenProductionNamePattern.hasMatch(name)) continue;
      // Write-path method params (e.g. registerDevice.simPin) are not DTO shape.
      if (!_isConstructorParameterContext(fullClass, match.start)) continue;
      return false;
    }
  }
  return true;
}

bool _hasMultiDeclaratorMember(String classBodies) {
  for (final field in _classFieldStartPattern.allMatches(classBodies)) {
    var parentheses = 0;
    var brackets = 0;
    var braces = 0;
    for (var index = field.end; index < classBodies.length; index += 1) {
      final codeUnit = classBodies.codeUnitAt(index);
      if (codeUnit == 0x27 || codeUnit == 0x22) {
        index = _stringLiteralEnd(classBodies, index);
        continue;
      }
      if (codeUnit == 0x2f && index + 1 < classBodies.length) {
        final next = classBodies.codeUnitAt(index + 1);
        if (next == 0x2f) {
          final newline = classBodies.indexOf('\n', index + 2);
          index = newline < 0 ? classBodies.length : newline;
          continue;
        }
        if (next == 0x2a) {
          final close = _nestedBlockCommentEnd(classBodies, index);
          index = close ?? classBodies.length;
          continue;
        }
      }
      if (codeUnit == 0x3c) {
        final typeArgumentEnd = _typeArgumentEnd(classBodies, index);
        if (typeArgumentEnd != null) {
          index = typeArgumentEnd;
          continue;
        }
      }
      switch (codeUnit) {
        case 0x28:
          parentheses += 1;
        case 0x29:
          if (parentheses > 0) parentheses -= 1;
        case 0x5b:
          brackets += 1;
        case 0x5d:
          if (brackets > 0) brackets -= 1;
        case 0x7b:
          braces += 1;
        case 0x7d:
          if (braces > 0) braces -= 1;
        case 0x2c:
          if (parentheses == 0 && brackets == 0 && braces == 0) return true;
        case 0x3b:
          if (parentheses == 0 && brackets == 0 && braces == 0) break;
      }
      if (codeUnit == 0x3b &&
          parentheses == 0 &&
          brackets == 0 &&
          braces == 0) {
        break;
      }
    }
  }
  return false;
}

int _stringLiteralEnd(String source, int start) {
  final quote = source.codeUnitAt(start);
  final prefixStart = start - 1;
  final raw =
      prefixStart >= 0 &&
      (source.codeUnitAt(prefixStart) == 0x72 ||
          source.codeUnitAt(prefixStart) == 0x52) &&
      (prefixStart == 0 ||
          !_isDartIdentifierPart(source.codeUnitAt(prefixStart - 1)));
  final triple =
      start + 2 < source.length &&
      source.codeUnitAt(start + 1) == quote &&
      source.codeUnitAt(start + 2) == quote;
  for (
    var index = start + (triple ? 3 : 1);
    index < source.length;
    index += 1
  ) {
    if (!raw && source.codeUnitAt(index) == 0x5c) {
      index += 1;
      continue;
    }
    if (source.codeUnitAt(index) != quote) continue;
    if (!triple ||
        (index + 2 < source.length &&
            source.codeUnitAt(index + 1) == quote &&
            source.codeUnitAt(index + 2) == quote)) {
      return index + (triple ? 2 : 0);
    }
  }
  return source.length - 1;
}

bool _isDartIdentifierPart(int codeUnit) {
  return codeUnit == 0x24 ||
      codeUnit == 0x5f ||
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
      codeUnit >= 0x80;
}

int? _typeArgumentEnd(String source, int start) {
  var depth = 0;
  for (var index = start; index < source.length; index += 1) {
    final codeUnit = source.codeUnitAt(index);
    if (codeUnit == 0x2f && index + 1 < source.length) {
      final next = source.codeUnitAt(index + 1);
      if (next == 0x2f) {
        final newline = source.indexOf('\n', index + 2);
        if (newline < 0) return null;
        index = newline;
        continue;
      }
      if (next == 0x2a) {
        final close = _nestedBlockCommentEnd(source, index);
        if (close == null) return null;
        index = close;
        continue;
      }
    }
    final isTypeCharacter =
        (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        const <int>{
          0x20,
          0x09,
          0x0a,
          0x0d,
          0x2c,
          0x2e,
          0x28,
          0x29,
          0x3a,
          0x3c,
          0x3e,
          0x3f,
          0x5f,
          0x5b,
          0x5d,
          0x7b,
          0x7d,
        }.contains(codeUnit);
    if (!isTypeCharacter) return null;
    if (codeUnit == 0x3c) depth += 1;
    if (codeUnit != 0x3e) continue;
    depth -= 1;
    if (depth != 0) continue;

    var next = index + 1;
    while (next < source.length &&
        const <int>{0x20, 0x09, 0x0a, 0x0d}.contains(source.codeUnitAt(next))) {
      next += 1;
    }
    if (next < source.length &&
        const <int>{0x28, 0x2e, 0x5b, 0x7b}.contains(source.codeUnitAt(next))) {
      return index;
    }
    return null;
  }
  return null;
}

int? _nestedBlockCommentEnd(String source, int start) {
  var depth = 1;
  for (var index = start + 2; index + 1 < source.length; index += 1) {
    final first = source.codeUnitAt(index);
    final second = source.codeUnitAt(index + 1);
    if (first == 0x2f && second == 0x2a) {
      depth += 1;
      index += 1;
      continue;
    }
    if (first != 0x2a || second != 0x2f) continue;
    depth -= 1;
    index += 1;
    if (depth == 0) return index;
  }
  return null;
}

String _insertAfterSourceAnchor(
  String source,
  String anchor,
  String insertion,
) => _replaceSourceAnchor(source, anchor, '$anchor$insertion');

String _replaceSourceAnchor(String source, String anchor, String replacement) {
  final first = source.indexOf(anchor);
  if (first < 0 || source.indexOf(anchor, first + anchor.length) >= 0) {
    fail('expected exactly one actual-source anchor: $anchor');
  }
  return source.replaceFirst(anchor, replacement);
}

void _expectRequiredWireFieldRejected(
  String scope,
  String key, {
  required Object? wrongValue,
}) {
  for (final mutation in <String>['missing', 'wrong']) {
    final fixture = _deviceFixture(
      identities: _Identities.generate(),
      nestedSecret: _runtimeSecret(101, key.length + mutation.length),
      detail: scope == 'detail',
    );
    final target = _wireScope(fixture, scope);
    if (mutation == 'missing') {
      target.remove(key);
    } else {
      target[key] = wrongValue;
    }
    expect(
      () => scope == 'detail'
          ? _parseDetailDevice(fixture)
          : _parseFleetDevice(fixture),
      throwsA(isA<DeviceDtoException>()),
      reason: '$scope.$key $mutation',
    );
  }
}

Map<String, Object?> _wireScope(Map<String, Object?> device, String scope) {
  return switch (scope) {
    'top' || 'detail' => device,
    'modem' => device['modem']! as Map<String, Object?>,
    'runtime' => device['vowifi_runtime']! as Map<String, Object?>,
    _ => throw ArgumentError.value(scope),
  };
}

DeviceSnapshotDto _parseFleetDevice(Map<String, Object?> device) {
  return DeviceFleetDto.fromData(<String, Object?>{
    'device_limit': 1,
    'devices': <Object?>[device],
  }).devices.single;
}

DeviceDetailDto _parseDetailDevice(Map<String, Object?> device) {
  return DeviceDetailDto.fromData(<String, Object?>{
    'devices': <Object?>[device],
  }, expectedDeviceId: 'configured-device');
}

Map<String, Object?> _deviceFixture({
  required _Identities identities,
  required String nestedSecret,
  bool physicalPresent = true,
  bool detail = false,
}) => <String, Object?>{
  'id': 'configured-device',
  'name': physicalPresent ? 'Workshop modem' : 'Offline modem',
  'device_type': 'pcie_ec20_ec25',
  'running': physicalPresent,
  'healthy': physicalPresent,
  'control_online': physicalPresent,
  'physical_present': physicalPresent,
  'worker_running': physicalPresent,
  'data_connected': physicalPresent,
  'radio_registered': physicalPresent,
  'lifecycle_phase': physicalPresent ? 'ready' : 'missing',
  'lifecycle_reason': physicalPresent ? '' : nestedSecret,
  'public_ip': '',
  'private_ip': '',
  'interface': 'wwan0',
  'proxy_port': 1080,
  'esim_transport': 'qmi',
  'sms_enabled': true,
  'network_enabled': true,
  'developer_enabled': true,
  'network_connected': physicalPresent,
  'vowifi_enabled': true,
  'vowifi_active': physicalPresent,
  'flight_mode': false,
  'local_phone': identities.phone,
  'phone_number_source': 'network',
  'registration_state_label': 'registered',
  'modem': <String, Object?>{
    'operator': 'One Carrier',
    'native_mcc': '001',
    'native_mnc': '01',
    'native_spn': 'One',
    'operator_country_code': 'ZZ',
    'card_mcc': '001',
    'card_mnc': '01',
    'card_country': 'Test',
    'home_carrier_name': 'One Carrier',
    'home_carrier_plmn': '00101',
    'home_carrier_country_code': 'ZZ',
    'service_blocked': false,
    'blocked_reason': '',
    'network_mode': 'LTE',
    'network_duplex': 'FDD',
    'radio_band': 'B3',
    'radio_channel': 1300,
    'signal_dbm': -73,
    'signal_rsrp': -96,
    'signal_rsrq': -11,
    'signal_sinr': 18,
    'imei': identities.imei,
    'iccid': identities.iccid,
    'imsi': identities.imsi,
    'firmware': 'EC25EFAR06A11M4G',
    'model': 'EC25',
    'reg_status': 1,
    'reg_status_text': 'registered',
    'ps_attached': true,
    'sim_inserted': true,
    'operating_mode': 1,
    'phone_number': identities.phone,
    'phone_number_source': 'network',
  },
  'vowifi_runtime': <String, Object?>{
    'device_id': 'configured-device',
    'phase': physicalPresent ? 'ims_ready' : 'idle',
    'enabled': physicalPresent,
    'active': physicalPresent,
    'carrier_profile': <String, Object?>{'secret': nestedSecret},
    'carrier_profile_from': 'runtime',
    'dataplane_mode': 'cellular',
    'iccid': identities.iccid,
    'imsi': identities.imsi,
    'sim_ready': physicalPresent,
    'access_ready': physicalPresent,
    'tunnel_ready': physicalPresent,
    'ims_ready': physicalPresent,
    'sms_ready': false,
    'reg_status': 1,
    'reg_status_text': 'registered',
    'network_mode': 'LTE',
    'local_phone': identities.phone,
    'phone_number_source': 'network',
    'last_error_class': '',
    'last_error': nestedSecret,
    'last_reason': 'ready',
    'updated_at': '2026-09-01T00:00:00Z',
    'tunnel': <String, Object?>{'path': nestedSecret},
    'imscore': <String, Object?>{'opaque': nestedSecret},
    'smsip': <String, Object?>{'opaque': nestedSecret},
  },
  'esim_switch': <String, Object?>{'opaque': nestedSecret},
  if (detail) ...<String, Object?>{
    'at_port': nestedSecret,
    'audio_device': nestedSecret,
    'backend_mode': 'qmi',
    'control_device': nestedSecret,
    'radio_live_ok': physicalPresent,
    'traffic': <String, Object?>{
      'rx': '1 KB',
      'tx': '2 KB',
      'rate': '3 KB/s',
      'rate_tx': '4 KB/s',
    },
    'traffic_raw': <String, Object?>{
      'rx': 1024,
      'tx': 2048,
      'rate': 3072,
      'rate_tx': 4096,
    },
    'traffic_meta': <String, Object?>{'status': ''},
  },
};

final class _Identities {
  const _Identities(this.imei, this.iccid, this.imsi, this.phone);

  factory _Identities.generate() => _Identities(
    _runtimeSecret(15, 3),
    _runtimeSecret(20, 5),
    _runtimeSecret(15, 7),
    _runtimeSecret(13, 11),
  );

  final String imei;
  final String iccid;
  final String imsi;
  final String phone;
}

String _runtimeSecret(int length, int offset) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}
