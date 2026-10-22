import 'package:flutter/material.dart';

import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../../design/widgets/system_controls.dart';
import '../domain/wifi_call_connection.dart';
import 'widgets/wifi_call_connection_row.dart';

Future<void> showWifiConnectionSheet({
  required BuildContext context,
  required List<WifiCallConnection> connections,
}) {
  return showOneGlassPopup<void>(
    context: context,
    builder: (context) => WifiConnectionSheet(connections: connections),
  );
}

final class WifiConnectionSheet extends StatelessWidget {
  const WifiConnectionSheet({required this.connections, super.key});

  static const Key rootKey = Key('proxy-connection-sheet');

  final List<WifiCallConnection> connections;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: rootKey,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          OneInsets.scroll(context).left,
          OneSpacing.medium,
          OneInsets.scroll(context).right,
          OneSpacing.medium,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '连接',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const SystemIcon(Icons.close),
                  tooltip: '关闭',
                ),
              ],
            ),
            Text(
              '只看经过 XX-WIFI 组的会话，不限国家，最多十条。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: OneSpacing.item),
            Expanded(
              child: connections.isEmpty
                  ? const Center(child: Text('当前没有经过 WIFI 组的连接。'))
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const WifiCallConnectionHeader(),
                          const SizedBox(height: OneSpacing.micro),
                          for (
                            var i = 0;
                            i < connections.length;
                            i++
                          ) ...<Widget>[
                            if (i > 0) const SizedBox(height: OneSpacing.small),
                            WifiCallConnectionRow(
                              key: ValueKey<String>(
                                'proxy-connection-sheet-${connections[i].id}',
                              ),
                              connection: connections[i],
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
