import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/system_controls.dart';
import '../../domain/wifi_call_connection.dart';
import '../../domain/wifi_connection_catalog.dart';
import '../../domain/wifi_selector_catalog.dart';

final class WifiCallConnectionHeader extends StatelessWidget {
  const WifiCallConnectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Row(
      children: <Widget>[
        Expanded(flex: 5, child: Text('主机', style: style)),
        Expanded(flex: 6, child: Text('节点', style: style)),
        SizedBox(
          width: 52,
          child: Text('下载', style: style, textAlign: TextAlign.right),
        ),
        SizedBox(
          width: 52,
          child: Text('上传', style: style, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

final class WifiCallConnectionRow extends StatelessWidget {
  const WifiCallConnectionRow({required this.connection, super.key});

  final WifiCallConnection connection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final chainColor = connection.direct
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    final flag = connection.countryCode == null
        ? ''
        : WifiSelectorCatalog.flagEmoji(connection.countryCode!);
    final chain = WifiConnectionCatalog.compactChain(connection.chainLabel);
    final host = WifiConnectionCatalog.compactHost(connection.host);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OneSpacing.micro),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Text(
              host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Row(
              children: <Widget>[
                SystemIcon(
                  connection.direct ? Icons.adjust : Icons.alt_route,
                  size: 14,
                  color: chainColor,
                ),
                const SizedBox(width: OneSpacing.nano),
                Expanded(
                  child: Text(
                    flag.isEmpty ? chain : '$flag $chain',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: chainColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              WifiConnectionCatalog.formatRate(connection.downloadBps),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              WifiConnectionCatalog.formatRate(connection.uploadBps),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
