/// 面向展示的本地时间文本。所有页面共用这一份，避免各自手写补零逻辑后口径漂移。
///
/// 只负责「有值时怎么显示」；值为空时的回退文案（`'—'`、`'时间不可用'`…）
/// 由调用方按自己页面的语气决定。
library;

String _two(int value) => value.toString().padLeft(2, '0');

/// `yyyy-MM-dd HH:mm`，按本机时区显示。
String formatLocalMinute(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// `yyyy-MM-dd HH:mm:ss`，按本机时区显示。
String formatLocalSecond(DateTime value) {
  final local = value.toLocal();
  return '${formatLocalMinute(value)}:${_two(local.second)}';
}
