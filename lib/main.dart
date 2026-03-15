import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/tasks/task_list_screen.dart';
import 'screens/tasks/task_detail_screen.dart';
import 'screens/tasks/task_form_screen.dart';
import 'screens/customers/customers_screen.dart';
import 'screens/workflows/workflows_screen.dart';
import 'screens/settings/settings_screen.dart';

void main() {
  runApp(const ProviderScope(child: PomTechFlowApp()));
}

final _router = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        // 0 - Dashboard
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/dashboard',
              builder: (_, __) => const DashboardScreen()),
        ]),
        // 1 - Tasks
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/tasks',
            builder: (_, __) => const TaskListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const TaskFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) =>
                    TaskDetailScreen(taskId: s.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, s) =>
                        TaskFormScreen(taskId: s.pathParameters['id']),
                  ),
                ],
              ),
            ],
          ),
        ]),
        // 2 - Einstellungen (inkl. Kunden, Workflows, Backup)
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/settings',
              builder: (_, __) => const SettingsScreen()),
          GoRoute(
              path: '/customers',
              builder: (_, __) => const CustomersScreen()),
          GoRoute(
              path: '/workflows',
              builder: (_, __) => const WorkflowsScreen()),
        ]),
      ],
    ),
  ],
);

class PomTechFlowApp extends StatelessWidget {
  const PomTechFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PomTechFlow',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: shell.goBranch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Einstellungen',
          ),
        ],
      ),
    );
  }
}
