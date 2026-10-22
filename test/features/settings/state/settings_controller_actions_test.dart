import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/http_transport.dart';
import 'package:onewifi_android/core/http/request_registry.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/features/settings/data/product_license_store.dart';
import 'package:onewifi_android/features/settings/data/settings_repository.dart';
import 'package:onewifi_android/features/settings/domain/gateway_settings.dart';
import 'package:onewifi_android/features/settings/state/settings_controller.dart';

typedef _Notification = (ActionStatus, String, bool, Object?);

void main() {
  group('setLanguage', () {
    _Harness harness() => _Harness(
      action: (c) => c.languageAction,
      field: (c) => c.data.language,
    );
    const started = (ActionStatus.submitting, '', false, UiLanguage.zh);

    test('success: submitting, replace, succeeded, notice', () async {
      final h = harness();
      await h.controller.setLanguage(UiLanguage.en);
      expect(h.repo.calls, <String>['savePreferences']);
      expect(h.repo.savedLanguage, UiLanguage.en);
      expect(h.controller.languageAction.status, ActionStatus.succeeded);
      expect(h.controller.notice, 'Language saved');
      expect(h.controller.noticeError, isFalse);
      expect(h.controller.data.language, UiLanguage.en);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '', false, UiLanguage.en),
        (ActionStatus.succeeded, '', false, UiLanguage.en),
        (ActionStatus.succeeded, 'Language saved', false, UiLanguage.en),
      ]);
    });

    test('success notice follows the saved value, not the request', () async {
      final h = harness();
      h.repo.languageResult = UiLanguage.zh;
      await h.controller.setLanguage(UiLanguage.en);
      expect(h.repo.savedLanguage, UiLanguage.en);
      expect(h.controller.data.language, UiLanguage.zh);
      expect(h.controller.notice, '语言已保存');
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '', false, UiLanguage.zh),
        (ActionStatus.succeeded, '', false, UiLanguage.zh),
        (ActionStatus.succeeded, '语言已保存', false, UiLanguage.zh),
      ]);
    });

    test('failure: submitting, failed, error notice; data unchanged', () async {
      final h = harness()..fail();
      await h.controller.setLanguage(UiLanguage.en);
      expect(h.controller.languageAction.status, ActionStatus.failed);
      expect(h.controller.notice, '保存失败');
      expect(h.controller.noticeError, isTrue);
      expect(h.controller.data.language, UiLanguage.zh);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.failed, '', false, UiLanguage.zh),
        (ActionStatus.failed, '保存失败', true, UiLanguage.zh),
      ]);
    });

    test('single flight: second call while pending is ignored', () async {
      final h = harness();
      await _expectSingleFlight(
        h,
        () => h.controller.setLanguage(UiLanguage.en),
        started,
      );
      expect(h.controller.languageAction.status, ActionStatus.succeeded);
      expect(h.controller.data.language, UiLanguage.en);
    });

    test('late success after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(
        h,
        () => h.controller.setLanguage(UiLanguage.en),
        started,
      );
      expect(h.controller.data.language, UiLanguage.zh);
    });

    test('late failure after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(
        h,
        () => h.controller.setLanguage(UiLanguage.en),
        started,
        fail: true,
      );
      expect(h.controller.data.language, UiLanguage.zh);
    });

    test('same language short-circuits without ticket or notice', () async {
      final h = harness();
      await h.controller.setLanguage(UiLanguage.zh);
      expect(h.repo.calls, isEmpty);
      expect(h.controller.languageAction.status, ActionStatus.idle);
      expect(h.log, isEmpty);
    });
  });

  group('saveNotifications', () {
    _Harness harness() => _Harness(
      action: (c) => c.notifyAction,
      field: (c) => c.data.notifications.telegram.enabled,
    );
    const started = (ActionStatus.submitting, '', false, false);

    for (final channel in [NotifyChannel.telegram, NotifyChannel.webhook]) {
      test(
        'save receipt retains newer $channel draft for the next save',
        () async {
          final h = harness();
          const submitted = NotifyChannelSettings(
            enabled: true,
            url: 'submitted',
          );
          const edited = NotifyChannelSettings(enabled: false, url: 'later');
          h.controller.patchNotify(NotifyChannel.telegram, submitted);
          h.hold();
          final saving = h.controller.saveNotifications();
          h.controller.patchNotify(channel, edited);
          h.release();
          await saving;
          expect(h.controller.data.notifications.of(channel), same(edited));
          expect(h.controller.notice, contains('未保存'));
          await h.controller.load();
          expect(h.controller.data.notifications.of(channel), same(edited));
          await h.controller.saveNotifications();
          expect(h.repo.savedNotifications!.of(channel), same(edited));
        },
      );
    }

    test(
      'A to B to A editing is not acknowledged by an older receipt',
      () async {
        final h = harness();
        const a = NotifyChannelSettings(url: 'A');
        h.controller.patchNotify(NotifyChannel.telegram, a);
        h.hold();
        final saving = h.controller.saveNotifications();
        h.controller.patchNotify(
          NotifyChannel.telegram,
          const NotifyChannelSettings(url: 'B'),
        );
        h.controller.patchNotify(NotifyChannel.telegram, a);
        h.release();
        await saving;
        expect(h.controller.data.notifications.telegram, same(a));
        expect(h.controller.notice, contains('未保存'));
      },
    );

    test('success: submitting, replace, succeeded, notice', () async {
      final h = harness();
      await h.controller.saveNotifications();
      expect(h.repo.calls, <String>['saveNotifications']);
      expect(h.repo.savedNotifications!.telegram.enabled, isFalse);
      expect(h.controller.notifyAction.status, ActionStatus.succeeded);
      expect(h.controller.notice, '通知设置已保存');
      expect(h.controller.noticeError, isFalse);
      expect(h.controller.data.notifications, same(h.repo.notificationsResult));
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '', false, true),
        (ActionStatus.succeeded, '', false, true),
        (ActionStatus.succeeded, '通知设置已保存', false, true),
      ]);
    });

    test('failure: submitting, failed, error notice; data unchanged', () async {
      final h = harness()..fail();
      await h.controller.saveNotifications();
      expect(h.controller.notifyAction.status, ActionStatus.failed);
      expect(h.controller.notice, '保存失败');
      expect(h.controller.noticeError, isTrue);
      expect(h.controller.data.notifications.telegram.enabled, isFalse);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.failed, '', false, false),
        (ActionStatus.failed, '保存失败', true, false),
      ]);
    });

    test('single flight: second call while pending is ignored', () async {
      final h = harness();
      await _expectSingleFlight(h, h.controller.saveNotifications, started);
      expect(h.controller.notifyAction.status, ActionStatus.succeeded);
    });

    test('late success after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(h, h.controller.saveNotifications, started);
      expect(h.controller.data.notifications.telegram.enabled, isFalse);
    });

    test('late failure after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(
        h,
        h.controller.saveNotifications,
        started,
        fail: true,
      );
      expect(h.controller.data.notifications.telegram.enabled, isFalse);
    });
  });

  group('testChannel', () {
    _Harness harness() =>
        _Harness(action: (c) => c.testAction, field: (c) => c.testingChannel);
    const started = (
      ActionStatus.submitting,
      '',
      false,
      NotifyChannel.telegram,
    );

    test(
      'success keeps testingChannel through the notice, then clears',
      () async {
        final h = harness();
        await h.controller.testChannel(NotifyChannel.telegram);
        expect(h.repo.calls, <String>['testNotification']);
        expect(h.repo.testCalls, <NotifyChannel>[NotifyChannel.telegram]);
        expect(h.controller.testAction.status, ActionStatus.succeeded);
        expect(h.controller.notice, '测试已发送');
        expect(h.controller.noticeError, isFalse);
        expect(h.controller.testingChannel, isNull);
        expect(h.log, <_Notification>[
          started,
          (ActionStatus.succeeded, '', false, NotifyChannel.telegram),
          (ActionStatus.succeeded, '测试已发送', false, NotifyChannel.telegram),
        ]);
      },
    );

    test(
      'failure keeps testingChannel through the notice, then clears',
      () async {
        final h = harness()..fail();
        await h.controller.testChannel(NotifyChannel.telegram);
        expect(h.controller.testAction.status, ActionStatus.failed);
        expect(h.controller.notice, '测试失败');
        expect(h.controller.noticeError, isTrue);
        expect(h.controller.testingChannel, isNull);
        expect(h.log, <_Notification>[
          started,
          (ActionStatus.failed, '', false, NotifyChannel.telegram),
          (ActionStatus.failed, '测试失败', true, NotifyChannel.telegram),
        ]);
      },
    );

    test('single flight: another channel while pending is ignored', () async {
      final h = harness();
      await _expectSingleFlight(
        h,
        () => h.controller.testChannel(NotifyChannel.telegram),
        started,
        again: () => h.controller.testChannel(NotifyChannel.bark),
      );
      expect(h.repo.testCalls, <NotifyChannel>[NotifyChannel.telegram]);
      expect(h.controller.testAction.status, ActionStatus.succeeded);
      expect(h.controller.testingChannel, isNull);
    });

    test('pushplus while pending is silently ignored', () async {
      final h = harness();
      h.hold();
      final first = h.controller.testChannel(NotifyChannel.telegram);
      await h.controller.testChannel(NotifyChannel.pushplus);
      expect(h.log, <_Notification>[started]);
      expect(h.controller.notice, '');
      h.release();
      await first;
      expect(h.controller.notice, '测试已发送');
    });

    test('late success after dispose leaves testingChannel set', () async {
      final h = harness();
      await _expectLateIgnored(
        h,
        () => h.controller.testChannel(NotifyChannel.telegram),
        started,
      );
      expect(h.controller.testingChannel, NotifyChannel.telegram);
    });

    test('late failure after dispose leaves testingChannel set', () async {
      final h = harness();
      await _expectLateIgnored(
        h,
        () => h.controller.testChannel(NotifyChannel.telegram),
        started,
        fail: true,
      );
      expect(h.controller.testingChannel, NotifyChannel.telegram);
    });

    test('pushplus is rejected locally without a ticket', () async {
      final h = harness();
      await h.controller.testChannel(NotifyChannel.pushplus);
      expect(h.repo.calls, isEmpty);
      expect(h.controller.testAction.status, ActionStatus.idle);
      expect(h.controller.testingChannel, isNull);
      expect(h.log, <_Notification>[
        (ActionStatus.idle, '此通道不支持连通测试', true, null),
      ]);
    });
  });

  group('changePassword', () {
    _Harness harness() => _Harness(
      action: (c) => c.passwordAction,
      field: (c) => c.passwordChanged,
    );
    const started = (ActionStatus.submitting, '', false, false);
    Future<void> change(
      _Harness h, {
      String newPassword = 'new-password-1',
      String? confirmPassword,
    }) => h.controller.changePassword(
      currentPassword: 'old-password',
      newPassword: newPassword,
      confirmPassword: confirmPassword ?? newPassword,
    );

    test('success sets passwordChanged before succeeded', () async {
      final h = harness();
      await change(h);
      expect(h.repo.calls, <String>['changePassword']);
      expect(h.repo.passwords, (
        'old-password',
        'new-password-1',
        'new-password-1',
      ));
      expect(h.controller.passwordAction.status, ActionStatus.succeeded);
      expect(h.controller.notice, '密码已改，请重新登录');
      expect(h.controller.noticeError, isFalse);
      expect(h.controller.passwordChanged, isTrue);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.succeeded, '', false, true),
        (ActionStatus.succeeded, '密码已改，请重新登录', false, true),
      ]);
    });

    test('failure leaves passwordChanged false', () async {
      final h = harness()..fail();
      await change(h);
      expect(h.controller.passwordAction.status, ActionStatus.failed);
      expect(h.controller.notice, '改密失败');
      expect(h.controller.noticeError, isTrue);
      expect(h.controller.passwordChanged, isFalse);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.failed, '', false, false),
        (ActionStatus.failed, '改密失败', true, false),
      ]);
    });

    test('single flight: second call while pending is ignored', () async {
      final h = harness();
      await _expectSingleFlight(h, () => change(h), started);
      expect(h.controller.passwordAction.status, ActionStatus.succeeded);
      expect(h.controller.passwordChanged, isTrue);
    });

    test('short password while pending is silently ignored', () async {
      final h = harness();
      h.hold();
      final first = change(h);
      await change(h, newPassword: 'short');
      expect(h.log, <_Notification>[started]);
      expect(h.controller.notice, '');
      h.release();
      await first;
      expect(h.controller.notice, '密码已改，请重新登录');
    });

    test('late success after dispose leaves passwordChanged false', () async {
      final h = harness();
      await _expectLateIgnored(h, () => change(h), started);
      expect(h.controller.passwordChanged, isFalse);
    });

    test('late failure after dispose leaves passwordChanged false', () async {
      final h = harness();
      await _expectLateIgnored(h, () => change(h), started, fail: true);
      expect(h.controller.passwordChanged, isFalse);
    });

    test('short password never hits the API', () async {
      final h = harness();
      await change(h, newPassword: 'short');
      expect(h.repo.calls, isEmpty);
      expect(h.controller.passwordAction.status, ActionStatus.idle);
      expect(h.controller.passwordChanged, isFalse);
      expect(h.log, <_Notification>[
        (ActionStatus.idle, '新密码至少 10 位', true, false),
      ]);
    });

    test('mismatched passwords never hit the API', () async {
      final h = harness();
      await change(h, confirmPassword: 'new-password-2');
      expect(h.repo.calls, isEmpty);
      expect(h.controller.passwordAction.status, ActionStatus.idle);
      expect(h.controller.passwordChanged, isFalse);
      expect(h.log, <_Notification>[
        (ActionStatus.idle, '两次密码不一致', true, false),
      ]);
    });
  });

  group('saveSecurity', () {
    _Harness harness() => _Harness(
      action: (c) => c.securityAction,
      field: (c) => c.data.security.mode,
    );
    const started = (ActionStatus.submitting, '', false, AccessMode.internal);
    Future<void> save(_Harness h) => h.controller.saveSecurity(
      mode: AccessMode.public,
      allowedCidrsText: '10.0.0.0/8\n\n 192.168.0.0/16 ',
      trustProxyHeaders: true,
      trustedProxyCidrsText: '127.0.0.1/32',
    );

    test('success: submitting, replace, succeeded, notice', () async {
      final h = harness();
      await save(h);
      expect(h.repo.calls, <String>['saveSecurity']);
      final policy = h.repo.savedPolicy!;
      expect(policy.mode, AccessMode.public);
      expect(policy.allowedCidrs, <String>['10.0.0.0/8', '192.168.0.0/16']);
      expect(policy.trustProxyHeaders, isTrue);
      expect(policy.trustedProxyCidrs, <String>['127.0.0.1/32']);
      expect(policy.clientIp, '');
      expect(policy.clientAllowed, isTrue);
      expect(h.controller.securityAction.status, ActionStatus.succeeded);
      expect(h.controller.notice, '访问策略已保存');
      expect(h.controller.noticeError, isFalse);
      expect(h.controller.data.security, same(policy));
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '', false, AccessMode.public),
        (ActionStatus.succeeded, '', false, AccessMode.public),
        (ActionStatus.succeeded, '访问策略已保存', false, AccessMode.public),
      ]);
    });

    test('failure: submitting, failed, error notice; data unchanged', () async {
      final h = harness()..fail();
      await save(h);
      expect(h.controller.securityAction.status, ActionStatus.failed);
      expect(h.controller.notice, '访问策略保存失败');
      expect(h.controller.noticeError, isTrue);
      expect(h.controller.data.security.mode, AccessMode.internal);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.failed, '', false, AccessMode.internal),
        (ActionStatus.failed, '访问策略保存失败', true, AccessMode.internal),
      ]);
    });

    test('single flight: second call while pending is ignored', () async {
      final h = harness();
      await _expectSingleFlight(h, () => save(h), started);
      expect(h.controller.securityAction.status, ActionStatus.succeeded);
    });

    test('late success after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(h, () => save(h), started);
      expect(h.controller.data.security.mode, AccessMode.internal);
    });

    test('late failure after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(h, () => save(h), started, fail: true);
      expect(h.controller.data.security.mode, AccessMode.internal);
    });
  });

  group('setHttps', () {
    _Harness harness() => _Harness(
      action: (c) => c.httpsAction,
      field: (c) => c.data.https?.enabled,
    );
    const started = (ActionStatus.submitting, '', false, null);

    test('enable: submitting, replace, succeeded, notice', () async {
      final h = harness();
      await h.controller.setHttps(true);
      expect(h.repo.calls, <String>['saveHttps']);
      expect(h.repo.savedHttps, isTrue);
      expect(h.controller.httpsAction.status, ActionStatus.succeeded);
      expect(h.controller.notice, 'HTTPS 已开启，请用新地址重新登录');
      expect(h.controller.noticeError, isFalse);
      expect(h.controller.data.https!.enabled, isTrue);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '', false, true),
        (ActionStatus.succeeded, '', false, true),
        (ActionStatus.succeeded, 'HTTPS 已开启，请用新地址重新登录', false, true),
      ]);
    });

    test('disable: notice follows the argument', () async {
      final h = harness();
      await h.controller.setHttps(false);
      expect(h.repo.savedHttps, isFalse);
      expect(h.controller.notice, 'HTTPS 已关闭，请用 HTTP 地址重新登录');
      expect(h.controller.data.https!.enabled, isFalse);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '', false, false),
        (ActionStatus.succeeded, '', false, false),
        (ActionStatus.succeeded, 'HTTPS 已关闭，请用 HTTP 地址重新登录', false, false),
      ]);
    });

    test('failure: submitting, failed, error notice; data unchanged', () async {
      final h = harness()..fail();
      await h.controller.setHttps(true);
      expect(h.controller.httpsAction.status, ActionStatus.failed);
      expect(h.controller.notice, 'HTTPS 配置保存失败');
      expect(h.controller.noticeError, isTrue);
      expect(h.controller.data.https, isNull);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.failed, '', false, null),
        (ActionStatus.failed, 'HTTPS 配置保存失败', true, null),
      ]);
    });

    test('single flight: second call while pending is ignored', () async {
      final h = harness();
      await _expectSingleFlight(h, () => h.controller.setHttps(true), started);
      expect(h.controller.httpsAction.status, ActionStatus.succeeded);
    });

    test('late success after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(h, () => h.controller.setHttps(true), started);
      expect(h.controller.data.https, isNull);
    });

    test('late failure after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(
        h,
        () => h.controller.setHttps(true),
        started,
        fail: true,
      );
      expect(h.controller.data.https, isNull);
    });
  });

  group('saveQuota', () {
    _Harness harness() => _Harness(
      action: (c) => c.quotaAction,
      field: (c) {
        final quota = c.data.quota;
        return quota == null ? null : (quota.deviceLimit, quota.smsHourlyLimit);
      },
    );
    const started = (ActionStatus.submitting, '', false, null);

    test('device limit: submitting, replace, succeeded, notice', () async {
      final h = harness();
      await h.controller.saveQuota(deviceLimit: 6);
      expect(h.repo.calls, <String>['saveDeveloper']);
      expect(h.repo.savedQuota, (6, null));
      expect(h.controller.quotaAction.status, ActionStatus.succeeded);
      expect(h.controller.notice, '设备配额已保存');
      expect(h.controller.noticeError, isFalse);
      expect(h.controller.data.quota!.deviceLimit, 6);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '', false, (6, 20)),
        (ActionStatus.succeeded, '', false, (6, 20)),
        (ActionStatus.succeeded, '设备配额已保存', false, (6, 20)),
      ]);
    });

    test('sms limit: notice follows the argument', () async {
      final h = harness();
      await h.controller.saveQuota(smsHourlyLimit: 30);
      expect(h.repo.savedQuota, (null, 30));
      expect(h.controller.notice, '短信小时限额已保存');
      expect(h.controller.data.quota!.smsHourlyLimit, 30);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '', false, (4, 30)),
        (ActionStatus.succeeded, '', false, (4, 30)),
        (ActionStatus.succeeded, '短信小时限额已保存', false, (4, 30)),
      ]);
    });

    test('failure: submitting, failed, error notice; data unchanged', () async {
      final h = harness()..fail();
      await h.controller.saveQuota(deviceLimit: 6);
      expect(h.controller.quotaAction.status, ActionStatus.failed);
      expect(h.controller.notice, '保存失败');
      expect(h.controller.noticeError, isTrue);
      expect(h.controller.data.quota, isNull);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.failed, '', false, null),
        (ActionStatus.failed, '保存失败', true, null),
      ]);
    });

    test('single flight: second call while pending is ignored', () async {
      final h = harness();
      await _expectSingleFlight(
        h,
        () => h.controller.saveQuota(deviceLimit: 6),
        started,
      );
      expect(h.controller.quotaAction.status, ActionStatus.succeeded);
    });

    test('late success after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(
        h,
        () => h.controller.saveQuota(deviceLimit: 6),
        started,
      );
      expect(h.controller.data.quota, isNull);
    });

    test('late failure after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(
        h,
        () => h.controller.saveQuota(deviceLimit: 6),
        started,
        fail: true,
      );
      expect(h.controller.data.quota, isNull);
    });
  });

  group('activateLicense', () {
    _Harness harness() => _Harness(
      action: (c) => c.licenseAction,
      field: (c) => c.data.license.key,
    );
    const started = (ActionStatus.submitting, '', false, '');

    test('success: submitting, replace, succeeded, notice', () async {
      final h = harness();
      await h.controller.activateLicense('  KEY-1  ');
      expect(h.repo.calls, isEmpty);
      expect(h.license.writes, 1);
      expect(h.license.stored.key, 'KEY-1');
      expect(h.license.stored.activated, isTrue);
      expect(h.controller.licenseAction.status, ActionStatus.succeeded);
      expect(h.controller.notice, '授权码已绑定本机');
      expect(h.controller.noticeError, isFalse);
      expect(h.controller.data.license, same(h.license.stored));
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '', false, 'KEY-1'),
        (ActionStatus.succeeded, '', false, 'KEY-1'),
        (ActionStatus.succeeded, '授权码已绑定本机', false, 'KEY-1'),
      ]);
    });

    test('failure: submitting, failed, error notice; data unchanged', () async {
      final h = harness()..fail();
      await h.controller.activateLicense('KEY-1');
      expect(h.license.writes, 1);
      expect(h.license.stored.key, '');
      expect(h.controller.licenseAction.status, ActionStatus.failed);
      expect(h.controller.notice, '授权绑定失败');
      expect(h.controller.noticeError, isTrue);
      expect(h.controller.data.license.key, '');
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.failed, '', false, ''),
        (ActionStatus.failed, '授权绑定失败', true, ''),
      ]);
    });

    test('single flight: second call while pending is ignored', () async {
      final h = harness();
      await _expectSingleFlight(
        h,
        () => h.controller.activateLicense('KEY-1'),
        started,
        again: () => h.controller.activateLicense('KEY-2'),
      );
      expect(h.license.writes, 1);
      expect(h.controller.data.license.key, 'KEY-1');
    });

    test('blank key while pending still emits the notice', () async {
      final h = harness();
      h.hold();
      final first = h.controller.activateLicense('KEY-1');
      await h.controller.activateLicense('  ');
      expect(h.license.writes, 1);
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '先填授权码', true, ''),
      ]);
      h.release();
      await first;
      expect(h.log, <_Notification>[
        started,
        (ActionStatus.submitting, '先填授权码', true, ''),
        (ActionStatus.submitting, '先填授权码', true, 'KEY-1'),
        (ActionStatus.succeeded, '先填授权码', true, 'KEY-1'),
        (ActionStatus.succeeded, '授权码已绑定本机', false, 'KEY-1'),
      ]);
    });

    test('late success after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(
        h,
        () => h.controller.activateLicense('KEY-1'),
        started,
      );
      expect(h.license.stored.key, 'KEY-1');
      expect(h.controller.data.license.key, '');
    });

    test('late failure after dispose notifies nothing', () async {
      final h = harness();
      await _expectLateIgnored(
        h,
        () => h.controller.activateLicense('KEY-1'),
        started,
        fail: true,
      );
      expect(h.license.stored.key, '');
      expect(h.controller.data.license.key, '');
    });

    test('blank key is rejected without a ticket', () async {
      final h = harness();
      await h.controller.activateLicense('  ');
      expect(h.license.writes, 0);
      expect(h.controller.licenseAction.status, ActionStatus.idle);
      expect(h.log, <_Notification>[(ActionStatus.idle, '先填授权码', true, '')]);
    });
  });

  group('deactivateLicense', () {
    test('success: clears the android seat', () async {
      final h = _Harness(
        action: (c) => c.licenseAction,
        field: (c) => c.data.license.key,
      );
      await h.controller.activateLicense('KEY-1');
      h.log.clear();
      await h.controller.deactivateLicense();
      expect(h.license.stored.isActive, isFalse);
      expect(h.controller.notice, '已解除本机激活');
      expect(h.controller.data.license.isActive, isFalse);
    });

    test('idle when the seat is already empty', () async {
      final h = _Harness(
        action: (c) => c.licenseAction,
        field: (c) => c.data.license.key,
      );
      await h.controller.deactivateLicense();
      expect(h.license.writes, 0);
      expect(h.controller.notice, '当前未激活');
    });
  });
}

