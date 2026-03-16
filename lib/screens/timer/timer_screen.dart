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
    final timerMap = ref.watch(timerProvider);
    final tasksAsync = ref.watch(tasksProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timer'),
        actions: [
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
            child: timerMap.isEmpty
                ? _buildIdleState(context, ref, tasksAsync, cs)
                : _buildActiveState(context, ref, timerMap, tasksAsync, cs),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleState(
      BuildContext context,
      WidgetRef ref,
      AsyncValue<List<TaskWithDetails>> tasksAsync,
      ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Bereit',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: cs.primary)),
        const SizedBox(height: 32),
        SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(220, 220),
                painter: _TimerRingPainter(
                  progress: 0,
                  color: cs.primary,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              Text(
                '00:00',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        tasksAsync.maybeWhen(
          data: (tasks) {
            final activeTasks = tasks
                .where((t) =>
                    t.task.status == 'ACTIVE' || t.task.status == 'PLANNED')
                .toList();
            if (activeTasks.isEmpty) {
              return Text('Keine Tasks vorhanden',
                  style: TextStyle(color: cs.outline));
            }
            return _TaskPickerButton(
              tasks: activeTasks,
              onStart: (taskId) =>
                  ref.read(timerProvider.notifier).start(taskId),
            );
          },
          orElse: () => const CircularProgressIndicator(),
        ),
      ],
    );
  }

  Widget _buildActiveState(
      BuildContext context,
      WidgetRef ref,
      Map<String, TimerEntry> timerMap,
      AsyncValue<List<TaskWithDetails>> tasksAsync,
      ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...timerMap.entries.map((entry) {
          final taskId = entry.key;
          final timerEntry = entry.value;
          final taskTitle = tasksAsync.maybeWhen(
                data: (tasks) => tasks
                    .where((t) => t.task.id == taskId)
                    .firstOrNull
                    ?.task
                    .title,
                orElse: () => null,
              ) ??
              taskId;
          return _ActiveTimerCard(
            taskId: taskId,
            taskTitle: taskTitle,
            entry: timerEntry,
            onPause: () => ref.read(timerProvider.notifier).pause(taskId),
            onResume: () => ref.read(timerProvider.notifier).resume(taskId),
            onStop: () => _stopTimer(context, ref, taskId),
          );
        }),
        const SizedBox(height: 16),
        tasksAsync.maybeWhen(
          data: (tasks) {
            final activeTasks = tasks
                .where((t) =>
                    (t.task.status == 'ACTIVE' ||
                        t.task.status == 'PLANNED') &&
                    !timerMap.containsKey(t.task.id))
                .toList();
            if (activeTasks.isEmpty) return const SizedBox();
            return _TaskPickerButton(
              tasks: activeTasks,
              label: 'Weiteren Task starten',
              onStart: (taskId) =>
                  ref.read(timerProvider.notifier).start(taskId),
            );
          },
          orElse: () => const SizedBox(),
        ),
      ],
    );
  }

  Future<void> _stopTimer(
      BuildContext context, WidgetRef ref, String taskId) async {
    await handleTimerStop(context, ref, taskId);
  }

  Future<void> _showReminderDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => const _ReminderDialog(),
    );
  }
}

// ─── Active Timer Card ────────────────────────────────────────────────────────

class _ActiveTimerCard extends StatelessWidget {
  final String taskId;
  final String taskTitle;
  final TimerEntry entry;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const _ActiveTimerCard({
    required this.taskId,
    required this.taskTitle,
    required this.entry,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRunning = entry.status == TimerStatus.running;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isRunning ? cs.primaryContainer : cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(72, 72),
                    painter: _TimerRingPainter(
                      progress: entry.progress,
                      color: isRunning ? cs.primary : cs.tertiary,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  Text(
                    entry.timeString,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                taskTitle,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (isRunning)
              IconButton.filled(
                onPressed: onPause,
                icon: const Icon(Icons.pause),
                tooltip: 'Pausieren',
              )
            else
              IconButton.filled(
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Fortsetzen',
              ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: onStop,
              icon: Icon(Icons.stop_circle_outlined, color: cs.error),
              tooltip: 'Stoppen',
            ),
          ],
        ),
      ),
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
  final String label;
  final ValueChanged<String> onStart;

  const _TaskPickerButton({
    required this.tasks,
    required this.onStart,
    this.label = 'Task auswählen & starten',
  });

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
      label: Text(label),
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
