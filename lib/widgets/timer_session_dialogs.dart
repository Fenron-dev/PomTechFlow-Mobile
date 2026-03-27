import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/timer_provider.dart';
import '../services/notification_service.dart';

// ─── Stop-Dialog: Was wurde erledigt? + Schnellnotiz ────────────────────────

class TimerStopResult {
  final List<String> completedTodoIds;
  final String? note;
  TimerStopResult({required this.completedTodoIds, this.note});
}

Future<TimerStopResult?> showTimerStopDialog(
  BuildContext context,
  WidgetRef ref,
  String taskId,
  int sessionMinutes,
) async {
  final db = ref.read(databaseProvider);
  final todos = await (db.select(db.todos)
        ..where((t) => t.taskId.equals(taskId))
        ..orderBy([(t) => drift.OrderingTerm(expression: t.sortOrder)]))
      .get();

  if (!context.mounted) return null;

  return showModalBottomSheet<TimerStopResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TimerStopSheet(todos: todos, sessionMinutes: sessionMinutes),
  );
}

class _TimerStopSheet extends ConsumerStatefulWidget {
  final List<Todo> todos;
  final int sessionMinutes;
  const _TimerStopSheet(
      {required this.todos, required this.sessionMinutes});

  @override
  ConsumerState<_TimerStopSheet> createState() => _TimerStopSheetState();
}

