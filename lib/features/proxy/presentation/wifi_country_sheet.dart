import 'package:flutter/material.dart';

import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../../design/widgets/system_controls.dart';
import '../domain/wifi_call_group.dart';
import '../state/proxy_controller.dart';
import 'widgets/wifi_call_country_card.dart';
import 'wifi_node_sheet.dart';

Future<void> showWifiCountrySheet({
  required BuildContext context,
  required ProxyController controller,
  required List<WifiCallGroup> groups,
  ValueChanged<WifiCallGroup>? onPick,
}) {
  return showOneGlassPopup<void>(
    context: context,
    builder: (context) => WifiCountrySheet(
      controller: controller,
      groups: groups,
      onPick: onPick,
    ),
  );
}

final class WifiCountrySheet extends StatelessWidget {
  const WifiCountrySheet({
    required this.controller,
    required this.groups,
    this.onPick,
    super.key,
  });

  static const Key rootKey = Key('proxy-country-sheet');

  final ProxyController controller;
  final List<WifiCallGroup> groups;
  final ValueChanged<WifiCallGroup>? onPick;

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
                    onPick == null ? '更多国家' : '加到一级菜单',
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
              onPick == null
                  ? '香港 / 美国 / 英国 / 德国 / 新西兰以外的 XX-WIFI 组。'
                  : '点一个国家，把它放到一级菜单。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: OneSpacing.item),
            Expanded(
              child: groups.isEmpty
                  ? const Center(child: Text('没有更多国家。'))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: OneSpacing.item,
                            crossAxisSpacing: OneSpacing.item,
                            mainAxisExtent: WifiCallCountryCard.extent,
                          ),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return WifiCallCountryCard(
                          key: ValueKey<String>(
                            'proxy-more-country-${group.groupName}',
                          ),
                          group: group,
                          onTap: () {
                            final pick = onPick;
                            if (pick != null) {
                              pick(group);
                              Navigator.of(context).pop();
                              return;
                            }
                            showWifiNodeSheet(
                              context: context,
                              controller: controller,
                              groupName: group.groupName,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