Future<void> _expectSingleFlight(
  _Harness h,
  Future<void> Function() start,
  _Notification started, {
  Future<void> Function()? again,
}) async {
  h.hold();
  final first = start();
  await (again ?? start)();
  expect(h.calls, 1);
  expect(h.status, ActionStatus.submitting);
  expect(h.log, <_Notification>[started]);
  h.release();
  await first;
}

Future<void> _expectLateIgnored(
  _Harness h,
  Future<void> Function() start,
  _Notification started, {
  bool fail = false,
}) async {
  h.hold();
  final pending = start();
  expect(h.calls, 1);
  expect(h.log, <_Notification>[started]);
  h.controller.dispose();
  if (fail) h.fail();
  h.release();
  await pending;
  expect(h.log, <_Notification>[started]);
  expect(h.status, ActionStatus.submitting);
  expect(h.controller.notice, '');
  expect(h.controller.noticeError, isFalse);
}

final class _Harness {
  _Harness({
    required ActionState Function(SettingsController controller) action,
    required Object? Function(SettingsController controller) field,
  }) : _action = action {
    controller = SettingsController(
      repository: repo,
      licenseStore: license,
      requestRegistry: RequestRegistry(),
    );
    controller.addListener(() {
      log.add((
        action(controller).status,
        controller.notice,
        controller.noticeError,
        field(controller),
      ));
    });
    addTearDown(controller.dispose);
  }

