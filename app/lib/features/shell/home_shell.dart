import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';

/// Bottom navigation bar on phones, side rail on tablets / landscape.
/// Also refreshes all data when the app returns from the background.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final AppLifecycleListener _lifecycle;

  static const _destinations = [
    (icon: Icons.eco_outlined, selected: Icons.eco, label: 'Plant'),
    (icon: Icons.show_chart, selected: Icons.show_chart, label: 'History'),
    (icon: Icons.notifications_outlined, selected: Icons.notifications, label: 'Events'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => refreshAll(ref));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _select(int index) => widget.shell.goBranch(
        index,
        initialLocation: index == widget.shell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final index = widget.shell.currentIndex;

    if (wide) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.85,
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selected),
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: widget.shell),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selected),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
