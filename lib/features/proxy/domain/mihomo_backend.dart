/// 本机保存的 Mihomo 后端（external-controller）。
final class MihomoBackend {
  const MihomoBackend({required this.origin, this.secret = ''});

  final Uri origin;
  final String secret;
}
