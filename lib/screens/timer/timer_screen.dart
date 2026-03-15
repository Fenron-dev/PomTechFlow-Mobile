import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/timer_provider.dart';
import '../../providers/tasks_provider.dart';

class TimerScreen extends ConsumerWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(timerProvider);
    final tasksAsync = ref.watch(tasksProvider);
    final cs = Theme.of(context).colorScheme;

    final phaseLabel = switch (timer.phase) {
      TimerPhase.work => 'Fokuszeit',
      TimerPhase.shortBreak => 'Kurze Pause',
      TimerPhase.longBreak => 'Lange Pause',
    };

    final phaseColor = switch (timer.phase) {
      TimerPhase.work => cs.primary,
      TimerPhase.shortBreak => cs.secondary,
      TimerPhase.longBreak => cs.tertiary,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Timer')),
      body: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Pomodoro-Punkte
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    4,
                    (i) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.circle,
                        size: 12,
                        color: i < (timer.completedPomodoros % 4)
                            ? phaseColor
                            : cs.outlineVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(phaseLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: phaseColor)),
                const SizedBox(height: 32),

                // Timer-Ring
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(220, 220),
                        painter: _TimerRingPainter(
                          progress: timer.progress,
                          color: phaseColor,
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timer.timeString,
                            style: Theme.of(context)
                                .textTheme
                                .displayMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                          ),
                          if (timer.activeTaskId != null)
                            tasksAsync.maybeWhen(
                              data: (tasks) {
                                final t = tasks
                                    .where((t) =>
                                        t.task.id == timer.activeTaskId)
                                    .firstOrNull;
                                return t != null
                                    ? Text(
                                        t.task.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(color: cs.outline),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : const SizedBox();
                              },
                              orElse: () => const SizedBox(),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Steuerung
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (timer.status == TimerStatus.idle) ...[
                      // Task-Auswahl wenn idle
                      tasksAsync.maybeWhen(
                        data: (tasks) {
                          final activeTasks = tasks
                              .where((t) =>
                                  t.task.status == 'ACTIVE' ||
                                  t.task.status == 'PLANNED')
                              .toList();
                          if (activeTasks.isEmpty) {
                            return Text('Keine Tasks vorhanden',
                                style: TextStyle(color: cs.outline));
                          }
                          return _TaskPickerButton(
                            tasks: activeTasks,
                            onStart: (taskId) => ref
                                .read(timerProvider.notifier)
                                .start(taskId),
                          );
                        },
                        orElse: () =>
                            const CircularProgressIndicator(),
                      ),
                    ] else ...[
                      if (timer.status == TimerStatus.paused)
                        _ControlButton(
                          icon: Icons.play_arrow,
                          color: phaseColor,
                          onPressed: () =>
                              ref.read(timerProvider.notifier).resume(),
                          size: 64,
                        )
                      else
                        _ControlButton(
                          icon: Icons.pause,
                          color: phaseColor,
                          onPressed: () =>
                              ref.read(timerProvider.notifier).pause(),
                          size: 64,
                        ),
                      const SizedBox(width: 20),
                      _ControlButton(
                        icon: Icons.stop,
                        color: cs.error,
                        onPressed: () =>
                            ref.read(timerProvider.notifier).stop(),
                        size: 48,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskPickerButton extends StatelessWidget {
  final List<TaskWithDetails> tasks;
  final ValueChanged<String> onStart;

  const _TaskPickerButton({required this.tasks, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () async {
        final taskId = await showModalBottomSheet<String>(
          context: context,
          builder: (_) => _TaskPickerSheet(tasks: tasks),
        );
        if (taskId != null) onStart(taskId);
      },
      icon: const Icon(Icons.play_arrow),
      label: const Text('Task auswählen & starten'),
    );
  }
}

class _TaskPickerSheet extends StatelessWidget {
  final List<TaskWithDetails> tasks;
  const _TaskPickerSheet({required this.tasks});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Task auswählen',
              style: Theme.of(context).textTheme.titleLarge),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: tasks.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(tasks[i].task.title),
              subtitle: tasks[i].customer != null
                  ? Text(tasks[i].customer!.name)
                  : null,
              trailing: Text('${tasks[i].aeCount()} AE'),
              onTap: () => Navigator.pop(context, tasks[i].task.id),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final double size;

  const _ControlButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Icon(icon, size: size * 0.45, color: Colors.white),
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  const _TimerRingPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 16) / 2;
    const strokeWidth = 10.0;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_TimerRingPainter old) =>
      old.progress != progress || old.color != color;
}
