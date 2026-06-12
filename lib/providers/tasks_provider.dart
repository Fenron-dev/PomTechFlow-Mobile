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

// Alle Tasks laden – bulk-load statt N+1-Queries
final tasksProvider = FutureProvider<List<TaskWithDetails>>((ref) async {
  final db = ref.watch(databaseProvider);

  // Archivierte Tasks werden in der Hauptliste nicht angezeigt
  final tasks = await (db.select(db.tasks)
        ..where((t) => t.archivedAt.isNull())
        ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]))
      .get();

  if (tasks.isEmpty) return [];

  // Alle verknüpften Daten in je einer Query laden
  final customers = await db.select(db.customers).get();
  final todos = await db.select(db.todos).get();
  final sessions = await db.select(db.sessions).get();

  final customerMap = {for (final c in customers) c.id: c};

  return tasks.map((task) {
    final taskTodos = todos.where((t) => t.taskId == task.id).toList();
    final taskSessions = sessions.where((s) => s.taskId == task.id).toList();
    return TaskWithDetails(
      task: task,
      customer: task.customerId != null ? customerMap[task.customerId] : null,
      todoCount: taskTodos.length,
      todoDoneCount: taskTodos.where((t) => t.completed).length,
      sessionCount: taskSessions.length,
    );
  }).toList();
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

// Anzahl offener Tasks (für App-Badge) – gezielter DB-Stream statt Ableitung aus
// dem vollständigen tasksProvider (der Todos/Sessions/Customers mitlädt).
final openTasksCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  final count = db.tasks.id.count();
  final query = db.selectOnly(db.tasks)
    ..addColumns([count])
    ..where(
      db.tasks.archivedAt.isNull() &
      (db.tasks.status.equals('PLANNED') | db.tasks.status.equals('ACTIVE')),
    );
  return query.watchSingle().map((row) => row.read(count) ?? 0);
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

// ── Dashboard „Im Blick" ──────────────────────────────────────────────────────

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Entscheidet, ob ein Task in der Dashboard-Sektion „Im Blick" erscheint.
/// [hasActiveTimer] = laufender oder pausierter Timer für diesen Task.
///
/// Sichtbar wenn: aktiver Timer ODER ans Dashboard gepinnt ODER heute geplant.
/// Bleibt sichtbar bis manuell abgewählt (`dashboardDismissedAt` = heute) oder
/// erledigt/archiviert. Ein aktiver Timer hat immer Vorrang.
bool isFocusTask(Task t, {required bool hasActiveTimer, DateTime? now}) {
  if (t.status == 'COMPLETED' || t.archivedAt != null) return false;
  if (hasActiveTimer) return true;
  final ref = now ?? DateTime.now();
  final dismissedToday =
      t.dashboardDismissedAt != null && _sameDay(t.dashboardDismissedAt!, ref);
  if (dismissedToday) return false;
  if (t.dashboardPinned) return true;
  if (t.plannedDate != null && _sameDay(t.plannedDate!, ref)) return true;
  return false;
}

/// Blendet einen Task aus „Im Blick" aus (für heute) bzw. entfernt den Pin.
Future<void> hideFromDashboard(AppDatabase db, String taskId) async {
  await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
    TasksCompanion(
      dashboardPinned: const drift.Value(false),
      dashboardDismissedAt: drift.Value(DateTime.now()),
    ),
  );
}

// ── Techniker-Filter ──────────────────────────────────────────────────────────

/// true = nur eigene Tasks + unzugewiesene; false = alle
final ownTasksOnlyProvider = StateProvider<bool>((ref) => true);

/// Alle bekannten Techniker-Namen aus Tasks (für Filter-Dropdown).
final knownTechniciansProvider = FutureProvider<List<String>>((ref) async {
  final tasks = await ref.watch(tasksProvider.future);
  final names = tasks
      .map((t) => t.task.assignedTo)
      .whereType<String>()
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return names;
});

/// Gibt Tasks zurück, gefiltert nach Techniker.
/// [technicianName] == null → zeigt unzugewiesene + eigene Tasks.
List<TaskWithDetails> filterByTechnician(
  List<TaskWithDetails> tasks,
  String? technicianName, {
  bool ownOnly = true,
}) {
  if (!ownOnly || technicianName == null || technicianName.isEmpty) return tasks;
  return tasks
      .where((t) =>
          t.task.assignedTo == null ||
          t.task.assignedTo!.isEmpty ||
          t.task.assignedTo == technicianName)
      .toList();
}

/// Tasks anderer Techniker (für Dashboard-Zusatzabschnitt).
List<TaskWithDetails> otherTechnicianTasks(
  List<TaskWithDetails> tasks,
  String? technicianName,
) {
  if (technicianName == null || technicianName.isEmpty) return [];
  return tasks
      .where((t) =>
          t.task.assignedTo != null &&
          t.task.assignedTo!.isNotEmpty &&
          t.task.assignedTo != technicianName)
      .toList();
}
