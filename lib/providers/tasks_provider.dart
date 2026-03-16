import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'database_provider.dart';
import '../db/database.dart';

// Task mit Kunde + Counts
class TaskWithDetails {
  final Task task;
  final Customer? customer;
  final int todoCount;
  final int todoDoneCount;
  final int sessionCount;

  const TaskWithDetails({
    required this.task,
    this.customer,
    this.todoCount = 0,
    this.todoDoneCount = 0,
    this.sessionCount = 0,
  });

  // AE pro angefangene 10 Min (aufrunden), konfigurierbar via aeMinutes
  int aeCount([int aeMinutes = 10]) =>
      task.totalMinutes == 0 ? 0 : (task.totalMinutes / aeMinutes).ceil();
}

// Alle Tasks laden
final tasksProvider = FutureProvider<List<TaskWithDetails>>((ref) async {
  final db = ref.watch(databaseProvider);

  final tasks = await (db.select(db.tasks)
        ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]))
      .get();

  final result = <TaskWithDetails>[];
  for (final task in tasks) {
    Customer? customer;
    if (task.customerId != null) {
      customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(task.customerId!)))
          .getSingleOrNull();
    }
    final todos = await (db.select(db.todos)
          ..where((t) => t.taskId.equals(task.id)))
        .get();
    final sessions = await (db.select(db.sessions)
          ..where((s) => s.taskId.equals(task.id)))
        .get();

    result.add(TaskWithDetails(
      task: task,
      customer: customer,
      todoCount: todos.length,
      todoDoneCount: todos.where((t) => t.completed).length,
      sessionCount: sessions.length,
    ));
  }
  return result;
});

// Einzelner Task
final taskDetailProvider =
    FutureProvider.family<TaskWithDetails?, String>((ref, taskId) async {
  final db = ref.watch(databaseProvider);
  final task = await (db.select(db.tasks)
        ..where((t) => t.id.equals(taskId)))
      .getSingleOrNull();
  if (task == null) return null;

  Customer? customer;
  if (task.customerId != null) {
    customer = await (db.select(db.customers)
          ..where((c) => c.id.equals(task.customerId!)))
        .getSingleOrNull();
  }
  final todos = await (db.select(db.todos)
        ..where((t) => t.taskId.equals(task.id)))
      .get();
  final sessions = await (db.select(db.sessions)
        ..where((s) => s.taskId.equals(task.id)))
      .get();

  return TaskWithDetails(
    task: task,
    customer: customer,
    todoCount: todos.length,
    todoDoneCount: todos.where((t) => t.completed).length,
    sessionCount: sessions.length,
  );
});

// Todos eines Tasks
final todosProvider =
    FutureProvider.family<List<Todo>, String>((ref, taskId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.todos)
        ..where((t) => t.taskId.equals(taskId))
        ..orderBy([(t) => drift.OrderingTerm.asc(t.sortOrder)]))
      .get();
});

// Hardware eines Tasks
final hardwareProvider =
    FutureProvider.family<List<HardwareData>, String>((ref, taskId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.hardware)
        ..where((h) => h.taskId.equals(taskId))
        ..orderBy([(h) => drift.OrderingTerm.asc(h.sortOrder)]))
      .get();
});

// Notizen eines Tasks
final notesProvider =
    FutureProvider.family<List<Note>, String>((ref, taskId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.notes)
        ..where((n) => n.taskId.equals(taskId))
        ..orderBy([(n) => drift.OrderingTerm.desc(n.createdAt)]))
      .get();
});

// Anzahl offener Tasks (für App-Badge)
final openTasksCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(tasksProvider).valueOrNull ?? [];
  return tasks
      .where((t) =>
          t.task.status == 'PLANNED' || t.task.status == 'ACTIVE')
      .length;
});

// Sessions eines Tasks (für manuelle Bearbeitung)
final sessionsProvider =
    FutureProvider.family<List<Session>, String>((ref, taskId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.sessions)
        ..where((s) => s.taskId.equals(taskId))
        ..orderBy([(s) => drift.OrderingTerm.desc(s.startTime)]))
      .get();
});
