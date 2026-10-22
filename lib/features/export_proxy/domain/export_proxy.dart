final class ExportProxyConfig {
  const ExportProxyConfig({
    required this.id,
    required this.name,
    required this.mode,
    required this.listenHost,
    required this.listenPort,
    required this.enabled,
    this.deviceId = '',
    this.running = false,
  });

  final String id;
  final String name;
  final String mode;
  final String listenHost;
  final int listenPort;
  final bool enabled;
  final String deviceId;
  final bool running;
}
