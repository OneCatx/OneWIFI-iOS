String overviewFallback(String value) => value.isEmpty ? '未上报' : value;

String overviewPercent(double value) => '${value.toStringAsFixed(1)}%';

String overviewBytes(int value) {
  const divisor = 1024 * 1024 * 1024;
  return '${(value / divisor).toStringAsFixed(1)} GB';
}

String overviewRate(double value) {
  const divisor = 1024 * 1024;
  if (value >= divisor) return '${(value / divisor).toStringAsFixed(1)} MB/s';
  return '${(value / 1024).toStringAsFixed(1)} KB/s';
}
