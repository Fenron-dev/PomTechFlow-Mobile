import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
import 'screens/focus/focus_screen.dart';
import 'screens/notes/notes_screen.dart';
import 'services/notification_service.dart';
import 'services/badge_service.dart';
import 'providers/tasks_provider.dart';
import 'widgets/adaptive_shell.dart';
import 'widgets/keyboard_shortcuts.dart';
import 'services/auto_backup_service.dart';
import 'services/app_lock_service.dart';
import 'services/widget_service.dart';
import 'providers/database_provider.dart';
import 'providers/timer_provider.dart';
import 'screens/app_lock_screen.dart';
import 'screens/tools/network_tools_screen.dart';
import 'screens/knowledge/knowledge_screen.dart';
import 'screens/calendar/calendar_screen.dart';
import 'services/device_maintenance_service.dart';
import 'sync/sync_provider.dart';
import 'sync/client/sync_scheduler.dart';
import 'sync/ui/conflict_resolution_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE', null);
  await NotificationService.initialize();
  await WidgetService.init();
  runApp(const ProviderScope(child: PomTechFlowApp()));
}

final _router = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    GoRoute(
      path: '/search',
      builder: (_, _) => const SearchScreen(),
    ),
    GoRoute(
      path: '/statistics',
      builder: (_, _) => const StatisticsScreen(),
    ),
    GoRoute(
      path: '/reports',
      builder: (_, _) => const AllReportsScreen(),
    ),
    GoRoute(
      path: '/reports/monthly',
      builder: (_, _) => const MonthlyReportScreen(),
    ),
    GoRoute(
      path: '/tools/network',
      builder: (_, _) => const NetworkToolsScreen(),
    ),
    GoRoute(
      path: '/knowledge',
      builder: (_, _) => const KnowledgeScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => const SettingsScreen(),
      routes: [
        GoRoute(
          path: 'customers',
          builder: (_, _) => const CustomersScreen(),
        ),
        GoRoute(
          path: 'workflows',
          builder: (_, _) => const WorkflowsScreen(),
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
              builder: (_, _) => const DashboardScreen()),
        ]),
        // 1 - Aktuell (Focus/Im Blick)
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/focus',
              builder: (_, _) => const FocusScreen()),
        ]),
        // 2 - Tasks
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/tasks',
            builder: (_, _) => const TaskListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) => const TaskFormScreen(),
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
        // 3 - Notizen
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/notes',
            builder: (_, _) => const NotesScreen(),
          ),
        ]),
        // 4 - Kalender
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/calendar',
            builder: (_, _) => const CalendarScreen(),
          ),
        ]),
      ],
    ),
  ],
);

class PomTechFlowApp extends ConsumerStatefulWidget {
  const PomTechFlowApp({super.key});

  @override
  ConsumerState<PomTechFlowApp> createState() => _PomTechFlowAppState();
}

class _PomTechFlowAppState extends ConsumerState<PomTechFlowApp> {
  SyncScheduler? _syncScheduler;
  final _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;

