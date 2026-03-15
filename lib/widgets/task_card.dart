import 'package:flutter/material.dart';
import '../providers/tasks_provider.dart';

class TaskCard extends StatelessWidget {
  final TaskWithDetails task;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool isTimerRunning;

  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    required this.onDelete,
    this.isTimerRunning = false,
  });

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      'ACTIVE' => cs.primaryContainer,
      'COMPLETED' => cs.secondaryContainer,
      'PAUSED' => cs.tertiaryContainer,
      _ => cs.surfaceContainerHighest,
    };
  }

  String _statusLabel(String status) => switch (status) {
        'ACTIVE' => 'Aktiv',
        'COMPLETED' => 'Erledigt',
        'PAUSED' => 'Pausiert',
        _ => 'Geplant',
      };

  @override
  Widget build(BuildContext context) {
    final t = task.task;
    final ae = task.aeCount;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isTimerRunning)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.timer,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  Expanded(
                    child: Text(
                      t.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: _statusLabel(t.status),
                    color: _statusColor(context, t.status),
                  ),
                ],
              ),
              if (task.customer != null) ...[
                const SizedBox(height: 4),
                Text(
                  task.customer!.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.timer_outlined,
                    label: '${ae.toStringAsFixed(1)} AE',
                  ),
                  const SizedBox(width: 8),
                  if (task.todoCount > 0)
                    _InfoChip(
                      icon: Icons.checklist,
                      label: '${task.todoDoneCount}/${task.todoCount}',
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    color: Theme.of(context).colorScheme.error,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 3),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}
