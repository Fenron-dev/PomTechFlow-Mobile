import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// ─── Tabellen ────────────────────────────────────────────────────────────────

class Customers extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get status => text().withDefault(const Constant('PLANNED'))();
  // Status: PLANNED | ACTIVE | PAUSED | COMPLETED
  IntColumn get totalMinutes => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Sessions extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get taskId => text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  IntColumn get duration => integer().withDefault(const Constant(0))(); // Minuten
  TextColumn get type => text().withDefault(const Constant('WORK'))();
  // Type: WORK | SHORT_BREAK | LONG_BREAK

  @override
  Set<Column> get primaryKey => {id};
}

class Todos extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get taskId => text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get content => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get workflowId => text().nullable()();
  TextColumn get workflowName => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Hardware extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get taskId => text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()();
  // Type: PC | LAPTOP | MONITOR | PRINTER | ROUTER | SWITCH | SERVER | PHONE | TABLET | OTHER
  TextColumn get name => text().nullable()();
  TextColumn get serial => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get taskId => text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Workflows extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class WorkflowItems extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get workflowId => text().references(Workflows, #id, onDelete: KeyAction.cascade)();
  TextColumn get itemText => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class WorkflowCustomers extends Table {
  TextColumn get workflowId => text().references(Workflows, #id, onDelete: KeyAction.cascade)();
  TextColumn get customerId => text().references(Customers, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {workflowId, customerId};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

// ─── Datenbank ────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [
  Customers,
  Tasks,
  Sessions,
  Todos,
  Hardware,
  Notes,
  Workflows,
  WorkflowItems,
  WorkflowCustomers,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'pomtechflow.db');
  }
}

// ─── UUID Helper ──────────────────────────────────────────────────────────────

String _uuid() {
  // Simple UUID v4 ohne externes Package
  final now = DateTime.now().microsecondsSinceEpoch;
  final rand = now ^ (now >> 16);
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replaceAllMapped(
    RegExp(r'[xy]'),
    (m) {
      final r = (rand + m.start * 7) % 16;
      final v = m.group(0) == 'x' ? r : (r & 0x3 | 0x8);
      return v.toRadixString(16);
    },
  );
}
