import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/timer_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/timer_session_dialogs.dart';

class TimerScreen extends ConsumerWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(timerProvider);
    final tasksAsync = ref.watch(tasksProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timer'),
        actions: [
          // Quick-Reminder Bell
          IconButton(
            icon: const Icon(Icons.alarm_add_outlined),
            tooltip: 'Erinnerung setzen',
            onPressed: () => _showReminderDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status-Label
                Text(
                  switch (timer.status) {
                    TimerStatus.running => 'Läuft',
                    TimerStatus.paused => 'Pausiert',
                    TimerStatus.idle => 'Bereit',
                  },
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: cs.primary),
                ),
                const SizedBox(height: 32),

                // Timer-Ring (füllt sich alle 25 Minuten)
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
                          color: timer.status == TimerStatus.paused
                              ? cs.tertiary
                              : cs.primary,
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
                                    ? Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16),
                                        child: Text(
                                          t.task.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(color: cs.outline),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
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
                        orElse: () => const CircularProgressIndicator(),
                      ),
                    ] else ...[
                      if (timer.status == TimerStatus.paused)
                        _ControlButton(
                          icon: Icons.play_arrow,
                          color: cs.primary,
                          onPressed: () =>
                              ref.read(timerProvider.notifier).resume(),
                          size: 64,
                        )
                      else
                        _ControlButton(
                          icon: Icons.pause,
                          color: cs.primary,
                          onPressed: () =>
                              ref.read(timerProvider.notifier).pause(),
                          size: 64,
                        ),
                      const SizedBox(width: 20),
                      _ControlButton(
                        icon: Icons.stop,
                        color: cs.error,
                        onPressed: () =>
                            _stopTimer(context, ref, timer),
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

  Future<void> _stopTimer(
      BuildContext context, WidgetRef ref, TimerState timer) async {
    await handleTimerStop(context, ref);
  }

  Future<void> _showReminderDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => const _ReminderDialog(),
    );
  }
}

// ─── Quick Reminder Dialog ────────────────────────────────────────────────────

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog();

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  int _minutes = 10;
  final _textCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textCtrl.text = 'Server nochmal prüfen';
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presets = [5, 10, 15, 20, 30];
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.alarm_add_outlined),
        SizedBox(width: 10),
        Text('Erinnerung setzen'),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _textCtrl,
            decoration: const InputDecoration(
              labelText: 'Woran erinnern?',
              isDense: true,
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          Text('In wie vielen Minuten?',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: presets
                .map((p) => ChoiceChip(
                      label: Text('$p min'),
                      selected: _minutes == p,
                      onSelected: (_) => setState(() => _minutes = p),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Individuell: '),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextFormField(
                  initialValue: _minutes.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffix: Text('min'),
                  ),
                  onChanged: (v) {
                    final val = int.tryParse(v);
                    if (val != null && val > 0) setState(() => _minutes = val);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.alarm_on),
          label: const Text('Setzen'),
          onPressed: () async {
            Navigator.pop(context);
            final when =
                DateTime.now().add(Duration(minutes: _minutes));
            final text = _textCtrl.text.trim().isEmpty
                ? 'Erinnerung'
                : _textCtrl.text.trim();
            await NotificationService.scheduleReminder(text, when);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Erinnerung in $_minutes Min: $text'),
              ));
            }
          },
        ),
      ],
    );
  }
}

// ─── Task Picker ──────────────────────────────────────────────────────────────

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

// ─── Control Button ───────────────────────────────────────────────────────────

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

// ─── Ring Painter ─────────────────────────────────────────────────────────────

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

    if (progress > 0) {
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
  }

  @override
  bool shouldRepaint(_TimerRingPainter old) =>
      old.progress != progress || old.color != color;
}
