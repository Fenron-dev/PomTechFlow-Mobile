import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:go_router/go_router.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/timer_provider.dart';
import '../../db/database.dart';
import '../../services/task_handover_service.dart';
import '../../widgets/timer_session_dialogs.dart';
import 'tabs/overview_tab.dart';
import 'tabs/checklist_tab.dart';
import 'tabs/hardware_tab.dart';
import 'tabs/notes_tab.dart';
import 'tabs/photos_tab.dart';

class TaskDetailScreen extends ConsumerWidget {
  final String taskId;
  /// When true, the widget is embedded in a master-detail Row (tablet).
  /// Suppresses the automatic back button and uses callbacks for side effects.
  final bool embedded;
  final VoidCallback? onDeleted;
  final VoidCallback? onTaskChanged;

  const TaskDetailScreen({
    super.key,
    required this.taskId,
    this.embedded = false,
    this.onDeleted,
    this.onTaskChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskDetailProvider(taskId));
    final timer = ref.watch(timerProvider);

    return taskAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (detail) {
        if (detail == null) {
          return const Scaffold(body: Center(child: Text('Task nicht gefunden')));
        }
        final task = detail.task;
        final isActiveTask = timer.containsKey(taskId);

        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: !embedded,
              title: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.alarm_add_outlined),
                  tooltip: 'Erinnerung setzen',
                  onPressed: () => showQuickReminderDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    await context.push('/tasks/$taskId/edit');
                    ref.invalidate(taskDetailProvider(taskId));
                    onTaskChanged?.call();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share_outlined),
                  tooltip: 'Task übergeben',
                  onPressed: () async {
                    try {
                      final db = ref.read(databaseProvider);
                      await TaskHandoverService.exportTask(db, taskId);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Fehler: $e')),
                        );
                      }
                    }
                  },
                ),
                PopupMenuButton<String>(
                  tooltip: 'Status setzen',
                  onSelected: (v) async {
                    if (v == 'done') {
                      await _markDone(ref, taskId);
                      onTaskChanged?.call();
                    } else if (v == 'planned') {
                      await _setStatus(ref, taskId, 'PLANNED');
                      onTaskChanged?.call();
                    } else if (v == 'duplicate') {
                      final newId = await _duplicateTask(ref, taskId);
                      if (newId != null && context.mounted) {
                        context.push('/tasks/$newId');
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'done',
                      enabled: task.status != 'COMPLETED',
                      child: const Row(children: [
                        Icon(Icons.check_circle_outline, color: Colors.green),
                        SizedBox(width: 10),
                        Text('Abschließen'),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'planned',
                      enabled: task.status != 'PLANNED',
                      child: const Row(children: [
                        Icon(Icons.replay_outlined),
                        SizedBox(width: 10),
                        Text('Zurück auf Geplant'),
                      ]),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'duplicate',
                      child: const Row(children: [
                        Icon(Icons.copy_outlined),
                        SizedBox(width: 10),
                        Text('Duplizieren'),
                      ]),
                    ),
                  ],
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.info_outline), text: 'Übersicht'),
                  Tab(icon: Icon(Icons.checklist), text: 'Checkliste'),
                  Tab(icon: Icon(Icons.computer_outlined), text: 'Hardware'),
                  Tab(icon: Icon(Icons.notes), text: 'Notizen'),
                  Tab(icon: Icon(Icons.photo_library_outlined), text: 'Fotos'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                OverviewTab(
                  detail: detail,
                  isActiveTask: isActiveTask,
                  onStartTimer: () async {
                    await ref.read(timerProvider.notifier).start(taskId);
                    if (!embedded && context.mounted) context.go('/timer');
                  },
                  onMarkDone: () async {
                    await _markDone(ref, taskId);
                    onTaskChanged?.call();
                  },
                ),
                ChecklistTab(taskId: taskId),
                HardwareTab(taskId: taskId),
                NotesTab(taskId: taskId),
                PhotosTab(taskId: taskId),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _setStatus(WidgetRef ref, String taskId, String status) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        status: drift.Value(status),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    ref.invalidate(taskDetailProvider(taskId));
    ref.invalidate(tasksProvider);
  }

  Future<void> _markDone(WidgetRef ref, String taskId) async {
    final db = ref.read(databaseProvider);
    final task = await (db.select(db.tasks)..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        status: const drift.Value('COMPLETED'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Wiederkehrenden Task anlegen
    if (task != null && task.recurring && task.recurrenceType != null) {
      final nextDate = _nextRecurrenceDate(
          task.plannedDate ?? DateTime.now(),
          task.recurrenceType!,
          task.recurrenceInterval);
      await db.into(db.tasks).insert(TasksCompanion.insert(
            title: task.title,
            description: drift.Value(task.description),
            customerId: drift.Value(task.customerId),
            plannedDate: drift.Value(nextDate),
            recurring: const drift.Value(true),
            recurrenceType: drift.Value(task.recurrenceType),
            recurrenceInterval: drift.Value(task.recurrenceInterval),
            updatedAt: drift.Value(DateTime.now()),
          ));
    }

    ref.invalidate(taskDetailProvider(taskId));
    ref.invalidate(tasksProvider);
  }

  /// Kopiert Task + Todos + Hardware + Notizen als neuen PLANNED-Task.
  /// Gibt die neue Task-ID zurück, oder null bei Fehler.
  Future<String?> _duplicateTask(WidgetRef ref, String sourceId) async {
    final db = ref.read(databaseProvider);
    final task = await (db.select(db.tasks)
          ..where((t) => t.id.equals(sourceId)))
        .getSingleOrNull();
    if (task == null) return null;

    // Neue Task-ID generieren (Drift nutzt clientDefault, wir übergeben keinen Wert)
    final newTaskId = await db.into(db.tasks).insertReturning(
          TasksCompanion.insert(
            title: '${task.title} (Kopie)',
            description: drift.Value(task.description),
            customerId: drift.Value(task.customerId),
            status: const drift.Value('PLANNED'),
            priority: drift.Value(task.priority),
            plannedDate: drift.Value(task.plannedDate),
            estimatedMinutes: drift.Value(task.estimatedMinutes),
            recurring: drift.Value(task.recurring),
            recurrenceType: drift.Value(task.recurrenceType),
            recurrenceInterval: drift.Value(task.recurrenceInterval),
            recurrenceWeekday: drift.Value(task.recurrenceWeekday),
            recurrenceMonthDay: drift.Value(task.recurrenceMonthDay),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );

    final newId = newTaskId.id;

    // Todos kopieren
    final todos = await (db.select(db.todos)
          ..where((t) => t.taskId.equals(sourceId))
          ..orderBy([(t) => drift.OrderingTerm.asc(t.sortOrder)]))
        .get();
    for (final t in todos) {
      await db.into(db.todos).insert(TodosCompanion.insert(
            taskId: newId,
            content: t.content,
            completed: drift.Value(false), // zurücksetzen
            sortOrder: drift.Value(t.sortOrder),
            workflowId: drift.Value(t.workflowId),
            workflowName: drift.Value(t.workflowName),
          ));
    }

    // Hardware kopieren
    final hw = await (db.select(db.hardware)
          ..where((h) => h.taskId.equals(sourceId))
          ..orderBy([(h) => drift.OrderingTerm.asc(h.sortOrder)]))
        .get();
    for (final h in hw) {
      await db.into(db.hardware).insert(HardwareCompanion.insert(
            taskId: newId,
            type: h.type,
            name: drift.Value(h.name),
            serial: drift.Value(h.serial),
            notes: drift.Value(h.notes),
            sortOrder: drift.Value(h.sortOrder),
          ));
    }

    // Notizen kopieren
    final notes = await (db.select(db.notes)
          ..where((n) => n.taskId.equals(sourceId)))
        .get();
    for (final n in notes) {
      await db.into(db.notes).insert(NotesCompanion.insert(
            taskId: newId,
            content: n.content,
          ));
    }

    ref.invalidate(tasksProvider);
    return newId;
  }

  DateTime _nextRecurrenceDate(
      DateTime base, String type, int interval) {
    return switch (type) {
      'DAILY' => base.add(Duration(days: interval)),
      'WEEKLY' => base.add(Duration(days: 7 * interval)),
      'MONTHLY' => DateTime(
          base.year, base.month + interval, base.day,
          base.hour, base.minute),
      'QUARTERLY' => DateTime(
          base.year, base.month + (3 * interval), base.day,
          base.hour, base.minute),
      _ => base.add(Duration(days: 7 * interval)),
    };
  }
}
