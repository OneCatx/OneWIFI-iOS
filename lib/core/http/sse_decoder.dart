final class SseEvent {
  const SseEvent({this.name = 'message', required this.data});

  final String name;
  final String data;
}

/// Incremental Server-Sent Events decoder. Comment frames (`: keepalive`)
/// are dropped. `data:` lines in one block are joined with a newline.
///
/// Line terminators follow WHATWG HTML §9.2.6: CRLF, LF, or CR. A CR at the
/// end of a chunk is held until the next chunk so a split CRLF is not two
/// terminators.
final class SseDecoder {
  final StringBuffer _pending = StringBuffer();
  bool _bomChecked = false;

  List<SseEvent> add(String chunk) {
    _pending.write(chunk);
    return _drain(flush: false);
  }

  List<SseEvent> flush() => _drain(flush: true);

  List<SseEvent> _drain({required bool flush}) {
    var raw = _pending.toString();
    if (!_bomChecked) {
      _bomChecked = true;
      if (raw.startsWith('\uFEFF')) raw = raw.substring(1);
    }
    final (normalized, held) = _normalizeNewlines(raw, flush: flush);
    var text = normalized;
    var carry = held;
    if (carry == '\r' && text.endsWith('\n')) {
      text = '$text\n';
      carry = '';
    }
    final events = <SseEvent>[];
    while (true) {
      final index = text.indexOf('\n\n');
      if (index < 0) break;
      final parsed = _parseBlock(text.substring(0, index));
      if (parsed != null) events.add(parsed);
      text = text.substring(index + 2);
    }
    _pending
      ..clear()
      ..write(text)
      ..write(carry);
    if (flush && text.isNotEmpty) {
      final parsed = _parseBlock(text);
      if (parsed != null) events.add(parsed);
      _pending.clear();
    }
    return events;
  }

  static (String, String) _normalizeNewlines(
    String input, {
    required bool flush,
  }) {
    final out = StringBuffer();
    var i = 0;
    while (i < input.length) {
      final code = input.codeUnitAt(i);
      if (code == 0x0D) {
        if (i + 1 < input.length) {
          if (input.codeUnitAt(i + 1) == 0x0A) i += 1;
          out.writeCharCode(0x0A);
        } else if (flush) {
          out.writeCharCode(0x0A);
        } else {
          return (out.toString(), input.substring(i));
        }
      } else {
        out.writeCharCode(code);
      }
      i += 1;
    }
    return (out.toString(), '');
  }

  static SseEvent? _parseBlock(String block) {
    var name = 'message';
    final dataLines = <String>[];
    for (final line in block.split('\n')) {
      if (line.isEmpty || line.startsWith(':')) continue;
      if (line.startsWith('event:')) {
        final value = _fieldValue(line, 'event:');
        if (value.isNotEmpty) name = value;
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(_fieldValue(line, 'data:'));
      }
    }
    if (dataLines.isEmpty) return null;
    return SseEvent(name: name, data: dataLines.join('\n'));
  }

  static String _fieldValue(String line, String prefix) {
    var value = line.substring(prefix.length);
    if (value.startsWith(' ')) value = value.substring(1);
    return value;
  }
}
