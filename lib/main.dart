import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'theme/app_theme.dart';
import 'providers/settings_provider.dart' hide AppSettings;
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/tasks/task_list_screen.dart';
import 'screens/tasks/task_detail_screen.dart';
import 'screens/tasks/task_form_screen.dart';
import 'screens/customers/customers_screen.dart';
import 'screens/workflows/workflows_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/statistics/statistics_screen.dart';
import 'screens/reports/all_reports_screen.dart';
import 'screens/reports/monthly_report_screen.dart';
import 'screens/notes/notes_screen.dart';
import 'services/notification_service.dart';
import 'services/badge_service.dart';
import 'providers/tasks_provider.dart';
import 'widgets/adaptive_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE', null);
  await NotificationService.initialize();
  runApp(const ProviderScope(child: PomTechFlowApp()));
}

final _router = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    GoRoute(
      path: '/search',
      builder: (_, __) => const SearchScreen(),
    ),
    GoRoute(
      path: '/statistics',
      builder: (_, __) => const StatisticsScreen(),
    ),
    GoRoute(
      path: '/reports',
      builder: (_, __) => const AllReportsScreen(),
    ),
    GoRoute(
      path: '/reports/monthly',
      builder: (_, __) => const MonthlyReportScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const SettingsScreen(),
      routes: [
        GoRoute(
          path: 'customers',
          builder: (_, __) => const CustomersScreen(),
        ),
        GoRoute(
          path: 'workflows',
          builder: (_, __) => const WorkflowsScreen(),
        ),
      ],
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AdaptiveShell(shell: shell),
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
        // 2 - Notizen
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/notes',
            builder: (_, __) => const NotesScreen(),
          ),
        ]),
      ],
    ),
  ],
);

class PomTechFlowApp extends ConsumerWidget {
  const PomTechFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // App-Icon Badge: offene Tasks
    ref.listen(openTasksCountProvider, (_, count) {
      BadgeService.update(count);
    });

    final settingsAsync = ref.watch(settingsProvider);
    final themeModeSetting = settingsAsync.valueOrNull?.themeMode ?? 'system';
    final themeMode = switch (themeModeSetting) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return MaterialApp.router(
      title: 'PomTechFlow',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
