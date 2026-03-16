import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/database_provider.dart';
import '../../services/csv_service.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final aeMin = settings?.aeMinutes ?? 10;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiken'),
        actions: [
          tasksAsync.maybeWhen(
            data: (tasks) => IconButton(
              icon: const Icon(Icons.table_chart_outlined),
              tooltip: 'Als CSV exportieren',
              onPressed: () async {
                try {
                  final db = ref.read(databaseProvider);
                  await CsvService.exportTasks(
                    db: db,
                    tasks: tasks,
                    aeMinutes: aeMin,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('CSV Fehler: $e')),
                    );
                  }
                }
              },
            ),
            orElse: () => const SizedBox(),
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tasks) => _StatisticsBody(tasks: tasks, aeMin: aeMin),
      ),
    );
  }
}

class _StatisticsBody extends ConsumerWidget {
  final List<TaskWithDetails> tasks;
  final int aeMin;

  const _StatisticsBody({required this.tasks, required this.aeMin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    // Alle Sessions laden
    final sessionsAsync = ref.watch(_allSessionsProvider);

    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (sessions) {
        final thisWeekSessions = sessions.where((s) =>
            s.startTime.isAfter(weekStart.subtract(const Duration(days: 1))));
        final thisMonthSessions = sessions.where((s) =>
            s.startTime.isAfter(monthStart.subtract(const Duration(days: 1))));

        final weekMin =
            thisWeekSessions.fold<int>(0, (s, sess) => s + sess.duration);
        final monthMin =
            thisMonthSessions.fold<int>(0, (s, sess) => s + sess.duration);
        final weekAE =
            weekMin == 0 ? 0 : (weekMin / aeMin).ceil();
        final monthAE =
            monthMin == 0 ? 0 : (monthMin / aeMin).ceil();

        // Tasks nach Status
        final completed = tasks
            .where((t) =>
                t.task.status == 'COMPLETED' || t.task.status == 'CRM_DONE')
            .length;
        final active = tasks.where((t) => t.task.status == 'ACTIVE').length;
        final planned = tasks.where((t) => t.task.status == 'PLANNED').length;

        // Tasks abgeschlossen diese Woche/Monat
        final completedThisWeek = tasks
            .where((t) =>
                t.task.status == 'COMPLETED' &&
                t.task.updatedAt.isAfter(
                    weekStart.subtract(const Duration(days: 1))))
            .length;
        final completedThisMonth = tasks
            .where((t) =>
                t.task.status == 'COMPLETED' &&
                t.task.updatedAt.isAfter(
                    monthStart.subtract(const Duration(days: 1))))
            .length;

        // Top Kunden nach Gesamtzeit
        final customerMinutes = <String, int>{};
        final customerNames = <String, String>{};
        for (final t in tasks) {
          if (t.customer != null && t.task.totalMinutes > 0) {
            customerMinutes[t.customer!.id] =
                (customerMinutes[t.customer!.id] ?? 0) + t.task.totalMinutes;
            customerNames[t.customer!.id] = t.customer!.name;
          }
        }
        final topCustomers = customerMinutes.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        final cs = Theme.of(context).colorScheme;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Diese Woche ──────────────────────────────────────────
            _SectionHeader('Diese Woche',
                sub: '${DateFormat('dd.MM').format(weekStart)} – ${DateFormat('dd.MM.yyyy').format(now)}'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _StatTile(
                        value: '$weekAE AE',
                        label: '$weekMin Min',
                        icon: Icons.timer_outlined,
                        color: cs.primaryContainer)),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatTile(
                        value: '$completedThisWeek',
                        label: 'abgeschlossen',
                        icon: Icons.check_circle_outline,
                        color: cs.secondaryContainer)),
              ],
            ),
            const SizedBox(height: 24),

            // ── Dieser Monat ─────────────────────────────────────────
            _SectionHeader('Dieser Monat',
                sub: DateFormat('MMMM yyyy', 'de_DE').format(now)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _StatTile(
                        value: '$monthAE AE',
                        label: '$monthMin Min',
                        icon: Icons.calendar_month_outlined,
                        color: cs.tertiaryContainer)),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatTile(
                        value: '$completedThisMonth',
                        label: 'abgeschlossen',
                        icon: Icons.check_circle_outline,
                        color: cs.surfaceContainerHighest)),
              ],
            ),
            const SizedBox(height: 24),

            // ── Tasks Übersicht ───────────────────────────────────────
            _SectionHeader('Alle Tasks', sub: '${tasks.length} gesamt'),
            const SizedBox(height: 8),
            _StatusBar(
              active: active,
              planned: planned,
              completed: completed,
              total: tasks.length,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StatusChip(
                    label: 'Aktiv',
                    count: active,
                    color: Colors.blue),
                const SizedBox(width: 8),
                _StatusChip(
                    label: 'Geplant',
                    count: planned,
                    color: Colors.grey),
                const SizedBox(width: 8),
                _StatusChip(
                    label: 'Erledigt',
                    count: completed,
                    color: Colors.green),
              ],
            ),
            const SizedBox(height: 24),

            // ── Top Kunden ────────────────────────────────────────────
            if (topCustomers.isNotEmpty) ...[
              _SectionHeader('Top Kunden', sub: 'nach Zeitaufwand'),
              const SizedBox(height: 8),
              ...topCustomers.take(5).map((e) {
                final name = customerNames[e.key] ?? e.key;
                final ae = (e.value / aeMin).ceil();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primaryContainer,
                    child: Text(name[0].toUpperCase(),
                        style: TextStyle(
                            color: cs.primary, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(name),
                  trailing: Text('$ae AE · ${e.value} Min',
                      style: Theme.of(context).textTheme.labelSmall),
                );
              }),
            ],
          ],
        );
      },
    );
  }
}

// Provider für alle Sessions
final _allSessionsProvider = FutureProvider((ref) async {
  final db = ref.watch(databaseProvider);
  return db.select(db.sessions).get();
});

class _SectionHeader extends StatelessWidget {
  final String title;
  final String sub;
  const _SectionHeader(this.title, {required this.sub});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text(sub,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final int active;
  final int planned;
  final int completed;
  final int total;
  const _StatusBar(
      {required this.active,
      required this.planned,
      required this.completed,
      required this.total});

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Row(
        children: [
          if (active > 0)
            Expanded(
                flex: active,
                child: Container(height: 8, color: Colors.blue)),
          if (planned > 0)
            Expanded(
                flex: planned,
                child: Container(height: 8, color: Colors.grey.shade400)),
          if (completed > 0)
            Expanded(
                flex: completed,
                child: Container(height: 8, color: Colors.green)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatusChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$count $label',
            style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
