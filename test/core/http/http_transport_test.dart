import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:onewifi_android/core/http/http_transport.dart';
import '../../support/fakes.dart';

void main() {
  group('HttpTransport JSON envelope handling', () {
    test('returns data from a complete JSON success envelope', () async {
      final client = FakeClient((request) async {
        expect(
          request.url.toString(),
          'https://api.example.test/devices/a%2Fb',
        );
        expect(request.followRedirects, isFalse);
        return _jsonResponse(200, <String, Object?>{
          'data': <String, Object?>{'name': 'Router'},
        });
      });
      final transport = _transport(client: client);

      final result = await transport.sendJson(
        method: 'GET',
        routeTemplate: '/devices/{deviceId}',
        pathParameters: const <String, String>{'deviceId': 'a/b'},
      );

      expect(result, <String, Object?>{'name': 'Router'});
      expect(client.sendCount, 1);
    });

    test('decodes JSON as UTF-8 when Content-Type is missing', () async {
      const chinese = '未命名设备';
      final client = FakeClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.value(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'data': <String, Object?>{'name': chinese},
              }),
            ),
          ),
          200,
        ),
      );

      final result = await _transport(
        client: client,
      ).sendJson(method: 'GET', routeTemplate: '/api/devices');

      expect(result, <String, Object?>{'name': chinese});
    });

    test(
      'rejects malformed success bodies as sanitized protocol failures',
      () async {
        final sensitiveDigits = _digits(12);
        final client = FakeClient(
          (_) async => http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('not-json-$sensitiveDigits')),
            200,
          ),
        );
        final transport = _transport(client: client);

        await expectLater(
          transport.sendJson(method: 'GET', routeTemplate: '/devices'),
          throwsA(
            isA<ApiFailure>()
                .having(
                  (failure) => failure.kind,
                  'kind',
                  ApiFailureKind.protocol,
                )
                .having(
                  (failure) => failure.message.contains(sensitiveDigits),
                  'redacted message',
                  isFalse,
                )
                .having(
                  (failure) => failure.requestId.isNotEmpty,
                  'request id',
                  isTrue,
                ),
          ),
        );
      },
    );

    test('accepts an empty body only for a no-content status', () async {
      final client = FakeClient(
        (_) async => http.StreamedResponse(Stream<List<int>>.empty(), 204),
      );

      final result = await _transport(client: client).sendJson(
        method: 'DELETE',
        routeTemplate: '/devices/{id}',
        pathParameters: const <String, String>{'id': 'device'},
      );

      expect(result, isNull);
    });

    test(
      'accepts 205 empty body and rejects non-empty 204 or 205 bodies',
      () async {
        final client = FakeClient(
          (_) async => http.StreamedResponse(Stream<List<int>>.empty(), 205),
        );
        final transport = _transport(client: client);

        expect(
          await transport.sendJson(method: 'POST', routeTemplate: '/actions'),
          isNull,
        );

        for (final statusCode in <int>[204, 205]) {
          final nonEmptyClient = FakeClient(
            (_) async => _jsonResponse(statusCode, <String, String>{
              'unexpected': 'body',
            }),
          );
          await expectLater(
            _transport(
              client: nonEmptyClient,
            ).sendJson(method: 'DELETE', routeTemplate: '/actions'),
            throwsA(
              isA<ApiFailure>().having(
                (failure) => failure.kind,
                'kind',
                ApiFailureKind.protocol,
              ),
            ),
          );
        }
      },
    );

    test(
      'filters null query values and encodes remaining query values',
      () async {
        final client = FakeClient((request) async {
          expect(request.url.queryParameters.containsKey('absent'), isFalse);
          expect(request.url.queryParameters['filter'], 'space / slash');
          return _jsonResponse(200, <String, Object?>{'data': null});
        });

        await _transport(client: client).sendJson(
          method: 'GET',
          routeTemplate: '/devices',
          queryParameters: const <String, String?>{
            'absent': null,
            'filter': 'space / slash',
          },
        );
      },
    );

    test('rejects invalid route templates before a network attempt', () async {
      final client = FakeClient(
        (_) async => _jsonResponse(200, <String, Object?>{'data': null}),
      );
      final transport = _transport(client: client);

      await expectLater(
        transport.sendJson(method: 'GET', routeTemplate: '/devices/{missing}'),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      await expectLater(
        transport.sendJson(
          method: 'GET',
          routeTemplate: 'https://elsewhere.example.test/devices',
        ),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
      expect(client.sendCount, 0);
    });
  });

  group('HttpTransport structured failures', () {
    test('never retains opaque backend error code or message', () async {
      final opaqueCode = _runtimeSecret(length: 48, offset: 4);
      final opaqueMessage = _runtimeSecret(length: 64, offset: 9);
      final client = FakeClient(
        (_) async => _jsonResponse(429, <String, Object?>{
          'error': <String, Object?>{
            'code': opaqueCode,
            'message': opaqueMessage,
          },
        }),
      );

      await expectLater(
        _transport(
          client: client,
        ).sendJson(method: 'GET', routeTemplate: '/devices'),
        throwsA(
          isA<ApiFailure>()
              .having((failure) => failure.kind, 'kind', ApiFailureKind.http)
              .having((failure) => failure.statusCode, 'status', 429)
              .having(
                (failure) => failure.backendCode == opaqueCode,
                'opaque code retained',
                isFalse,
              )
              .having(
                (failure) => failure.message == opaqueMessage,
                'opaque message retained',
                isFalse,
              ),
        ),
      );
    });

    test(
      'round-trips every frozen WEB error code and rejects unsafe values',
      () async {
        const frozenWebCodes = <String>[
          'apn_profile_not_found',
          'at_port_unavailable',
          'binding_proxy_mismatch',
          'blocked_destination',
          'call_media_unavailable',
          'call_rejected',
          'cellular_data_active',
          'cellular_data_disabled',
          'cellular_interface_missing',
          'certificate_unavailable',
          'container_update_required',
          'data_backend_unavailable',
          'database_error',
          'developer_mode_required',
          'device_exists',
          'device_feature_unsupported',
          'device_limit_reached',
          'device_manager_not_started',
          'device_manager_unavailable',
          'device_not_found',
          'device_required',
          'duplicate_iccid',
          'esim_cat_busy',
          'esim_delete_disallowed_by_policy',
          'esim_disable_disallowed_by_policy',
          'esim_nickname_too_long',
          'esim_operation_unavailable',
          'esim_profile_enabled',
          'esim_profile_not_enabled',
          'esim_profile_not_found',
          'esim_qmi_unavailable',
          'euicc_channel_stuck',
          'export_proxy_active',
          'export_proxy_invalid',
          'export_proxy_not_found',
          'extensions_unavailable',
          'https_required',
          'https_unavailable',
          'https_update_failed',
          'immutable_device_id',
          'immutable_proxy_id',
          'ims_sms_submission_failed',
          'internal_error',
          'invalid_access_policy',
          'invalid_apn',
          'invalid_apn_credentials',
          'invalid_apn_profile',
          'invalid_auth_type',
          'invalid_automatic_task',
          'invalid_bindings',
          'invalid_call_id',
          'invalid_card_policy',
          'invalid_country',
          'invalid_credentials',
          'invalid_csrf',
          'invalid_device',
          'invalid_device_config',
          'invalid_device_id',
          'invalid_device_limit',
          'invalid_device_name',
          'invalid_device_type',
          'invalid_duration',
          'invalid_iccid',
          'invalid_ip_version',
          'invalid_language',
          'invalid_logging_policy',
          'invalid_mcc',
          'invalid_mnc',
          'invalid_notification_channel',
          'invalid_notification_config',
          'invalid_number',
          'invalid_peer',
          'invalid_plugin_upload',
          'invalid_proxy_addr',
          'invalid_proxy_id',
          'invalid_range',
          'invalid_redirect_host',
          'invalid_request',
          'invalid_roaming_ip_version',
          'invalid_sms_hourly_limit',
          'invalid_sms_id',
          'invalid_task_id',
          'invalid_token',
          'log_stream_unavailable',
          'method_not_allowed',
          'modem_error',
          'modem_timeout',
          'network_access_denied',
          'not_found',
          'notification_not_configured',
          'notification_provider_rejected',
          'notification_test_failed',
          'notification_test_unsupported',
          'password_mismatch',
          'password_reused',
          'physical_device_missing',
          'plugin_install_failed',
          'plugin_not_found',
          'plugin_state_failed',
          'plugin_uninstall_failed',
          'profile_already_bound',
          'public_ip_lookup_failed',
          'region_blocked',
          'request_canceled',
          'scheduler_unavailable',
          'sim_identity_unavailable',
          'task_unavailable',
          'too_many_attempts',
          'unauthorized',
          'unavailable',
          'unsafe_at_command',
          'unsafe_destination',
          'update_apply_failed',
          'update_busy',
          'update_check_failed',
          'update_session_revocation_failed',
          'upstream_proxy_disabled',
          'voice_calls_removed',
          'vowifi_busy',
          'vowifi_call_failed',
          'vowifi_device_unavailable',
          'vowifi_disabled',
          'vowifi_error',
          'vowifi_not_running',
          'vowifi_owns_airplane_mode',
          'vowifi_owns_radio',
          'vowifi_provider_unavailable',
          'vowifi_runtime_stopped',
          'vowifi_voice_unavailable',
          'weak_password',
          'websheet_not_found',
          'wifi_calling_only_device',
        ];
        final unsafeCodes = <String>[
          _runtimeSecret(length: 48, offset: 2),
          'UNAUTHORIZED',
          'invalid.code',
          List<String>.filled(257, 'a').join(),
        ];
        final responseCodes = <String>[...frozenWebCodes, ...unsafeCodes];
        var index = 0;
        final client = FakeClient((_) async {
          final code = responseCodes[index++];
          return _jsonResponse(400, <String, Object?>{
            'error': <String, String>{'code': code, 'message': 'ignored'},
          });
        });
        final transport = _transport(client: client);

        for (final code in frozenWebCodes) {
          final failure = await _apiFailureOf(
            transport.sendJson(method: 'GET', routeTemplate: '/devices'),
          );
          expect(
            failure.backendCode == code,
            isTrue,
            reason: 'frozen WEB code rejected',
          );
        }
        for (final _ in unsafeCodes) {
          final failure = await _apiFailureOf(
            transport.sendJson(method: 'GET', routeTemplate: '/devices'),
          );
          expect(
            failure.backendCode == null,
            isTrue,
            reason: 'unsafe server code retained',
          );
        }
      },
    );
  });

  group('HttpTransport authentication headers', () {
    test(
      'omits credentials for auth-none and sends only bearer authorization',
      () async {
        final client = FakeClient(
          (request) async =>
              _jsonResponse(200, <String, Object?>{'data': null}),
        );
        final transport = _transport(
          client: client,
          tokenProvider: (_) async => _runtimeSecret(length: 32, offset: 2),
        );

        await transport.sendJson(
          method: 'POST',
          routeTemplate: '/login',
          authMode: AuthMode.none,
          body: const <String, String>{'username': 'person'},
        );
        await transport.sendJson(method: 'GET', routeTemplate: '/devices');

        final anonymousHeaders = client.requests[0].headers;
        expect(anonymousHeaders.containsKey('authorization'), isFalse);
        expect(anonymousHeaders.containsKey('cookie'), isFalse);
        expect(anonymousHeaders.containsKey('x-csrf-token'), isFalse);
        expect(
          client.requests[1].headers['authorization'],
          startsWith('Bearer '),
        );
        expect(client.requests[1].headers.containsKey('cookie'), isFalse);
        expect(client.requests[1].headers.containsKey('x-csrf-token'), isFalse);
      },
    );

    test(
      'fails missing bearer token before creating a network attempt',
      () async {
        final client = FakeClient(
          (_) async => _jsonResponse(200, <String, Object?>{'data': null}),
        );

        await expectLater(
          _transport(
            client: client,
            tokenProvider: (_) async => null,
          ).sendJson(method: 'GET', routeTemplate: '/devices'),
          throwsA(
            isA<ApiFailure>().having(
              (failure) => failure.kind,
              'kind',
              ApiFailureKind.authentication,
            ),
          ),
        );

        expect(client.sendCount, 0);
      },
    );
  });

  group('HttpTransport session expiry', () {
    test(
      'forwards the captured epoch only for expiring bearer 401 responses',
      () async {
        final capturedEpochs = <int>[];
        final client = FakeClient(
          (_) async => _jsonResponse(401, <String, Object?>{
            'error': <String, String>{
              'code': 'UNAUTHORIZED',
              'message': 'Sign in again',
            },
          }),
        );
        final transport = _transport(
          client: client,
          sessionEpoch: () => 41,
          onUnauthorized: (epoch) => capturedEpochs.add(epoch),
        );

        await expectLater(
          transport.sendJson(method: 'GET', routeTemplate: '/devices'),
          throwsA(
            isA<ApiFailure>().having(
              (failure) => failure.statusCode,
              'status',
              401,
            ),
          ),
        );
        expect(capturedEpochs, <int>[41]);
      },
    );

    test(
      'expires a qualifying bearer 401 before malformed envelope parsing',
      () async {
        final capturedEpochs = <int>[];
        final client = FakeClient(
          (_) async => http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('not-json')),
            401,
          ),
        );

        await expectLater(
          _transport(
            client: client,
            sessionEpoch: () => 7,
            onUnauthorized: capturedEpochs.add,
          ).sendJson(method: 'GET', routeTemplate: '/devices'),
          throwsA(
            isA<ApiFailure>().having(
              (failure) => failure.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
        );

        expect(capturedEpochs, <int>[7]);
      },
    );

    test(
      'does not expire for forbidden or explicitly non-expiring requests',
      () async {
        final capturedEpochs = <int>[];
        var responseStatus = 403;
        final client = FakeClient(
          (_) async => _jsonResponse(responseStatus, <String, Object?>{
            'error': <String, String>{'code': 'DENIED', 'message': 'Denied'},
          }),
        );
        final transport = _transport(
          client: client,
          onUnauthorized: capturedEpochs.add,
        );

        await expectLater(
          transport.sendJson(method: 'GET', routeTemplate: '/devices'),
          throwsA(isA<ApiFailure>()),
        );
        responseStatus = 401;
        await expectLater(
          transport.sendJson(
            method: 'POST',
            routeTemplate: '/login',
            authMode: AuthMode.none,
            expireSessionOnUnauthorized: false,
          ),
          throwsA(isA<ApiFailure>()),
        );
        await expectLater(
          transport.sendJson(
            method: 'GET',
            routeTemplate: '/devices',
            expireSessionOnUnauthorized: false,
          ),
          throwsA(isA<ApiFailure>()),
        );

        expect(capturedEpochs, isEmpty);
      },
    );
  });

  group('HttpTransport retry hints', () {
    test(
      'parses delta-seconds and HTTP-date Retry-After without throwing on invalid input',
      () async {
        var retryAfter = '12';
        final client = FakeClient(
          (_) async => _jsonResponse(
            503,
            <String, Object?>{
              'error': <String, String>{'code': 'BUSY', 'message': 'Try later'},
            },
            headers: <String, String>{'retry-after': retryAfter},
          ),
        );
        final transport = _transport(
          client: client,
          clock: () => DateTime.utc(2015, 10, 21, 7, 27),
        );

        await expectLater(
          transport.sendJson(method: 'GET', routeTemplate: '/devices'),
          throwsA(
            isA<ApiFailure>().having(
              (failure) => failure.retryAfter,
              'delta retry-after',
              const Duration(seconds: 12),
            ),
          ),
        );
        retryAfter = 'Wed, 21 Oct 2015 07:28:00 GMT';
        await expectLater(
          transport.sendJson(method: 'GET', routeTemplate: '/devices'),
          throwsA(
            isA<ApiFailure>().having(
              (failure) => failure.retryAfter,
              'date retry-after',
              const Duration(minutes: 1),
            ),
          ),
        );
        retryAfter = 'not-a-delay';
        await expectLater(
          transport.sendJson(method: 'GET', routeTemplate: '/devices'),
          throwsA(
            isA<ApiFailure>().having(
              (failure) => failure.retryAfter,
              'invalid retry-after',
              isNull,
            ),
          ),
        );
      },
    );
  });

  group('HttpTransport redirects and attempts', () {
    test(
      'rejects redirects without retaining location and makes one attempt',
      () async {
        final sensitiveLocation =
            'https://elsewhere.example.test/${_digits(12)}';
        final client = FakeClient(
          (_) async => http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('redirect')),
            302,
            headers: <String, String>{'location': sensitiveLocation},
          ),
        );

        await expectLater(
          _transport(
            client: client,
          ).sendJson(method: 'POST', routeTemplate: '/actions'),
          throwsA(
            isA<ApiFailure>()
                .having(
                  (failure) => failure.kind,
                  'kind',
                  ApiFailureKind.redirect,
                )
                .having(
                  (failure) => failure.message.contains(sensitiveLocation),
                  'sanitized message',
                  isFalse,
                ),
          ),
        );

        expect(client.sendCount, 1);
        expect(client.requests.single.followRedirects, isFalse);
      },
    );
  });

  group('HttpTransport request identifiers', () {
    test(
      'generates a fresh non-sensitive default identifier for each request',
      () async {
        final token = _runtimeSecret(length: 40, offset: 12);
        final bodyValue = _runtimeSecret(length: 40, offset: 15);
        final client = FakeClient(
          (_) async => _jsonResponse(500, <String, Object?>{
            'error': <String, String>{'code': 'INTERNAL', 'message': 'ignored'},
          }),
        );
        final transport = HttpTransport(
          client: client,
          originProvider: () async => Uri.parse('https://api.example.test'),
          tokenProvider: (_) async => token,
        );

        final first = await _apiFailureOf(
          transport.sendJson(
            method: 'POST',
            routeTemplate: '/devices',
            body: <String, String>{'value': bodyValue},
          ),
        );
        final second = await _apiFailureOf(
          transport.sendJson(method: 'GET', routeTemplate: '/devices'),
        );

        expect(first.requestId.isNotEmpty, isTrue);
        expect(second.requestId.isNotEmpty, isTrue);
        expect(first.requestId == second.requestId, isFalse);
        expect(first.requestId.contains(token), isFalse);
        expect(first.requestId.contains(bodyValue), isFalse);
        expect(first.requestId.contains('api.example.test'), isFalse);
      },
    );
  });

  group('HttpTransport cancellation', () {
    test('does not send a pre-cancelled request', () async {
      final cancellation = RequestCancellation()..cancel();
      final client = FakeClient(
        (_) async => _jsonResponse(200, <String, Object?>{'data': null}),
      );

      await expectLater(
        _transport(client: client).sendJson(
          method: 'GET',
          routeTemplate: '/devices',
          cancellation: cancellation,
        ),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.cancelled,
          ),
        ),
      );

      expect(client.sendCount, 0);
    });

    test(
      'surfaces in-flight cancellation through an AbortableRequest',
      () async {
        final cancellation = RequestCancellation();
        final started = Completer<void>();
        final client = FakeClient((request) {
          started.complete();
          return _waitForAbort(request);
        });
        final pending = _transport(client: client).sendJson(
          method: 'GET',
          routeTemplate: '/devices',
          cancellation: cancellation,
        );
        await started.future;
        cancellation.cancel();

        await expectLater(
          pending,
          throwsA(
            isA<ApiFailure>().having(
              (failure) => failure.kind,
              'kind',
              ApiFailureKind.cancelled,
            ),
          ),
        );
        expect(client.sendCount, 1);
      },
    );

    test('surfaces timeout through the same abort mechanism', () async {
      final client = FakeClient(_waitForAbort);

      await expectLater(
        _transport(client: client).sendJson(
          method: 'GET',
          routeTemplate: '/devices',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.timeout,
          ),
        ),
      );
      expect(client.sendCount, 1);
    });

    test(
      'cancels while the origin provider is pending and consumes its late error',
      () async {
        final origin = Completer<Uri>();
        final cancellation = RequestCancellation();
        final client = FakeClient(
          (_) async => _jsonResponse(200, <String, Object?>{'data': null}),
        );
        final pending =
            HttpTransport(
              client: client,
              originProvider: () => origin.future,
              tokenProvider: (_) async => 'token-value',
            ).sendJson(
              method: 'GET',
              routeTemplate: '/devices',
              cancellation: cancellation,
            );

        cancellation.cancel();
        origin.completeError(StateError('late origin failure'));

        await expectLater(
          pending,
          throwsA(
            isA<ApiFailure>().having(
              (failure) => failure.kind,
              'kind',
              ApiFailureKind.cancelled,
            ),
          ),
        );
        expect(client.sendCount, 0);
      },
    );

    test(
      'times out while the token provider is pending and consumes its late error',
      () async {
        final token = Completer<String?>();
        final client = FakeClient(
          (_) async => _jsonResponse(200, <String, Object?>{'data': null}),
        );
        final pending =
            HttpTransport(
              client: client,
              originProvider: () async => Uri.parse('https://api.example.test'),
              tokenProvider: (_) => token.future,
            ).sendJson(
              method: 'GET',
              routeTemplate: '/devices',
              timeout: const Duration(milliseconds: 10),
            );

        try {
          await expectLater(
            pending.timeout(const Duration(milliseconds: 100)),
            throwsA(
              isA<ApiFailure>().having(
                (failure) => failure.kind,
                'kind',
                ApiFailureKind.timeout,
              ),
            ),
          );
        } finally {
          token.completeError(StateError('late token failure'));
        }
        expect(client.sendCount, 0);
      },
    );
  });

  group('HttpTransport SSE', () {
    test(
      'streams progress frames and stops when the callback returns false',
      () async {
        final client = FakeClient((request) async {
          expect(request.headers['accept'], contains('text/event-stream'));
          expect(request.headers['authorization'], startsWith('Bearer '));
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode('event: progress\ndata: {"step":"auth"}\n\n'),
              utf8.encode('event: progress\ndata: {"step":"done"}\n\n'),
              utf8.encode('event: progress\ndata: {"step":"late"}\n\n'),
            ]),
            200,
            headers: const <String, String>{
              'content-type': 'text/event-stream',
            },
          );
        });
        final steps = <String>[];
        await _transport(client: client).sendSse(
          method: 'POST',
          routeTemplate: '/api/devices/{id}/esim/actions/download',
          pathParameters: const <String, String>{'id': 'modem-1'},
          body: const <String, String>{'smdp': 'rsp.example.test'},
          onEvent: (event) {
            steps.add(event.data);
            return !event.data.contains('done');
          },
        );
        expect(steps, hasLength(2));
        expect(steps.last, contains('done'));
      },
    );

    test('reassembles a UTF-8 character split across SSE chunks', () async {
      final payload = utf8.encode('data: {"msg":"下载中…"}\n\n');
      final cut = utf8.encode('data: {"msg":"').length + 1;
      final client = FakeClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.fromIterable(<List<int>>[
            payload.sublist(0, cut),
            payload.sublist(cut),
          ]),
          200,
          headers: const <String, String>{'content-type': 'text/event-stream'},
        ),
      );
      final events = <String>[];
      await _transport(client: client).sendSse(
        method: 'POST',
        routeTemplate: '/api/devices/{id}/esim/actions/download',
        pathParameters: const <String, String>{'id': 'modem-1'},
        body: const <String, String>{'smdp': 'rsp.example.test'},
        onEvent: (event) {
          events.add(event.data);
          return true;
        },
      );
      expect(events.single, '{"msg":"下载中…"}');
    });

    test('maps JSON error envelopes before the stream starts', () async {
      final client = FakeClient(
        (_) async => _jsonResponse(400, <String, Object?>{
          'error': <String, String>{
            'code': 'invalid_request',
            'message': 'smdp 为必填项',
          },
        }),
      );
      await expectLater(
        _transport(client: client).sendSse(
          method: 'POST',
          routeTemplate: '/api/devices/{id}/esim/actions/download',
          pathParameters: const <String, String>{'id': 'modem-1'},
          body: const <String, String>{'smdp': ''},
          onEvent: (_) => true,
        ),
        throwsA(
          isA<ApiFailure>()
              .having((failure) => failure.kind, 'kind', ApiFailureKind.http)
              .having((failure) => failure.statusCode, 'status', 400)
              .having(
                (failure) => failure.backendCode,
                'code',
                'invalid_request',
              ),
        ),
      );
    });
  });

  group('HttpTransport sendBytes', () {
    test('returns raw body bytes on success', () async {
      const pem = '-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----\n';
      http.BaseRequest? captured;
      final client = FakeClient((request) async {
        captured = request;
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(pem)),
          200,
          headers: const <String, String>{
            'content-type': 'application/x-pem-file',
          },
        );
      });

      final bytes = await _transport(client: client).sendBytes(
        method: 'GET',
        routeTemplate: '/api/settings/https/certificate',
        accept: 'application/x-pem-file, */*',
      );

      expect(utf8.decode(bytes), pem);
      expect(captured!.headers['accept'], 'application/x-pem-file, */*');
      expect(captured!.headers['authorization'], 'Bearer token-value');
    });

    test('maps JSON error envelope to ApiFailure', () async {
      final client = FakeClient(
        (_) async => _jsonResponse(503, <String, Object?>{
          'error': <String, Object?>{
            'code': 'https_unavailable',
            'message': 'self-signed HTTPS is unavailable',
          },
        }),
      );

      await expectLater(
        _transport(client: client).sendBytes(
          method: 'GET',
          routeTemplate: '/api/settings/https/certificate',
        ),
        throwsA(
          isA<ApiFailure>()
              .having((f) => f.kind, 'kind', ApiFailureKind.http)
              .having((f) => f.statusCode, 'status', 503),
        ),
      );
    });
  });
}