  final ActionState Function(SettingsController controller) _action;
  final _Repo repo = _Repo();
  final _LicenseStore license = _LicenseStore();
  final List<_Notification> log = <_Notification>[];
  late final SettingsController controller;
  Completer<void>? _gate;

  ActionStatus get status => _action(controller).status;

  int get calls => repo.calls.length + license.writes;

  void hold() {
    final gate = Completer<void>();
    _gate = gate;
    repo.gate = gate;
    license.gate = gate;
  }

  void release() => _gate?.complete();

  void fail() {
    final error = StateError('boom');
    repo.failure = error;
    license.failure = error;
  }
}

final class _LicenseStore implements ProductLicenseStore {
  Completer<void>? gate;
  Object? failure;
  int writes = 0;
  ProductLicense stored = const ProductLicense();

  @override
  Future<ProductLicense> read() async => stored;

  @override
  Future<void> write(ProductLicense license) async {
    writes += 1;
    final pending = gate;
    if (pending != null) await pending.future;
    final error = failure;
    if (error != null) throw error;
    stored = license;
  }

  @override
  Future<ProductLicense> activate(String key) async {
    final next = ProductLicense(key: key.trim(), activated: true);
    await write(next);
    return next;
  }

  @override
  Future<ProductLicense> deactivate() async {
    const next = ProductLicense();
    await write(next);
    return next;
  }
}