  @override
  void dispose() {
    _syncScheduler?.dispose();
    _batterySubscription?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _updateWakelock(bool keepAwake, bool chargingOnly) async {
    _batterySubscription?.cancel();
    _batterySubscription = null;

    if (!keepAwake) {
      await WakelockPlus.disable();
      return;
    }

    if (!chargingOnly) {
      await WakelockPlus.enable();
      return;
    }

    // Nur beim Laden: aktuellen Zustand prüfen und auf Änderungen reagieren
    void apply(BatteryState state) {
      final isCharging =
          state == BatteryState.charging || state == BatteryState.full;
      isCharging ? WakelockPlus.enable() : WakelockPlus.disable();
    }

    apply(await _battery.batteryState);
    _batterySubscription = _battery.onBatteryStateChanged.listen(apply);
  }

  @override
  Widget build(BuildContext context) {
    // App-Icon Badge: offene Tasks
    ref.listen(openTasksCountProvider, (_, count) {
      BadgeService.update(count.valueOrNull ?? 0);
    });

    // Homescreen-Widget: aktualisieren bei Timer-Änderungen
    ref.listen(timerProvider, (_, timers) {
      final tasks = ref.read(tasksProvider).valueOrNull ?? [];
      final openCount = ref.read(openTasksCountProvider).valueOrNull ?? 0;

      final running = timers.entries
          .where((e) => e.value.status == TimerStatus.running)
          .firstOrNull;
      final active = running ??
          timers.entries
              .where((e) => e.value.status == TimerStatus.paused)
              .firstOrNull;

      if (active == null) {
        WidgetService.update(
          timerStatus: 'idle',
          elapsedSecs: 0,
          taskName: '',
          openTasks: openCount,
        );
      } else {
        final task = tasks.firstWhere(
          (t) => t.task.id == active.key,
          orElse: () => tasks.first,
        );
        final isRunning = active.value.status == TimerStatus.running;
        WidgetService.update(
          timerStatus: isRunning ? 'running' : 'paused',
          elapsedSecs: active.value.elapsedSeconds,
          taskName: task.task.title,
          openTasks: openCount,
          startTime: isRunning
              ? DateTime.now().subtract(Duration(seconds: active.value.elapsedSeconds))
              : null,
        );
      }
    });

    // Auto-Backup und Sync-Init: einmalig beim ersten Build nach App-Start
    ref.listen(settingsProvider, (prev, next) {
      if (next.hasValue) {
        final s = next.value!;
        _updateWakelock(s.keepScreenAwake, s.keepScreenAwakeChargingOnly);
      }

      if (prev == null && next.hasValue) {
        final settings = next.value!;
        final db = ref.read(databaseProvider);
        final notifier = ref.read(settingsProvider.notifier);
        AutoBackupService.checkAndRun(db, settings, notifier);
        ref.read(timerProvider.notifier).restoreFromDatabase();
        DeviceMaintenanceService.checkAndCreateTasks(db);

        // Sync-Scheduler starten (Client-Mode)
        _syncScheduler?.dispose();
        _syncScheduler = SyncScheduler(
          db: db,
          settings: settings,
          onResult: (result) => ref.read(syncStatusProvider.notifier).onResult(result),
          onHostRefreshed: (newHost) {
            // Persist the refreshed IP from mDNS discovery
            final current = ref.read(settingsProvider).valueOrNull;
            if (current != null && current.syncServerHost != newHost) {
              ref.read(settingsProvider.notifier).save(
                    current.copyWith(syncServerHost: newHost),
                  );
            }
          },
        );
        _syncScheduler!.start();

        // Server starten falls konfiguriert
        if (settings.syncRole == 'SERVER') {
          ref.read(syncServerProvider).start(
            db: db,
            serverDeviceId: settings.deviceId,
            serverName: settings.effectiveDeviceName,
            syncAppSettings: settings.syncAppSettings,
          );
        }
      }

      // Settings-Änderung → Scheduler aktualisieren
      if (prev != null && next.hasValue) {
        _syncScheduler?.onSettingsChanged(next.value!);
      }
    });

    // Conflicts nach Sync anzeigen
    ref.listen(syncStatusProvider, (prev, next) {
      if (next.pendingConflicts.isNotEmpty && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog<void>(
            context: context,
            builder: (_) => ConflictResolutionDialog(
              conflicts: next.pendingConflicts,
              onDismiss: () {
                Navigator.of(context).pop();
                ref.read(syncStatusProvider.notifier).clearConflicts();
              },
            ),
          );
        });
      }
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
      builder: (context, child) => AppLockWrapper(
        child: KeyboardShortcutsWrapper(child: child ?? const SizedBox()),
      ),
    );
  }
}

// ── App-Lock wrapper ─────────────────────────────────────────────────────────

class AppLockWrapper extends StatefulWidget {
  final Widget child;
  const AppLockWrapper({super.key, required this.child});

  @override
  State<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends State<AppLockWrapper>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    final setup = await AppLockService.isSetup();
    if (mounted) setState(() { _locked = setup; _checking = false; });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Re-lock when app moves to background
      AppLockService.isSetup().then((setup) {
        if (setup && mounted) setState(() => _locked = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_locked) {
      return AppLockScreen(onUnlocked: () => setState(() => _locked = false));
    }
    return widget.child;
  }
}
