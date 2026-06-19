import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:go_router/go_router.dart';
import 'keyboard_shortcuts.dart';

class AdaptiveShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AdaptiveShell({super.key, required this.shell});

  static const _destinations = [
    (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.visibility_outlined, selected: Icons.visibility, label: 'Aktuell'),
    (icon: Icons.checklist_outlined, selected: Icons.checklist, label: 'Tasks'),
    (icon: Icons.note_outlined, selected: Icons.note, label: 'Notizen'),
    (icon: Icons.calendar_today_outlined, selected: Icons.calendar_today, label: 'Kalender'),
  ];

  void _onDestination(BuildContext context, int i) {
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
            Expanded(
              child: Row(
                children: [
                  _DesktopSidebar(
                    shell: shell,
                    destinations: _destinations,
                    isWide: isWide,
                    onBranch: (i) => _onDestination(context, i),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(child: shell),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile / Tablet: Bottom Navigation
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

// ─── Desktop Sidebar ──────────────────────────────────────────────────────────

class _DesktopSidebar extends StatelessWidget {
  final StatefulNavigationShell shell;
  final List<({IconData icon, IconData selected, String label})> destinations;
  final bool isWide;
  final void Function(int) onBranch;

  const _DesktopSidebar({
    required this.shell,
    required this.destinations,
    required this.isWide,
    required this.onBranch,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: isWide ? 204 : 72,
      child: Column(
        children: [
          // ── Logo ──────────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
                vertical: 18, horizontal: isWide ? 16 : 0),
            child: isWide
                ? Row(children: [
                    Icon(Icons.timer, size: 28, color: cs.primary),
                    const SizedBox(width: 10),
                    Text('PomTechFlow',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: cs.onSurface)),
                  ])
                : Icon(Icons.timer, size: 28, color: cs.primary),
          ),

          // ── Haupt-Navigation (Shell-Branches) ─────────────────────────────
          for (int i = 0; i < destinations.length; i++)
            _SidebarItem(
              icon: destinations[i].icon,
              activeIcon: destinations[i].selected,
              label: destinations[i].label,
              selected: shell.currentIndex == i,
              extended: isWide,
              onTap: () => onBranch(i),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Divider(height: 1, color: cs.outlineVariant),
          ),

          // ── Extra-Links ───────────────────────────────────────────────────
          _SidebarItem(
            icon: Icons.business_outlined,
            activeIcon: Icons.business,
            label: 'Kunden',
            selected: shell.currentIndex == 5,
            extended: isWide,
            onTap: () => onBranch(5),
          ),
          _SidebarItem(
            icon: Icons.devices_outlined,
            activeIcon: Icons.devices,
            label: 'Gerätebibliothek',
            selected: shell.currentIndex == 6,
            extended: isWide,
            onTap: () => onBranch(6),
          ),
          _SidebarItem(
            icon: Icons.lightbulb_outline,
            activeIcon: Icons.lightbulb,
            label: 'Wissensdatenbank',
            selected: shell.currentIndex == 7,
            extended: isWide,
            onTap: () => onBranch(7),
          ),
          _SidebarItem(
            icon: Icons.bar_chart_outlined,
            activeIcon: Icons.bar_chart,
            label: 'Statistiken',
            selected: shell.currentIndex == 8,
            extended: isWide,
            onTap: () => onBranch(8),
          ),
          _SidebarItem(
            icon: Icons.picture_as_pdf_outlined,
            activeIcon: Icons.picture_as_pdf,
            label: 'Alle Berichte',
            selected: shell.currentIndex == 9,
            extended: isWide,
            onTap: () => onBranch(9),
          ),

          const Spacer(),

          // ── Einstellungen unten ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Divider(height: 1, color: cs.outlineVariant),
          ),
          _SidebarItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings,
            label: 'Einstellungen',
            selected: shell.currentIndex == 10,
            extended: isWide,
            onTap: () => onBranch(10),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconWidget = Icon(
      selected ? activeIcon : icon,
      size: 22,
      color: selected ? cs.primary : cs.onSurfaceVariant,
    );
    final bg = selected
        ? cs.primaryContainer.withValues(alpha: 0.6)
        : Colors.transparent;

    if (!extended) {
      return Tooltip(
        message: label,
        preferBelow: false,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 56,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: iconWidget),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
                shortcut: sc(LogicalKeyboardKey.keyN),
                onPressed: () => context.push('/tasks/new'),
                child: const Text('Neuer Task'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.timer_outlined, size: 16),
                shortcut: sc(LogicalKeyboardKey.keyT),
                onPressed: () {},
                child: const Text('Task-Timer starten/pausieren'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.av_timer_outlined, size: 16),
                shortcut: const SingleActivator(
                    LogicalKeyboardKey.space, control: true, shift: true),
                onPressed: () {},
                child: const Text('Stoppuhr Start/Pause'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.stop_outlined, size: 16),
                shortcut: const SingleActivator(
                    LogicalKeyboardKey.enter, control: true, shift: true),
                onPressed: () {},
                child: const Text('Stoppuhr Stopp'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.bar_chart_outlined, size: 16),
                onPressed: () => context.push('/statistics'),
                child: const Text('Statistiken'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
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
                shortcut: scCtrl(LogicalKeyboardKey.digit1),
                onPressed: () => shell.goBranch(0),
                child: const Text('Dashboard'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.visibility_outlined, size: 16),
                shortcut: scCtrl(LogicalKeyboardKey.digit2),
                onPressed: () => shell.goBranch(1),
                child: const Text('Aktuell'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.checklist_outlined, size: 16),
                shortcut: scCtrl(LogicalKeyboardKey.digit3),
                onPressed: () => shell.goBranch(2),
                child: const Text('Tasks'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.note_outlined, size: 16),
                shortcut: scCtrl(LogicalKeyboardKey.digit4),
                onPressed: () => shell.goBranch(3),
                child: const Text('Notizen'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.calendar_today_outlined, size: 16),
                shortcut: scCtrl(LogicalKeyboardKey.digit5),
                onPressed: () => shell.goBranch(4),
                child: const Text('Kalender'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.search, size: 16),
                shortcut: sc(LogicalKeyboardKey.keyF),
                onPressed: () => context.push('/search'),
                child: const Text('Suche'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.settings_outlined, size: 16),
                shortcut: sc(LogicalKeyboardKey.comma),
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
