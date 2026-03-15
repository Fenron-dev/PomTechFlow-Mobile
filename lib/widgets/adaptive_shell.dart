import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdaptiveShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AdaptiveShell({super.key, required this.shell});

  static const _destinations = [
    (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.checklist_outlined, selected: Icons.checklist, label: 'Tasks'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Einstellungen'),
    (icon: Icons.search_outlined, selected: Icons.search, label: 'Suche'),
  ];

  void _onDestination(BuildContext context, int i) {
    if (i == 3) {
      context.push('/search');
    } else {
      shell.goBranch(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 840;
    final isWide = width >= 1200;

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: isWide,
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (i) => _onDestination(context, i),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: isWide
                    ? Row(children: [
                        const Icon(Icons.timer, size: 28),
                        const SizedBox(width: 10),
                        Text('PomTechFlow',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ])
                    : const Icon(Icons.timer, size: 28),
              ),
              destinations: _destinations
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selected),
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }

    // Mobile: Bottom Navigation
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => _onDestination(context, i),
        destinations: _destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}
