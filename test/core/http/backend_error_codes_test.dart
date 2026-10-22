import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/backend_error_codes.dart';

void main() {
  group('BackendErrorCodes.allow', () {
    test('returns the same string when code is in allowed set', () {
      expect(BackendErrorCodes.allow('device_not_found'), 'device_not_found');
      expect(BackendErrorCodes.allow('unauthorized'), 'unauthorized');
      expect(BackendErrorCodes.allow('internal_error'), 'internal_error');
      expect(BackendErrorCodes.allow('invalid_token'), 'invalid_token');
      expect(BackendErrorCodes.allow('not_found'), 'not_found');
    });

    test('returns null when code is not in allowed set', () {
      expect(BackendErrorCodes.allow('unknown_error'), isNull);
      expect(BackendErrorCodes.allow(''), isNull);
      expect(BackendErrorCodes.allow('device_not_found_typo'), isNull);
      expect(BackendErrorCodes.allow('DEVICE_NOT_FOUND'), isNull);
    });

    test('validates all documented error codes are allowed', () {
      const criticalCodes = [
        'apn_profile_not_found',
        'call_rejected',
        'certificate_unavailable',
        'device_exists',
        'device_limit_reached',
        'device_not_found',
        'esim_profile_not_found',
        'https_unavailable',
        'invalid_credentials',
        'invalid_csrf',
        'invalid_device',
        'invalid_token',
        'modem_error',
        'modem_timeout',
        'network_access_denied',
        'not_found',
        'password_mismatch',
        'request_canceled',
        'unauthorized',
        'unavailable',
        'update_apply_failed',
        'voice_calls_removed',
        'vowifi_busy',
        'vowifi_call_failed',
        'vowifi_disabled',
        'vowifi_error',
        'vowifi_not_running',
        'vowifi_provider_unavailable',
        'vowifi_runtime_unavailable',
        'vowifi_runtime_stopped',
        'weak_password',
      ];

      for (final code in criticalCodes) {
        expect(
          BackendErrorCodes.allow(code),
          code,
          reason: '$code should be in allowed set',
        );
      }
    });

    test('validates call-related error codes', () {
      const callCodes = [
        'call_media_unavailable',
        'call_rejected',
        'call_state',
        'call_not_found',
        'invalid_call_id',
        'invalid_dial_number',
        'vowifi_call_failed',
        'vowifi_voice_unavailable',
      ];

      for (final code in callCodes) {
        expect(
          BackendErrorCodes.allow(code),
          code,
          reason: 'Call-related code $code should be allowed',
        );
      }
    });

    test('validates esim-related error codes', () {
      const esimCodes = [
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
      ];

      for (final code in esimCodes) {
        expect(
          BackendErrorCodes.allow(code),
          code,
          reason: 'eSIM-related code $code should be allowed',
        );
      }
    });

    test('validates device-related error codes', () {
      const deviceCodes = [
        'device_exists',
        'device_feature_unsupported',
        'device_limit_reached',
        'device_manager_not_started',
        'device_manager_unavailable',
        'device_not_found',
        'device_required',
        'invalid_device',
        'invalid_device_config',
        'invalid_device_id',
        'invalid_device_limit',
        'invalid_device_name',
        'invalid_device_type',
        'physical_device_missing',
      ];

      for (final code in deviceCodes) {
        expect(
          BackendErrorCodes.allow(code),
          code,
          reason: 'Device-related code $code should be allowed',
        );
      }
    });

    test('validates proxy and network error codes', () {
      const networkCodes = [
        'binding_proxy_mismatch',
        'blocked_destination',
        'export_proxy_active',
        'export_proxy_invalid',
        'export_proxy_not_found',
        'invalid_proxy_addr',
        'invalid_proxy_id',
        'immutable_proxy_id',
        'network_access_denied',
        'public_ip_lookup_failed',
        'region_blocked',
        'unsafe_destination',
        'upstream_proxy_disabled',
      ];

      for (final code in networkCodes) {
        expect(
          BackendErrorCodes.allow(code),
          code,
          reason: 'Network-related code $code should be allowed',
        );
      }
    });

    test('edge cases with whitespace and special chars', () {
      expect(BackendErrorCodes.allow(' device_not_found'), isNull);
      expect(BackendErrorCodes.allow('device_not_found '), isNull);
      expect(BackendErrorCodes.allow('device-not-found'), isNull);
      expect(BackendErrorCodes.allow('device.not.found'), isNull);
    });

    test('validates auth and login-related error codes', () {
      const authCodes = [
        'https_required',
        'invalid_credentials',
        'invalid_csrf',
        'invalid_redirect_host',
        'invalid_token',
        'network_access_denied',
        'password_mismatch',
        'password_reused',
        'too_many_attempts',
        'unauthorized',
        'weak_password',
      ];

      for (final code in authCodes) {
        expect(
          BackendErrorCodes.allow(code),
          code,
          reason: 'Auth-related code $code should be allowed',
        );
      }
    });
  });
}
