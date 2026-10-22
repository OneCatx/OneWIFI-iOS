import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/features/esim/data/esim_api.dart';
import 'package:onewifi_android/features/esim/domain/card_policy.dart';
import '../../../support/fakes.dart';

void main() {
  test(
    'opaque identity distinguishes full ICCID and applet despite equal tails',
    () async {
      const first = '89860000000000001234';
      const second = '89860000000000011234';
      final api = EsimApi(
        _transport(
          FakeClient(
            (_) async => _success([
              for (final (iccid, aid) in [
                (first, 'AID0'),
                (second, 'AID0'),
                (first, 'AID1'),
              ])
                {
                  'eid': '1' * 32,
                  'aidHex': aid,
                  'profiles': [
                    {
                      'iccid': iccid,
                      'name': 'Line',
                      'serviceProviderName': 'Carrier',
                      'state': 0,
                      'stateText': 'disabled',
                      'classText': 'operational',
                    },
                  ],
                },
            ]),
          ),
        ),
      );
      final profiles = (await api.fetchProfiles(
        'device',
        refresh: false,
      )).profiles;
      expect(profiles.map((p) => p.iccidDisplay).toSet(), hasLength(1));
      expect(profiles.map((p) => p.target).toSet(), hasLength(3));
      for (final profile in profiles) {
        expect(profile.target.toString(), 'EsimSwitchTarget(redacted)');
      }
    },
  );

  test(
    'reads cached and refreshed profiles without exposing full ICCID',
    () async {
      final rawIccid = _runtimeDigits(20, 3);
      final requests = <http.BaseRequest>[];
      final api = EsimApi(
        _transport(
          FakeClient((request) async {
            requests.add(request);
            return _success(<Object?>[
              <String, Object?>{
                'eid': _runtimeDigits(32, 5),
                'aidHex': 'A0000005591010FFFFFFFF8900000177',
                'profiles': <Object?>[
                  <String, Object?>{
                    'iccid': rawIccid,
                    'name': 'Work line',
                    'serviceProviderName': 'One Carrier',
                    'state': 0,
                    'stateText': 'disabled',
                    'classText': 'operational',
                  },
                ],
              },
            ]);
          }),
        ),
      );

      final cached = await api.fetchProfiles('rack/a b', refresh: false);
      final refreshed = await api.fetchProfiles('rack/a b', refresh: true);

      expect(
        cached.profiles.single.iccidDisplay,
        endsWith(rawIccid.substring(16)),
      );
      expect(cached.profiles.single.toString().contains(rawIccid), isFalse);
      expect(
        cached.profiles.single.target.toString().contains(rawIccid),
        isFalse,
      );
      expect(refreshed.profiles, hasLength(1));
      expect(
        refreshed.profiles.single.target,
        cached.profiles.single.target,
        reason: 'a new DTO for the same card must keep opaque identity',
      );
      expect(
        refreshed.profiles.single.target.hashCode,
        cached.profiles.single.target.hashCode,
      );
      expect(requests.map((request) => request.url.toString()), <String>[
        'https://api.example.test/api/devices/rack%2Fa%20b/esim/profiles',
        'https://api.example.test/api/devices/rack%2Fa%20b/esim/profiles?refresh=1',
      ]);
    },
  );

  test(
    'switch posts the opaque target and accepts only verified terminal status',
    () async {
      final rawIccid = _runtimeDigits(20, 7);
      http.BaseRequest? switchRequest;
      final api = EsimApi(
        _transport(
          FakeClient((request) async {
            if (request.method == 'GET') {
              return _success(<Object?>[
                <String, Object?>{
                  'eid': '',
                  'aidHex': 'AID0',
                  'profiles': <Object?>[
                    <String, Object?>{
                      'iccid': rawIccid,
                      'name': 'Travel',
                      'serviceProviderName': 'Carrier',
                      'state': 0,
                      'stateText': 'disabled',
                      'classText': '',
                    },
                  ],
                },
              ]);
            }
            switchRequest = request;
            return _success(<String, Object?>{
              'status': 'switched',
              'iccid': rawIccid,
              'verified': true,
              'warning': _runtimeDigits(31, 9),
            });
          }),
        ),
      );
      final inventory = await api.fetchProfiles('device', refresh: false);

      final result = await api.switchProfile(
        'device',
        inventory.profiles.single.target,
      );

      expect(result.status.name, 'switched');
      expect(result.verified, isTrue);
      expect(switchRequest!.method, 'POST');
      expect(switchRequest!.headers['authorization'], startsWith('Bearer '));
      expect(switchRequest!.headers.containsKey('cookie'), isFalse);
      expect(switchRequest!.headers.containsKey('x-csrf-token'), isFalse);
      final body =
          jsonDecode(utf8.decode(await switchRequest!.finalize().toBytes()))
              as Map<String, Object?>;
      expect(body['iccid'] == rawIccid, isTrue);
      expect(body['aid_hex'], 'AID0');
    },
  );

  test('download consumes SSE until done and never retries', () async {
    final requests = <http.BaseRequest>[];
    final api = EsimApi(
      _transport(
        FakeClient((request) async {
          requests.add(request);
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode(
                'event: progress\ndata: {"step":"auth","msg":"ok","pct":40}\n\n',
              ),
              utf8.encode(
                'event: progress\ndata: {"step":"done","msg":"Profile 下载完成","pct":100}\n\n',
              ),
            ]),
            200,
            headers: const <String, String>{
              'content-type': 'text/event-stream',
            },
          );
        }),
      ),
    );
    final steps = <String>[];
    await api.downloadProfile(
      'modem-1',
      smdp: 'rsp.example.test',
      matchingId: 'mid',
      onProgress: (progress) => steps.add(progress.step),
    );
    expect(steps, <String>['auth', 'done']);
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.path,
      '/api/devices/modem-1/esim/actions/download',
    );
    expect(requests.single.headers['accept'], contains('text/event-stream'));
  });

  test('card policy PUT sends IP not IPV4', () async {
    http.BaseRequest? saved;
    final api = EsimApi(
      _transport(
        FakeClient((request) async {
          saved = request;
          return _success(<String, Object?>{
            'iccid': '89860012345678901234',
            'apn': 'ims',
            'ip_version': 'IP',
            'network_enabled': true,
            'vowifi_enabled': true,
            'airplane_enabled': true,
            'custom_phone_number': '',
            'source': 'manual',
          });
        }),
      ),
    );
    final inventory = await EsimApi(
      _transport(
        FakeClient(
          (_) async => _success(<Object?>[
            <String, Object?>{
              'eid': '1' * 32,
              'aidHex': 'AID0',
              'profiles': <Object?>[
                <String, Object?>{
                  'iccid': '89860012345678901234',
                  'name': 'Work',
                  'serviceProviderName': 'Carrier',
                  'state': 1,
                  'stateText': 'enabled',
                  'classText': 'operational',
                },
              ],
            },
          ]),
        ),
      ),
    ).fetchProfiles('device', refresh: false);
    final policy = await api.savePolicy(
      inventory.profiles.single.target,
      apn: 'ims',
      ipVersion: CardIpVersion.ip,
    );
    expect(policy.ipVersion, CardIpVersion.ip);
    final body =
        jsonDecode(utf8.decode(await saved!.finalize().toBytes()))
            as Map<String, Object?>;
    expect(body['ip_version'], 'IP');
    expect(body['apn'], 'ims');
    expect(body.containsKey('mbn_profile'), isFalse);
    expect(body.containsKey('voice_path'), isFalse);
  });

  test(
    'card policy PUT includes mbn_profile only when the caller sends it',
    () async {
      http.BaseRequest? saved;
      final api = EsimApi(
        _transport(
          FakeClient((request) async {
            saved = request;
            return _success(<String, Object?>{
              'iccid': '89860012345678901234',
              'apn': 'ims',
              'ip_version': 'IP',
              'mbn_profile': 'OpenMkt-Commercial-CU',
            });
          }),
        ),
      );
      final inventory = await EsimApi(
        _transport(
          FakeClient(
            (_) async => _success(<Object?>[
              <String, Object?>{
                'eid': '1' * 32,
                'aidHex': 'AID0',
                'profiles': <Object?>[
                  <String, Object?>{
                    'iccid': '89860012345678901234',
                    'name': 'Work',
                    'serviceProviderName': 'Carrier',
                    'state': 1,
                    'stateText': 'enabled',
                    'classText': 'operational',
                  },
                ],
              },
            ]),
          ),
        ),
      ).fetchProfiles('device', refresh: false);
      final policy = await api.savePolicy(
        inventory.profiles.single.target,
        apn: 'ims',
        ipVersion: CardIpVersion.ip,
        mbnProfile: 'OpenMkt-Commercial-CU',
      );
      expect(policy.mbnProfile, 'OpenMkt-Commercial-CU');
      final body =
          jsonDecode(utf8.decode(await saved!.finalize().toBytes()))
              as Map<String, Object?>;
      expect(body['mbn_profile'], 'OpenMkt-Commercial-CU');
      expect(body.containsKey('voice_path'), isFalse);
    },
  );

  test('card policy PUT sends voice_path only when the caller changes it', () async {
    http.BaseRequest? saved;
    final api = EsimApi(
      _transport(
        FakeClient((request) async {
          saved = request;
          return _success(<String, Object?>{
            'iccid': '89860012345678901234',
            'apn': 'ims',
            'ip_version': 'IP',
            'voice_path': 'cellular',
          });
        }),
      ),
    );
    final inventory = await EsimApi(
      _transport(
        FakeClient(
          (_) async => _success(<Object?>[
            <String, Object?>{
              'eid': '1' * 32,
              'aidHex': 'AID0',
              'profiles': <Object?>[
                <String, Object?>{
                  'iccid': '89860012345678901234',
                  'name': 'Work',
                  'serviceProviderName': 'Carrier',
                  'state': 1,
                  'stateText': 'enabled',
                  'classText': 'operational',
                },
              ],
            },
          ]),
        ),
      ),
    ).fetchProfiles('device', refresh: false);
    final policy = await api.savePolicy(
      inventory.profiles.single.target,
      apn: 'ims',
      ipVersion: CardIpVersion.ip,
      voicePath: CardVoicePath.cellular,
    );
    expect(policy.voicePath, CardVoicePath.cellular);
    final body =
        jsonDecode(utf8.decode(await saved!.finalize().toBytes()))
            as Map<String, Object?>;
    expect(body['voice_path'], 'cellular');
  });

  test(
    'card policy GET reads mbn_profile and defaults a missing voice_path to vowifi',
    () async {
      Future<EsimApi> apiFor(Map<String, Object?> policy) async {
        final client = FakeClient((request) async {
          if (request.url.path.contains('/esim/profiles')) {
            return _success(<Object?>[
              <String, Object?>{
                'eid': '1' * 32,
                'aidHex': 'AID0',
                'profiles': <Object?>[
                  <String, Object?>{
                    'iccid': '89860012345678901234',
                    'name': 'Work',
                    'serviceProviderName': 'Carrier',
                    'state': 1,
                    'stateText': 'enabled',
                    'classText': 'operational',
                  },
                ],
              },
            ]);
          }
          return _success(policy);
        });
        return EsimApi(_transport(client));
      }

      final withKey = await apiFor(<String, Object?>{
        'iccid': '89860012345678901234',
        'apn': 'ims',
        'ip_version': 'IPV4V6',
        'mbn_profile': 'OpenMkt-Commercial-CT',
      });
      final listed = await withKey.fetchProfiles('device', refresh: false);
      expect(
        (await withKey.fetchPolicy(listed.profiles.single.target)).mbnProfile,
        'OpenMkt-Commercial-CT',
      );
      expect(
        (await withKey.fetchPolicy(listed.profiles.single.target)).voicePath,
        CardVoicePath.vowifi,
      );

      final missing = await apiFor(<String, Object?>{
        'iccid': '89860012345678901234',
        'apn': 'ims',
        'ip_version': 'IPV4V6',
      });
      final again = await missing.fetchProfiles('device', refresh: false);
      expect(
        (await missing.fetchPolicy(again.profiles.single.target)).mbnProfile,
        isEmpty,
      );
      expect(
        (await missing.fetchPolicy(again.profiles.single.target)).voicePath,
        CardVoicePath.vowifi,
      );
    },
  );

  test('rename patches nickname; disable and delete use WEB verbs', () async {
    final rawIccid = _runtimeDigits(20, 9);
    final requests = <http.BaseRequest>[];
    final api = EsimApi(
      _transport(
        FakeClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return _success(<Object?>[
              <String, Object?>{
                'eid': '',
                'aidHex': 'AID1',
                'profiles': <Object?>[
                  <String, Object?>{
                    'iccid': rawIccid,
                    'name': 'Work',
                    'serviceProviderName': 'Carrier',
                    'state': 0,
                    'stateText': 'disabled',
                    'classText': 'operational',
                    'locked': false,
                  },
                ],
              },
            ]);
          }
          if (request.method == 'PATCH') {
            return _success(<String, Object?>{'status': 'renamed'});
          }
          if (request.method == 'POST') {
            return _success(<String, Object?>{'status': 'disabled'});
          }
          return _success(<String, Object?>{'status': 'deleted'});
        }),
      ),
    );
    final inventory = await api.fetchProfiles('rack/a', refresh: false);
    final target = inventory.profiles.single.target;
    await api.renameProfile('rack/a', target, name: 'Desk');
    await api.disableProfile('rack/a', target);
    await api.deleteProfile('rack/a', target);
    expect(
      requests.map((request) => '${request.method} ${request.url.path}'),
      <String>[
        'GET /api/devices/rack%2Fa/esim/profiles',
        'PATCH /api/devices/rack%2Fa/esim/profiles/$rawIccid',
        'POST /api/devices/rack%2Fa/esim/actions/disable',
        'DELETE /api/devices/rack%2Fa/esim/profiles/$rawIccid',
      ],
    );
    final renameBody =
        jsonDecode(utf8.decode(await requests[1].finalize().toBytes()))
            as Map<String, Object?>;
    expect(renameBody['name'], 'Desk');
    expect(renameBody['aid_hex'], 'AID1');
  });
}

HttpTransport _transport(http.BaseClient client) => HttpTransport(
  client: client,
  originProvider: () async => Uri.parse('https://api.example.test'),
  tokenProvider: (_) async => _runtimeDigits(47, 11),
  requestIdGenerator: () => 'safe-esim-test',
);

http.StreamedResponse _success(Object? data) => http.StreamedResponse(
  Stream<List<int>>.value(
    utf8.encode(jsonEncode(<String, Object?>{'data': data})),
  ),
  200,
);

String _runtimeDigits(int length, int offset) => List<String>.generate(
  length,
  (index) => ((index + offset) % 10).toString(),
).join();