final class _Repo implements SettingsRepository {
  @override
  Future<VowifiMtuSettings> fetchVowifiSettings({
    RequestCancellation? cancellation,
  }) async => const VowifiMtuSettings();

  @override
  Future<VowifiMtuSettings> saveVowifiSettings(
    bool mtuCompatibility, {
    RequestCancellation? cancellation,
  }) async => VowifiMtuSettings(mtuCompatibility: mtuCompatibility);

  @override
  Future<SmsModemSettings> fetchSmsModemSettings({
    RequestCancellation? cancellation,
  }) async => const SmsModemSettings();

  @override
  Future<SmsModemSettings> saveSmsModemSettings(
    bool autoClearModemStorage, {
    RequestCancellation? cancellation,
  }) async => SmsModemSettings(autoClearModemStorage: autoClearModemStorage);

  @override
  Future<GatewayLicenseStatus?> fetchGatewayLicense({
    RequestCancellation? cancellation,
  }) async => null;

  Completer<void>? gate;
  Object? failure;
  final List<String> calls = <String>[];
  UiLanguage? savedLanguage;
  UiLanguage? languageResult;
  NotificationSettings? savedNotifications;
  final NotificationSettings notificationsResult = const NotificationSettings(
    telegram: NotifyChannelSettings(enabled: true),
  );
  final List<NotifyChannel> testCalls = <NotifyChannel>[];
  (String, String, String)? passwords;
  AccessPolicy? savedPolicy;
  bool? savedHttps;
  (int?, int?)? savedQuota;
  GatewayUpdate update = const GatewayUpdate(available: false);
  GatewayUpdateApply applyResult = const GatewayUpdateApply(applied: false);
  Future<T> _respond<T>(String name, T Function() result) async {
    calls.add(name);
    final pending = gate;
    if (pending != null) await pending.future;
    final error = failure;
    if (error != null) throw error;
    return result();
  }

