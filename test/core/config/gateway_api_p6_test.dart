import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/config/gateway_api.dart';

void main() {
  test('P6 GatewayApi ledger matches WEB incremental paths', () {
    expect(GatewayApi.extensions, '/api/extensions');
    expect(GatewayApi.extensionsInstallUrl, '/api/extensions/install-url');
    expect(GatewayApi.extensionById('demo'), '/api/extensions/demo');
    expect(GatewayApi.upstreamProxies, '/api/upstream-proxies');
    expect(GatewayApi.upstreamProxy('u1'), '/api/upstream-proxies/u1');
    expect(
      GatewayApi.upstreamProxyProbeAction('u1'),
      '/api/upstream-proxies/u1/actions/probe',
    );
    expect(GatewayApi.exportProxies, '/api/export-proxies');
    expect(GatewayApi.exportProxiesStatus, '/api/export-proxies/status');
    expect(GatewayApi.exportProxy('e1'), '/api/export-proxies/e1');
    expect(GatewayApi.systemInfo, '/api/system/info');
    expect(GatewayApi.automaticTasks, '/api/automatic-tasks');
    expect(GatewayApi.logsHistory, '/api/logs/history');
  });
}
