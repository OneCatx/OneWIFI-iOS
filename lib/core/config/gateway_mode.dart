/// Choose MDD vs legacy call/auth path at runtime.
///
/// Call [GatewayModeController.useMdd] after login when the gateway
/// advertises MDD.
library;

enum GatewayMode { legacy, mdd }

class GatewayModeController {
  GatewayModeController._();

  static GatewayMode mode = GatewayMode.legacy;
  static String origin = '';
  static String? lineId;

  static void useMdd(String base, {String? initialLine}) {
    mode = GatewayMode.mdd;
    origin = base;
    lineId = initialLine;
  }

  static void useLegacy() {
    mode = GatewayMode.legacy;
  }

  static bool get isMdd => mode == GatewayMode.mdd;
}
