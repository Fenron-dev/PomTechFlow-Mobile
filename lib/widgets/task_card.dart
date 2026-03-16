import 'package:flutter/material.dart';
import '../providers/tasks_provider.dart';

// Layout nach Screenshot: Icon + Titel, Kunde + Fortschritt, Zeit/AE + Play + Status + Menü

class TaskCard extends StatelessWidget {
  final TaskWithDetails task;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool isTimerRunning;
  final bool isTimerPaused;
  final int aeMinutes;
  final bool isSelected;
  final VoidCallback? onTimerStart;
  final VoidCallback? onTimerPause;
  final VoidCallback? onTimerResume;
  final VoidCallback? onTimerStop;

  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    required this.onDelete,
    this.isTimerRunning = false,
    this.isTimerPaused = false,
    this.aeMinutes = 10,
    this.isSelected = false,
    this.onTimerStart,
    this.onTimerPause,
    this.onTimerResume,
    this.onTimerStop,
  });

  @override
  Widget build(BuildContext context) {
    final t = task.task;
    final cs = Theme.of(context).colorScheme;
    final ae = task.aeCount(aeMinutes);
    final mins = t.totalMinutes;

    // Status-Icon wie im Screenshot
    final statusIcon = switch (t.status) {
      'ACTIVE' => Icon(Icons.timer, color: cs.primary, size: 22),
      'COMPLETED' => Icon(Icons.check_circle, color: Colors.green, size: 22),
      'CRM_DONE' => Icon(Icons.cloud_done_outlined, color: Colors.teal, size: 22),
      _ => Icon(Icons.radio_button_unchecked, color: cs.outline, size: 22),
    };

    // Status Badge Farbe
    final badgeColor = switch (t.status) {
      'ACTIVE' => Colors.blue.shade100,
      'COMPLETED' => Colors.green.shade100,
      'PAUSED' => Colors.orange.shade100,
      'CRM_DONE' => Colors.teal.shade100,
      _ => cs.surfaceContainerHighest,
    };
    final badgeTextColor = switch (t.status) {
      'ACTIVE' => Colors.blue.shade800,
      'COMPLETED' => Colors.green.shade800,
      'PAUSED' => Colors.orange.shade800,
      'CRM_DONE' => Colors.teal.shade800,
      _ => cs.onSurface,
    };
    final badgeLabel = switch (t.status) {
      'ACTIVE' => 'AKTIV',
      'COMPLETED' => 'ERLEDIGT',
      'PAUSED' => 'PAUSIERT',
      'CRM_DONE' => 'CRM',
      _ => 'GEPLANT',
    };

    final priorityColor = switch (t.priority) {
      'CRITICAL' => Colors.red,
      'HIGH' => Colors.orange,
      'LOW' => Colors.blueGrey.shade300,
      _ => Colors.transparent,
    };

    final isActiveTimer = isTimerRunning || isTimerPaused;
    final canStartTimer = t.status != 'COMPLETED' && t.status != 'CRM_DONE';

    return Card(
      margin: EdgeInsets.zero,
      color: isSelected ? cs.secondaryContainer : null,
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        if (t.priority != 'NORMAL')
          Container(width: 4, color: priorityColor),
        Expanded(child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Zeile 1: Status-Icon + Titel
              Row(
                children: [
                  statusIcon,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (t.recurring)
                    Tooltip(
                      message: 'Wiederkehrender Task',
                      child: Icon(Icons.repeat,
                          size: 16, color: cs.primary),
                    ),
                ],
              ),

              // Zeile 2: Kunde + Checklisten-Fortschritt
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 2),
                child: Row(
                  children: [
                    if (task.customer != null)
                      Text(
                        task.customer!.name,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.outline),
                      ),
                    if (task.customer != null && task.todoCount > 0)
                      Text(' • ',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.outline)),
                    if (task.todoCount > 0)
                      Text(
                        '${task.todoDoneCount}/${task.todoCount} erledigt',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.outline),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Zeile 3: Zeit/AE + Timer-Buttons + Status-Badge + Menü
              Row(
                children: [
                  const SizedBox(width: 32),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${mins}m',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold),
                          ),
                          if (t.estimatedMinutes != null &&
                              mins > t.estimatedMinutes!)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Tooltip(
                                message: 'Zeitbudget überschritten (${t.estimatedMinutes} Min)',
                                child: const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 14,
                                    color: Colors.orange),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        '$ae AE',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.outline),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Timer-Buttons
                  if (canStartTimer) ...[
                    // Play/Pause button
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
                        color: isActiveTimer ? cs.primary : cs.outline,
                        size: 28,
                      ),
                    ),
                    // Stop button (only when this task's timer is active)
                    if (isActiveTimer) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onTimerStop,
                        child: Icon(
                          Icons.stop_circle_outlined,
                          color: cs.error,
                          size: 26,
                        ),
                      ),
                    ],
                  ],

                  const Spacer(),
                  // Status-Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badgeLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: badgeTextColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                  // Drei-Punkte-Menü
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (v) {
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Löschen'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      )), // Expanded + InkWell
      ],
      ), // Row
      ), // IntrinsicHeight
    );
  }
}
