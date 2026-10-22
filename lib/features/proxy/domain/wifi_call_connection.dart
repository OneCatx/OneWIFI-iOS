/// Mihomo `GET /connections` 里的一条实时连接。
final class WifiCallConnection {
  const WifiCallConnection({
    required this.id,
    required this.host,
    required this.chainLabel,
    this.countryCode,
    this.direct = false,
    this.downloadBytes = 0,
    this.uploadBytes = 0,
    this.downloadBps = 0,
    this.uploadBps = 0,
    this.liveRate = false,
  });

  final String id;
  final String host;
  final String chainLabel;
  final String? countryCode;
  final bool direct;
  final int downloadBytes;
  final int uploadBytes;
  final int downloadBps;
  final int uploadBps;
  final bool liveRate;
}
