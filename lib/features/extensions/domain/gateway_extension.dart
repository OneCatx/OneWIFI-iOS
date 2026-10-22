final class GatewayExtension {
  const GatewayExtension({
    required this.id,
    required this.name,
    required this.enabled,
    this.version = '',
    this.description = '',
  });

  final String id;
  final String name;
  final bool enabled;
  final String version;
  final String description;
}
