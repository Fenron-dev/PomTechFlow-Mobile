import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/timer_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final timer = ref.watch(timerProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(settings?.companyName ?? 'PomTechFlow'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Statistiken',
            onPressed: () => context.push('/statistics'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Neuer Task',
            onPressed: () async {
              await context.push('/tasks/new');
              ref.invalidate(tasksProvider);
            },
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tasks) {
          final active = tasks.where((t) => t.task.status == 'ACTIVE').toList();
          final completed = tasks.where((t) => t.task.status == 'COMPLETED').length;
          final planned = tasks.where((t) => t.task.status == 'PLANNED').length;
          final today = DateTime.now();
          final todayTasks = tasks.where((t) {
            final d = t.task.plannedDate;
            if (d == null) return false;
            return d.year == today.year &&
                d.month == today.month &&
                d.day == today.day;
          }).toList()
            ..sort((a, b) => a.task.plannedDate!.compareTo(b.task.plannedDate!));
          final totalMinutes = tasks.fold<int>(0, (s, t) => s + t.task.totalMinutes);
          final aeMin = settings?.aeMinutes ?? 10;
          // Summe der aufgerundeten AE pro Task
          final totalAE = tasks.fold<int>(0, (s, t) => s + t.aeCount(aeMin));

          // Task mit laufendem Timer
          final activeTimerTask = timer.activeTaskId != null
              ? tasks.where((t) => t.task.id == timer.activeTaskId).firstOrNull
              : null;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tasksProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Aktiver Timer Banner
                if (timer.status != TimerStatus.idle) ...[
                  _TimerBanner(
                    timer: timer,
                    taskTitle: activeTimerTask?.task.title,
                    onTap: () => context.go('/timer'),
                  ),
                  const SizedBox(height: 16),
                ],

                // Stats
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    _StatCard(
                      label: 'Gesamt AE',
                      value: totalAE.toString(),
                      sub: '$totalMinutes Min',
                      icon: Icons.timer_outlined,
                      color: cs.primaryContainer,
                    ),
                    _StatCard(
                      label: 'Aktive Tasks',
                      value: active.length.toString(),
                      sub: '$planned geplant',
                      icon: Icons.play_circle_outline,
                      color: cs.secondaryContainer,
                    ),
                    _StatCard(
                      label: 'Abgeschlossen',
                      value: completed.toString(),
                      sub: '${tasks.length} gesamt',
                      icon: Icons.check_circle_outline,
                      color: cs.tertiaryContainer,
                    ),
                    _StatCard(
                      label: '1 AE =',
                      value: '$aeMin Min',
                      sub: 'konfigurierbar',
                      icon: Icons.settings_outlined,
                      color: cs.surfaceContainerHighest,
                      onTap: () => context.go('/settings'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Heute geplant ───────────────────────────────────────
                if (todayTasks.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Heute geplant',
                    icon: Icons.today,
                    count: todayTasks.length,
                  ),
                  const SizedBox(height: 8),
                  ...todayTasks.map((t) => _PlannedTaskRow(
                        task: t,
                        aeMin: aeMin,
                        onTap: () => context.push('/tasks/${t.task.id}'),
                      )),
                  const SizedBox(height: 16),
                ],

                // Aktive Tasks
                if (active.isNotEmpty) ...[
                  Row(
                    children: [
                      _SectionHeader(
                          title: 'Aktiv', icon: Icons.play_circle_outline, count: active.length),
                      const Spacer(),
                      TextButton(
                          onPressed: () => context.go('/tasks'),
                          child: const Text('Alle')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...active.take(3).map((t) => _TaskRow(
                        task: t,
                        isTimerRunning: timer.activeTaskId == t.task.id,
                        aeMin: aeMin,
                        onTap: () =>
                            context.push('/tasks/${t.task.id}'),
                      )),
                ],

                // Geplante Tasks
                if (planned > 0) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _SectionHeader(
                          title: 'Geplant', icon: Icons.checklist_outlined, count: planned),
                      const Spacer(),
                      TextButton(
                          onPressed: () => context.go('/tasks'),
                          child: const Text('Alle')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...tasks
                      .where((t) => t.task.status == 'PLANNED')
                      .take(3)
                      .map((t) => _TaskRow(
                            task: t,
                            isTimerRunning: false,
                            aeMin: aeMin,
                            onTap: () => context.push('/tasks/${t.task.id}'),
                          )),
                ],

                if (tasks.isEmpty) ...[
                  const SizedBox(height: 32),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.rocket_launch_outlined,
                            size: 64, color: cs.outlineVariant),
                        const SizedBox(height: 16),
                        Text('Willkommen bei PomTechFlow!',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Erstelle deinen ersten Task',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: cs.outline)),
                        const SizedBox(height: 16),
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
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Timer Banner ─────────────────────────────────────────────────────────────

class _TimerBanner extends StatelessWidget {
  final TimerState timer;
  final String? taskTitle;
  final VoidCallback onTap;

  const _TimerBanner(
      {required this.timer, required this.taskTitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRunning = timer.status == TimerStatus.running;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRunning ? cs.primaryContainer : cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(isRunning ? Icons.timer : Icons.pause_circle_outline,
                color: isRunning ? cs.primary : cs.tertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isRunning ? 'Timer läuft' : 'Timer pausiert',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  if (taskTitle != null)
                    Text(taskTitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Text(
              timer.timeString,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isRunning ? cs.primary : cs.tertiary),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  const _SectionHeader(
      {required this.title, required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
        ),
      ],
    );
  }
}

class _PlannedTaskRow extends StatelessWidget {
  final TaskWithDetails task;
  final int aeMin;
  final VoidCallback onTap;
  const _PlannedTaskRow(
      {required this.task, required this.aeMin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = task.task.plannedDate!;
    final timeStr = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(timeStr,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(task.task.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: task.customer != null ? Text(task.customer!.name) : null,
        trailing: _StatusDot(status: task.task.status),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'ACTIVE' => Colors.blue,
      'COMPLETED' => Colors.green,
      _ => Theme.of(context).colorScheme.outline,
    };
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const Spacer(),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label,
                style: Theme.of(context).textTheme.labelSmall),
            Text(sub,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final TaskWithDetails task;
  final bool isTimerRunning;
  final int aeMin;
  final VoidCallback onTap;

  const _TaskRow({
    required this.task,
    required this.isTimerRunning,
    required this.aeMin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ae = task.aeCount(aeMin);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: isTimerRunning
            ? Icon(Icons.timer,
                color: Theme.of(context).colorScheme.primary)
            : Icon(Icons.radio_button_unchecked,
                color: Theme.of(context).colorScheme.outline),
        title: Text(task.task.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: task.customer != null ? Text(task.customer!.name) : null,
        trailing: Text('$ae AE',
            style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}
