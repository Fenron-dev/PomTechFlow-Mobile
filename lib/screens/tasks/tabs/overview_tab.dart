import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../providers/tasks_provider.dart';

class OverviewTab extends StatelessWidget {
  final TaskWithDetails detail;
  final bool isActiveTask;
  final VoidCallback onStartTimer;
  final VoidCallback onMarkDone;

  const OverviewTab({
    super.key,
    required this.detail,
    required this.isActiveTask,
    required this.onStartTimer,
    required this.onMarkDone,
  });

  @override
  Widget build(BuildContext context) {
    final task = detail.task;
    final ae = detail.aeCount;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status-Banner
        _StatusBanner(status: task.status),
        const SizedBox(height: 16),

        // Timer-Aktionen
        if (task.status != 'COMPLETED')
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onStartTimer,
                  icon: Icon(isActiveTask ? Icons.timer : Icons.play_arrow),
                  label: Text(isActiveTask ? 'Timer läuft' : 'Timer starten'),
                ),
              ),
              if (task.status != 'COMPLETED') ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onMarkDone,
                  icon: const Icon(Icons.check),
                  label: const Text('Erledigt'),
                ),
              ],
            ],
          ),
        const SizedBox(height: 20),

        // Statistiken
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Arbeitseinheiten',
                value: ae.toStringAsFixed(1),
                unit: 'AE',
                icon: Icons.timer_outlined,
                color: cs.primaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Zeitaufwand',
                value: task.totalMinutes.toString(),
                unit: 'Min',
                icon: Icons.schedule,
                color: cs.secondaryContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Checkliste',
                value: '${detail.todoDoneCount}/${detail.todoCount}',
                unit: 'Punkte',
                icon: Icons.checklist,
                color: cs.tertiaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Sessions',
                value: detail.sessionCount.toString(),
                unit: 'Pomodoros',
                icon: Icons.repeat,
                color: cs.surfaceContainerHighest,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Kunde
        if (detail.customer != null)
          _InfoRow(
            icon: Icons.business_outlined,
            label: 'Kunde',
            value: detail.customer!.name,
          ),

        // Beschreibung
        if (task.description != null && task.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.description_outlined,
            label: 'Beschreibung',
            value: task.description!,
          ),
        ],

        const SizedBox(height: 12),
        _InfoRow(
          icon: Icons.calendar_today_outlined,
          label: 'Erstellt',
          value: DateFormat('dd.MM.yyyy HH:mm').format(task.createdAt.toLocal()),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (color, icon, label) = switch (status) {
      'ACTIVE' => (cs.primaryContainer, Icons.play_circle_outline, 'Aktiv'),
      'COMPLETED' => (
          cs.secondaryContainer,
          Icons.check_circle_outline,
          'Abgeschlossen'
        ),
      'PAUSED' => (cs.tertiaryContainer, Icons.pause_circle_outline, 'Pausiert'),
      _ => (cs.surfaceContainerHighest, Icons.schedule, 'Geplant'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
          Text(unit,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
