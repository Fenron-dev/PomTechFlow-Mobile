import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';

class AdaptiveShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AdaptiveShell({super.key, required this.shell});

  static const _destinations = [
    (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.checklist_outlined, selected: Icons.checklist, label: 'Tasks'),
    (icon: Icons.note_outlined, selected: Icons.note, label: 'Notizen'),
  ];

  void _onDestination(BuildContext context, int i) {
    // Gleichen Tab erneut antippen → immer zur Root-Ansicht zurück
    shell.goBranch(i, initialLocation: shell.currentIndex == i);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 840;
    final isWide = width >= 1200;

    final showMenuBar = !kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    if (isDesktop) {
      return Scaffold(
        body: Column(
          children: [
            if (showMenuBar) _AppMenuBar(shell: shell),
            Expanded(child: Row(
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
        )), // Row + Expanded
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

// ─── Desktop Menu Bar ─────────────────────────────────────────────────────────

class _AppMenuBar extends StatelessWidget {
  final StatefulNavigationShell shell;
  const _AppMenuBar({required this.shell});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: MenuBar(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 8)),
        ),
        children: [
          // ── Datei ────────────────────────────────────────────────
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.add, size: 16),
                onPressed: () => context.push('/tasks/new'),
                child: const Text('Neuer Task'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.download_outlined, size: 16),
                onPressed: () => context.push('/tasks'),
                child: const Text('Task importieren (.ptf)'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.bar_chart_outlined, size: 16),
                onPressed: () => context.push('/statistics'),
                child: const Text('Statistiken'),
              ),
              MenuItemButton(
                leadingIcon:
                    const Icon(Icons.picture_as_pdf_outlined, size: 16),
                onPressed: () => context.push('/reports'),
                child: const Text('Alle Berichte'),
              ),
            ],
            child: const Text('Datei'),
          ),
          // ── Ansicht ───────────────────────────────────────────────
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.dashboard_outlined, size: 16),
                onPressed: () => shell.goBranch(0),
                child: const Text('Dashboard'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.checklist_outlined, size: 16),
                onPressed: () => shell.goBranch(1),
                child: const Text('Tasks'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.search, size: 16),
                onPressed: () => context.push('/search'),
                child: const Text('Suche'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.note_outlined, size: 16),
                onPressed: () => shell.goBranch(2),
                child: const Text('Notizen'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.settings_outlined, size: 16),
                onPressed: () => context.push('/settings'),
                child: const Text('Einstellungen'),
              ),
            ],
            child: const Text('Ansicht'),
          ),
        ],
      ),
    );
  }
}