  @override
  Future<GatewayUpdateApply> applyUpdate({RequestCancellation? cancellation}) =>
      _respond<GatewayUpdateApply>('applyUpdate', () => applyResult);

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
    RequestCancellation? cancellation,
  }) {
    passwords = (oldPassword, newPassword, confirmPassword);
    return _respond<void>('changePassword', () {});
  }

  @override
  Future<GatewayUpdate> checkUpdate({RequestCancellation? cancellation}) =>
      _respond<GatewayUpdate>('checkUpdate', () => update);

  @override
  Future<DeveloperQuota?> fetchDeveloper({
    RequestCancellation? cancellation,
  }) async => null;

  @override
  Future<HttpsSettings?> fetchHttps({
    RequestCancellation? cancellation,
  }) async => null;

  @override
  Future<NotificationSettings> fetchNotifications({
    RequestCancellation? cancellation,
  }) async => const NotificationSettings();

  @override
  Future<UiLanguage> fetchPreferences({
    RequestCancellation? cancellation,
  }) async => UiLanguage.zh;

  @override
  Future<AccessPolicy> fetchSecurity({
    RequestCancellation? cancellation,
  }) async => const AccessPolicy();

  @override
  Future<SystemInfo> fetchSystemInfo({
    RequestCancellation? cancellation,
  }) async => const SystemInfo();

  @override
  Future<DeveloperQuota> saveDeveloper({
    int? deviceLimit,
    int? smsHourlyLimit,
    RequestCancellation? cancellation,
  }) {
    savedQuota = (deviceLimit, smsHourlyLimit);
    return _respond<DeveloperQuota>(
      'saveDeveloper',
      () => DeveloperQuota(
        deviceLimit: deviceLimit ?? 4,
        maxDeviceLimit: 10,
        smsHourlyLimit: smsHourlyLimit ?? 20,
        maxSmsHourlyLimit: 20,
      ),
    );
  }

  @override
  Future<HttpsSettings> saveHttps(
    bool enabled, {
    RequestCancellation? cancellation,
  }) {
    savedHttps = enabled;
    return _respond<HttpsSettings>(
      'saveHttps',
      () => HttpsSettings(enabled: enabled),
    );
  }

  @override
  Future<HttpsSettings> uploadCustomCertificate({
    required String certificate,
    required String privateKey,
    RequestCancellation? cancellation,
  }) {
    return _respond<HttpsSettings>(
      'uploadCustomCertificate',
      () => const HttpsSettings(enabled: false),
    );
  }

  @override
  Future<HttpsSettings> deleteCustomCertificate({
    RequestCancellation? cancellation,
  }) {
    return _respond<HttpsSettings>(
      'deleteCustomCertificate',
      () => const HttpsSettings(enabled: false),
    );
  }

  @override
  Future<HttpsSettings> reissueCertificate({
    RequestCancellation? cancellation,
  }) {
    return _respond<HttpsSettings>(
      'reissueCertificate',
      () => const HttpsSettings(enabled: false),
    );
  }

  @override
  Future<NotificationSettings> saveNotifications(
    NotificationSettings notifications, {
    RequestCancellation? cancellation,
  }) {
    savedNotifications = notifications;
    return _respond<NotificationSettings>(
      'saveNotifications',
      () => notificationsResult,
    );
  }

  @override
  Future<UiLanguage> savePreferences(
    UiLanguage language, {
    RequestCancellation? cancellation,
  }) {
    savedLanguage = language;
    return _respond<UiLanguage>(
      'savePreferences',
      () => languageResult ?? language,
    );
  }

  @override
  Future<AccessPolicy> saveSecurity(
    AccessPolicy policy, {
    RequestCancellation? cancellation,
  }) {
    savedPolicy = policy;
    return _respond<AccessPolicy>('saveSecurity', () => policy);
  }

  @override
  Future<void> testNotification(
    NotifyChannel channel,
    NotifyChannelSettings settings, {
    RequestCancellation? cancellation,
  }) {
    testCalls.add(channel);
    return _respond<void>('testNotification', () {});
  }
}
