import 'package:flutter/material.dart';

import '../one/ultra_glass_dock.dart' as ultra;
import 'system_controls.dart';

export '../one/ultra_glass_dock.dart'
    show kGlassDockIndicatorKey, kGlassDockRimKey, glassDockTabEdges;

final class OneDockDestination {
  const OneDockDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.key,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  /// 覆盖默认的按位置生成的测试键，给位置会随可用页签变化的项用。
  final Key? key;
}

final class GlassDock extends StatelessWidget {
  const GlassDock({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  }) : assert(destinations.length > 0),
       assert(selectedIndex >= 0),
       assert(selectedIndex < destinations.length);

  static const Key overviewTargetKey = ValueKey<String>('glass-dock-target-0');

  static Key targetKey(int index) =>
      ValueKey<String>('glass-dock-target-$index');

  final List<OneDockDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '主导航',
      child: ultra.GlassDock(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: <NavigationDestination>[
            for (var index = 0; index < destinations.length; index++)
              NavigationDestination(
                icon: SystemIcon(
                  destinations[index].icon,
                  key: destinations[index].key ?? targetKey(index),
                ),
                selectedIcon: SystemIcon(
                  destinations[index].selectedIcon ?? destinations[index].icon,
                  key: destinations[index].key ?? targetKey(index),
                ),
                label: destinations[index].label,
              ),
          ],
        ),
    );
  }
}
