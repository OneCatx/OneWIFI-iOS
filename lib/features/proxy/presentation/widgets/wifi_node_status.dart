import '../../../../design/widgets/console_layout.dart';
import '../../domain/wifi_call_group.dart';
import '../../domain/wifi_selector_catalog.dart';

String wifiNodeBadge(WifiCallNode node, {bool probing = false}) {
  if (node.delayMs > 0) return '${node.delayMs}ms';
  if (node.delayFailed || !node.alive) return '超时';
  if (!node.delayProbed) return probing ? '测速中' : '—';
  return '—';
}

bool wifiNodeShowsPlate(WifiCallNode node, {bool probing = false}) {
  if (node.delayMs > 0) return true;
  if (node.delayFailed || !node.alive) return true;
  if (probing && !node.delayProbed) return true;
  return false;
}

PlateTone wifiNodeTone(WifiCallNode node) {
  if (node.delayMs > 0) {
    if (node.delayMs < 100) return PlateTone.green;
    if (node.delayMs <= 300) return PlateTone.blue;
    return PlateTone.red;
  }
  if (node.delayFailed || !node.alive) return PlateTone.red;
  if (!node.delayProbed) return PlateTone.blue;
  return PlateTone.neutral;
}

WifiCallNode? wifiCurrentNode(WifiCallGroup group) {
  for (final node in group.nodes) {
    if (node.name == group.now) return node;
  }
  for (final node in group.nodes) {
    if (WifiSelectorCatalog.sameProxyName(node.name, group.now)) return node;
  }
  return null;
}
