import 'package:flutter/material.dart';

import 'glass_dock.dart';

export 'glass_dock.dart' show OneDockDestination;

/// 各平台都用原来的玻璃底栏。系统 UITabBar 和页面比例不匹配。
final class AdaptiveGlassDock extends StatelessWidget {
  const AdaptiveGlassDock({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final List<OneDockDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return GlassDock(
      destinations: destinations,
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
    );
  }
}