import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/sms/domain/sms_code_extractor.dart';

void main() {
  test('标准中文语序：关键词后跟码', () {
    expect(SmsCodeExtractor.extract('【京东】验证码：123456，5分钟内有效。'), '123456');
  });

  test('动态密码关键词：四位码', () {
    expect(SmsCodeExtractor.extract('您的动态密码为 8492，请勿泄露。'), '8492');
  });

  test('码在关键词之前的语序', () {
    expect(SmsCodeExtractor.extract('975316（腾讯科技短信验证码）'), '975316');
  });

  test('谷歌式字母连字符前缀只取数字段', () {
    expect(
      SmsCodeExtractor.extract('Your Google verification code is G-482915'),
      '482915',
    );
  });

  test('英文短信：码在关键词前', () {
    expect(
      SmsCodeExtractor.extract('[TikTok] 4821 is your verification code'),
      '4821',
    );
  });

  test('无关键词的账单短信不抽码', () {
    expect(SmsCodeExtractor.extract('尊敬的用户，您尾号8888的储蓄卡收入1000.00元'), isNull);
  });

  test('十一位手机号不会被当成码', () {
    expect(SmsCodeExtractor.extract('验证码 84921，请联系 13800138000'), '84921');
  });

  test('字母数字混合码', () {
    expect(SmsCodeExtractor.extract('【OneIMS】登录验证码58C2A9，10分钟内输入。'), '58C2A9');
  });

  test('有关键词但没有候选返回空', () {
    expect(SmsCodeExtractor.extract('请输入验证码完成操作'), isNull);
  });

  test('日期时间片段不当候选', () {
    expect(
      SmsCodeExtractor.extract('2026-08-12 14:30 您的验证码为 662200'),
      '662200',
    );
  });

  test('英文整词匹配 shipping 不触发 pin', () {
    expect(
      SmsCodeExtractor.extract('Your package 78901 is shipping today'),
      isNull,
    );
  });

  test('OTP 整词命中', () {
    expect(SmsCodeExtractor.extract('Your OTP is 4455'), '4455');
  });

  test('品牌签名里的数字不取', () {
    expect(SmsCodeExtractor.extract('【10086】您的验证码 667788，请勿告知他人。'), '667788');
  });

  test('距离打平时偏向关键词之后', () {
    expect(SmsCodeExtractor.extract('123456 验证码 654321'), '654321');
  });

  test('空正文返回空', () {
    expect(SmsCodeExtractor.extract('  '), isNull);
  });
}