class _TimerStopSheetState extends ConsumerState<_TimerStopSheet> {
  final Set<String> _toComplete = {};
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Start with nothing selected — user picks what they completed
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.todos.where((t) => !t.completed).toList();
    final done = widget.todos.where((t) => t.completed).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.stop_circle_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Session beenden',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${widget.sessionMinutes} Min',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Offene Todos markieren
          if (open.isNotEmpty) ...[
            Text('Was hast du erledigt?',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary)),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.3,
              ),
              child: ListView(
                shrinkWrap: true,
                children: open
                    .map((todo) => CheckboxListTile(
                          dense: true,
                          value: _toComplete.contains(todo.id),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _toComplete.add(todo.id);
                            } else {
                              _toComplete.remove(todo.id);
                            }
                          }),
                          title: Text(todo.content),
                          subtitle: todo.workflowName != null
                              ? Text(todo.workflowName!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary))
                              : null,
                          controlAffinity: ListTileControlAffinity.leading,
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Bereits erledigt (Info)
          if (done.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${done.length} bereits erledigt',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ),

          // Schnellnotiz
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Notiz zur Session (optional)',
              hintText: 'Was wurde gemacht, Probleme, nächste Schritte...',
              isDense: true,
            ),
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context,
                      TimerStopResult(completedTodoIds: [], note: null)),
                  child: const Text('Überspringen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    TimerStopResult(
                      completedTodoIds: _toComplete.toList(),
                      note: _noteCtrl.text.trim().isEmpty
                          ? null
                          : _noteCtrl.text.trim(),
                    ),
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text('Speichern'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Hilfsfunktion: Kompletten Stop-Flow ausführen ───────────────────────────

/// Stops the running timer for [taskId], shows the stop dialog, and persists the result.
/// Can be called from any screen (timer, task list, dashboard).
Future<void> handleTimerStop(BuildContext context, WidgetRef ref, String taskId) async {
  final timerMap = ref.read(timerProvider);
  final entry = timerMap[taskId];
  if (entry == null) return;
  final sessionMins = entry.elapsedSeconds ~/ 60;

  await ref.read(timerProvider.notifier).stop(taskId);
  if (!context.mounted) return;

  final result = await showTimerStopDialog(context, ref, taskId, sessionMins);
  if (result == null || !context.mounted) return;

  final db = ref.read(databaseProvider);
  await applyTimerStopResult(db, taskId, result);

  if (result.note != null) {
    final sessions = await (db.select(db.sessions)
          ..where((s) => s.taskId.equals(taskId))
          ..orderBy([(s) => drift.OrderingTerm.desc(s.startTime)])
          ..limit(1))
        .get();
    if (sessions.isNotEmpty) {
      await (db.update(db.sessions)
            ..where((s) => s.id.equals(sessions.first.id)))
          .write(SessionsCompanion(note: drift.Value(result.note)));
    }
  }

  ref.invalidate(tasksProvider);
  ref.invalidate(sessionsProvider(taskId));
  ref.invalidate(taskDetailProvider(taskId));
}

// ─── Erinnerungsdialog ───────────────────────────────────────────────────────

Future<void> showQuickReminderDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const _ReminderDialog(),
  );
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog();

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  // preset quick-picks (minutes) — null means custom is active
  int? _presetMinutes = 10;
  // custom value + unit
  int _customValue = 10;
  String _customUnit = 'MIN'; // MIN | HOUR | DAY | WEEK
  final _textCtrl = TextEditingController();
  final _customCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textCtrl.text = 'Server nochmal prüfen';
    _customCtrl.text = '10';
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  int get _totalMinutes {
    final v = _presetMinutes ?? _customValue;
    if (_presetMinutes != null) return _presetMinutes!;
    return switch (_customUnit) {
      'HOUR' => v * 60,
      'DAY'  => v * 1440,
      'WEEK' => v * 10080,
      _      => v,
    };
  }

  String get _durationLabel {
    if (_presetMinutes != null) return '$_presetMinutes Min';
    return switch (_customUnit) {
      'HOUR' => '$_customValue Std',
      'DAY'  => '$_customValue ${_customValue == 1 ? "Tag" : "Tage"}',
      'WEEK' => '$_customValue ${_customValue == 1 ? "Woche" : "Wochen"}',
      _      => '$_customValue Min',
    };
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
          Text('Schnellauswahl (Minuten)',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: presets
                .map((p) => ChoiceChip(
                      label: Text('$p min'),
                      selected: _presetMinutes == p,
                      onSelected: (_) => setState(() {
                        _presetMinutes = p;
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Text('Individuell',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 64,
                child: TextFormField(
                  controller: _customCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (v) {
                    final val = int.tryParse(v);
                    if (val != null && val > 0) {
                      setState(() {
                        _customValue = val;
                        _presetMinutes = null;
                      });
                    }
                  },
                  onTap: () => setState(() => _presetMinutes = null),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _customUnit,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'MIN',  child: Text('Minuten')),
                  DropdownMenuItem(value: 'HOUR', child: Text('Stunden')),
                  DropdownMenuItem(value: 'DAY',  child: Text('Tage')),
                  DropdownMenuItem(value: 'WEEK', child: Text('Wochen')),
                ],
                onChanged: (v) => setState(() {
                  _customUnit = v!;
                  _presetMinutes = null;
                }),
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
            final when = DateTime.now().add(Duration(minutes: _totalMinutes));
            final text = _textCtrl.text.trim().isEmpty
                ? 'Erinnerung'
                : _textCtrl.text.trim();
            await NotificationService.scheduleReminder(text, when);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Erinnerung in $_durationLabel: $text'),
              ));
            }
          },
        ),
      ],
    );
  }
}

// ─── Hilfsfunktion: Stop-Ergebnis in DB schreiben ────────────────────────────

Future<void> applyTimerStopResult(
  AppDatabase db,
  String taskId,
  TimerStopResult result,
) async {
  // Todos als erledigt markieren
  for (final id in result.completedTodoIds) {
    await (db.update(db.todos)..where((t) => t.id.equals(id)))
        .write(const TodosCompanion(completed: drift.Value(true)));
  }
  // Notiz speichern
  if (result.note != null && result.note!.isNotEmpty) {
    await db.into(db.notes).insert(
          NotesCompanion.insert(taskId: taskId, content: result.note!),
        );
  }
}