HttpTransport _transport({
  required http.BaseClient client,
  Future<String?> Function(Uri origin)? tokenProvider,
  FutureOr<void> Function(int capturedSessionEpoch)? onUnauthorized,
  int Function()? sessionEpoch,
  DateTime Function()? clock,
}) {
  return HttpTransport(
    client: client,
    originProvider: () async => Uri.parse('https://api.example.test'),
    tokenProvider: tokenProvider ?? (_) async => 'token-value',
    onUnauthorized: onUnauthorized,
    sessionEpoch: sessionEpoch,
    clock: clock,
    requestIdGenerator: () => 'local-request-id',
  );
}

http.StreamedResponse _jsonResponse(
  int statusCode,
  Object? body, {
  Map<String, String>? headers,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    statusCode,
    headers: headers ?? const <String, String>{},
  );
}

String _digits(int length) {
  return List<String>.generate(
    length,
    (index) => (index % 10).toString(),
  ).join();
}

String _runtimeSecret({required int length, required int offset}) {
  return List<String>.generate(
    length,
    (index) => String.fromCharCode(65 + ((index + offset) % 26)),
  ).join();
}

Future<http.StreamedResponse> _waitForAbort(http.BaseRequest request) async {
  final abortTrigger = (request as http.AbortableRequest).abortTrigger;
  if (abortTrigger == null) {
    return Completer<http.StreamedResponse>().future;
  }
  await abortTrigger;
  throw http.RequestAbortedException(request.url);
}

Future<ApiFailure> _apiFailureOf(Future<Object?> pending) async {
  try {
    await pending;
  } on ApiFailure catch (failure) {
    return failure;
  }
  throw StateError('Expected ApiFailure');
}
