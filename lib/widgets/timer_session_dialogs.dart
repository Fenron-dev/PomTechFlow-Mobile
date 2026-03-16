import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/timer_provider.dart';

// ─── Start-Dialog: Welche Todos planst du in dieser Session? ─────────────────

Future<bool> showTimerStartDialog(
  BuildContext context,
  WidgetRef ref,
  String taskId,
) async {
  final db = ref.read(databaseProvider);
  final todos = await (db.select(db.todos)
        ..where((t) => t.taskId.equals(taskId))
        ..where((t) => t.completed.equals(false))
        ..orderBy([(t) => drift.OrderingTerm(expression: t.sortOrder)]))
      .get();

  if (!context.mounted) return false;

  // Keine offenen Todos → direkt starten ohne Dialog
  if (todos.isEmpty) return true;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TimerStartSheet(todos: todos),
  );
  return result ?? false;
}

class _TimerStartSheet extends StatefulWidget {
  final List<Todo> todos;
  const _TimerStartSheet({required this.todos});

  @override
  State<_TimerStartSheet> createState() => _TimerStartSheetState();
}

class _TimerStartSheetState extends State<_TimerStartSheet> {
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    // Erste 3 offene Todos vorauswählen
    for (final todo in widget.todos.take(3)) {
      _selected.add(todo.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.play_circle_outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Timer starten',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Was planst du in dieser Session zu erledigen?',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: ListView(
              shrinkWrap: true,
              children: widget.todos
                  .map((todo) => CheckboxListTile(
                        dense: true,
                        value: _selected.contains(todo.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(todo.id);
                          } else {
                            _selected.remove(todo.id);
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Abbrechen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Starten'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
    // Bereits erledigte rausfiltern, offene vorauswählen
    for (final todo in widget.todos.where((t) => !t.completed)) {
      _toComplete.add(todo.id);
    }
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

/// Stops the running timer, shows the stop dialog, and persists the result.
/// Can be called from any screen (timer, task list, dashboard).
Future<void> handleTimerStop(BuildContext context, WidgetRef ref) async {
  final timer = ref.read(timerProvider);
  final taskId = timer.activeTaskId;
  final sessionMins = timer.elapsedSeconds ~/ 60;

  await ref.read(timerProvider.notifier).stop();
  if (taskId == null || !context.mounted) return;

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
