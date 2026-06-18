import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/timer_provider.dart';
import '../../providers/database_provider.dart';
import '../../sync/sync_provider.dart';
import '../../sync/client/sync_service.dart' show SyncStatus;
import '../../widgets/timer_session_dialogs.dart';
import '../../widgets/quick_assign_sheet.dart';

class FocusScreen extends ConsumerWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final timer = ref.watch(timerProvider);
    final ownOnly = ref.watch(ownTasksOnlyProvider);
    final techName = settings?.technicianName ?? '';
    final syncStatus = ref.watch(syncStatusProvider);
    final cs = Theme.of(context).colorScheme;

    final isClient = settings?.syncRole == 'CLIENT' &&
        (settings?.syncServerHost.isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktuell'),
        actions: [
          IconButton(
            icon: Icon(ownOnly ? Icons.person : Icons.people_outline),
            tooltip: ownOnly ? 'Meine Tasks (Alle anzeigen)' : 'Alle Tasks (Filtern)',
            onPressed: () =>
                ref.read(ownTasksOnlyProvider.notifier).state = !ownOnly,
          ),
        ],
      ),
      body: Column(
        children: [
          // Sync status chip for CLIENT mode
          if (isClient) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: cs.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    syncStatus.status == SyncStatus.syncing
                        ? Icons.sync
                        : syncStatus.status == SyncStatus.error
                            ? Icons.cloud_off_outlined
                            : Icons.cloud_done_outlined,
                    size: 16,
                    color: syncStatus.status == SyncStatus.error
                        ? cs.error
                        : cs.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    syncStatus.status == SyncStatus.syncing
                        ? 'Synchronisiere…'
                        : syncStatus.lastSyncAt != null
                            ? 'Sync: ${DateFormat('HH:mm').format(syncStatus.lastSyncAt!)}'
                            : 'Verbunden',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: syncStatus.status == SyncStatus.syncing
                        ? null
                        : () => triggerManualSync(ref),
                    icon: const Icon(Icons.sync, size: 14),
                    label: const Text('Sync'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (tasks) {
                final today = DateTime.now();
                final tech = techName.isEmpty ? null : techName;
                final visibleTasks = filterByTechnician(tasks, tech, ownOnly: ownOnly);

                bool hasTimer(String id) => timer[id] != null;
                int focusRank(TaskWithDetails t) {
                  final st = timer[t.task.id]?.status;
                  if (st == TimerStatus.running) return 0;
                  if (st == TimerStatus.paused) return 1;
                  return 2;
                }

                int pRank(String p) => switch (p) {
                      'CRITICAL' => 3,
                      'HIGH' => 2,
                      'NORMAL' => 1,
                      _ => 0,
                    };

                int sortByPriorityThenDate(TaskWithDetails a, TaskWithDetails b) {
                  final p = pRank(b.task.priority).compareTo(pRank(a.task.priority));
                  if (p != 0) return p;
                  final aDate = a.task.plannedDate ?? a.task.createdAt;
                  final bDate = b.task.plannedDate ?? b.task.createdAt;
                  return aDate.compareTo(bDate);
                }

                final focusTasks = visibleTasks
                    .where((t) => isFocusTask(t.task,
                        hasActiveTimer: hasTimer(t.task.id), now: today))
                    .toList()
                  ..sort((a, b) {
                    final r = focusRank(a).compareTo(focusRank(b));
                    if (r != 0) return r;
                    return sortByPriorityThenDate(a, b);
                  });

                if (focusTasks.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_off_outlined,
                              size: 64, color: cs.outlineVariant),
                          const SizedBox(height: 16),
                          Text(
                            'Keine Tasks im Blick',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Starte einen Timer oder plane einen Task für heute.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: cs.outline),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () async {
                              await context.push('/tasks/new');
                              ref.invalidate(tasksProvider);
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Neuer Task'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(tasksProvider),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: focusTasks.length,
                        itemBuilder: (context, index) {
                          final t = focusTasks[index];
                          final entry = timer[t.task.id];
                          final isRunning = entry?.status == TimerStatus.running;
                          final isPaused = entry?.status == TimerStatus.paused;
                          return _FocusTaskRow(
                            task: t,
                            elapsed: entry?.timeString,
                            isTimerRunning: isRunning,
                            isTimerPaused: isPaused,
                            today: today,
                            onTap: () => context.push('/tasks/${t.task.id}'),
                            onTimerStart: entry == null
                                ? () async {
                                    await ref
                                        .read(timerProvider.notifier)
                                        .start(t.task.id);
                                    ref.invalidate(tasksProvider);
                                  }
                                : null,
                            onTimerPause: isRunning
                                ? () => ref
                                    .read(timerProvider.notifier)
                                    .pause(t.task.id)
                                : null,
                            onTimerResume: isPaused
                                ? () => ref
                                    .read(timerProvider.notifier)
                                    .resume(t.task.id)
                                : null,
                            onTimerStop: (isRunning || isPaused)
                                ? () =>
                                    handleTimerStop(context, ref, t.task.id)
                                : null,
                            onHide: entry == null
                                ? () async {
                                    await hideFromDashboard(
                                        ref.read(databaseProvider), t.task.id);
                                    ref.invalidate(tasksProvider);
                                  }
                                : null,
                            onComplete: entry == null
                                ? () async {
                                    await markTaskDone(
                                        ref.read(databaseProvider), t.task.id);
                                    ref.invalidate(tasksProvider);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('„${t.task.title}" erledigt'),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  }
                                : null,
                            onAssign: () =>
                                showQuickAssignSheet(context, ref, t.task.id),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await context.push('/tasks/new');
          ref.invalidate(tasksProvider);
        },
        tooltip: 'Neuer Task',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─── Focus Task Row ───────────────────────────────────────────────────────────

class _FocusTaskRow extends StatelessWidget {
  final TaskWithDetails task;
  final String? elapsed;
  final bool isTimerRunning;
  final bool isTimerPaused;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback? onTimerStart;
  final VoidCallback? onTimerPause;
  final VoidCallback? onTimerResume;
  final VoidCallback? onTimerStop;
  final VoidCallback? onHide;
  final VoidCallback? onComplete;
  final VoidCallback? onAssign;

  const _FocusTaskRow({
    required this.task,
    required this.elapsed,
    required this.isTimerRunning,
    required this.isTimerPaused,
    required this.today,
    required this.onTap,
    this.onTimerStart,
    this.onTimerPause,
    this.onTimerResume,
    this.onTimerStop,
    this.onHide,
    this.onComplete,
    this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = isTimerRunning || isTimerPaused;
    final priorityColor = switch (task.task.priority) {
      'CRITICAL' => Colors.red,
      'HIGH' => Colors.orange,
      'LOW' => Colors.blueGrey.shade300,
      _ => Colors.transparent,
    };

    final pd = task.task.plannedDate;
    final plannedToday = pd != null &&
        pd.year == today.year &&
        pd.month == today.month &&
        pd.day == today.day;

    final timeText = elapsed ??
        (plannedToday
            ? 'Heute ${pd.hour.toString().padLeft(2, '0')}:${pd.minute.toString().padLeft(2, '0')}'
            : null);
    final customerName = task.customer?.name;

    final leadingIcon = isTimerRunning
        ? Icon(Icons.timer, color: cs.primary)
        : isTimerPaused
            ? Icon(Icons.pause_circle_outline, color: cs.primary)
            : Icon(Icons.radio_button_unchecked, color: cs.outline);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (task.task.priority != 'NORMAL')
              Container(width: 4, color: priorityColor),
            Expanded(
              child: ListTile(
                onTap: onTap,
                leading: leadingIcon,
                title: Text(task.task.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: (timeText == null && customerName == null)
                    ? null
                    : Row(
                        children: [
                          if (timeText != null)
                            Text(
                              timeText,
                              style: TextStyle(
                                color: isTimerRunning ? cs.primary : cs.outline,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (timeText != null && customerName != null)
                            Text('  ·  ', style: TextStyle(color: cs.outline)),
                          if (customerName != null)
                            Expanded(
                              child: Text(
                                customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.outline),
                              ),
                            ),
                        ],
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onAssign != null) ...[
                      GestureDetector(
                        onTap: onAssign,
                        child: Tooltip(
                          message: 'Kunde / Titel zuordnen',
                          child: Icon(Icons.sell_outlined,
                              color: cs.outline, size: 22),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    GestureDetector(
                      onTap: isTimerRunning
                          ? onTimerPause
                          : isTimerPaused
                              ? onTimerResume
                              : onTimerStart,
                      child: Icon(
                        isTimerRunning
                            ? Icons.pause_circle
                            : isTimerPaused
                                ? Icons.play_circle
                                : Icons.play_circle_outline,
                        color: isActive ? cs.primary : cs.outline,
                        size: 30,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onTimerStop,
                        child: Icon(Icons.stop_circle_outlined,
                            color: cs.error, size: 28),
                      ),
                    ] else ...[
                      if (onComplete != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: onComplete,
                          child: Tooltip(
                            message: 'Als erledigt markieren',
                            child: Icon(Icons.check_circle_outline,
                                color: Colors.green.shade600, size: 26),
                          ),
                        ),
                      ],
                      if (onHide != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: onHide,
                          child: Tooltip(
                            message: 'Aus „Im Blick" ausblenden',
                            child: Icon(Icons.visibility_off_outlined,
                                color: cs.outline, size: 24),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
