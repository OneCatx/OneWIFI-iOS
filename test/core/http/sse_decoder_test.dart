import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/http/sse_decoder.dart';

void main() {
  test('parses named progress frames and drops keepalive comments', () {
    final decoder = SseDecoder();
    final first = decoder.add(
      'event: progress\ndata: {"step":"auth","pct":10}\n\n'
      ': keepalive\n\n',
    );
    expect(first, hasLength(1));
    expect(first.single.name, 'progress');
    expect(first.single.data, '{"step":"auth","pct":10}');

    final second = decoder.add(
      'event: progress\ndata: {"step":"done","pct":100}',
    );
    expect(second, isEmpty);
    final flushed = decoder.flush();
    expect(flushed.single.data, contains('done'));
  });

  test('accepts CRLF framed blocks', () {
    final decoder = SseDecoder();
    final events = decoder.add(
      'event: progress\r\ndata: {"step":"error","msg":"no"}\r\n\r\n',
    );
    expect(events.single.name, 'progress');
    expect(events.single.data, contains('error'));
  });

  test('CRLF 被 chunk 切成 CR|LF 时仍是一个行终止符', () {
    final decoder = SseDecoder();
    final first = decoder.add('event: progress\r\ndata: {"step":1}\r');
    final second = decoder.add('\ndata: {"step":2}\r\n\r\n');
    final events = <SseEvent>[...first, ...second];
    expect(events, hasLength(1));
    expect(events.single.name, 'progress');
    expect(events.single.data, '{"step":1}\n{"step":2}');
  });

  test('单个 CR 作为行终止符与 LF 等价', () {
    final decoder = SseDecoder();
    expect(decoder.add('data: a\rdata: b\r\r').single.data, 'a\nb');
  });

  test('data 值只去掉冒号后一个前导空格，末尾空白保留', () {
    final decoder = SseDecoder();
    expect(decoder.add('data: hello world \n\n').single.data, 'hello world ');
    expect(decoder.add('data:  two\n\n').single.data, ' two');
  });

  test('流开头的一个 U+FEFF BOM 必须忽略', () {
    final decoder = SseDecoder();
    expect(decoder.add('\uFEFFdata: first\n\n').single.data, 'first');
  });
}
