import 'dart:math';
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
  DateTimeColumn get plannedDate => dateTime().nullable()(); // NEU v2
  TextColumn get priority => text().withDefault(const Constant('NORMAL'))(); // NEU v6: LOW|NORMAL|HIGH|CRITICAL
  BoolColumn get recurring => boolean().withDefault(const Constant(false))(); // NEU v4
  TextColumn get recurrenceType => text().nullable()(); // DAILY|WEEKLY|MONTHLY|QUARTERLY
  IntColumn get recurrenceInterval => integer().withDefault(const Constant(1))(); // alle N Einheiten
  IntColumn get recurrenceWeekday => integer().nullable()(); // 1=Mo..7=So (für WEEKLY) NEU v7
  IntColumn get recurrenceMonthDay => integer().nullable()(); // 1..31 (für MONTHLY, z.B. "jeden 1.") NEU v7
  IntColumn get estimatedMinutes => integer().nullable()(); // NEU v9: Zeitbudget
  DateTimeColumn get billedAt => dateTime().nullable()(); // NEU v9: null=offen, gesetzt=abgerechnet am Datum
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
  TextColumn get note => text().nullable()();

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

class Photos extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get taskId => text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get filePath => text()();
  TextColumn get caption => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class HardwareBundles extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class HardwareBundleItems extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get bundleId => text().references(HardwareBundles, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()();
  TextColumn get name => text().nullable()();
  TextColumn get serial => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class TaskTemplates extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get workflowId => text().nullable()();
  TextColumn get hardwareBundleId => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskTemplateWorkflows extends Table {
  TextColumn get templateId =>
      text().references(TaskTemplates, #id, onDelete: KeyAction.cascade)();
  TextColumn get workflowId => text()();

  @override
  Set<Column> get primaryKey => {templateId, workflowId};
}

class TaskTemplateTodos extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get templateId =>
      text().references(TaskTemplates, #id, onDelete: KeyAction.cascade)();
  TextColumn get content => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskLinks extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get taskId =>
      text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get linkedTaskId => text()(); // soft ref — cascade via app logic
  TextColumn get linkType => text().withDefault(const Constant('RELATED'))();
  // RELATED | BLOCKS | FOLLOW_UP
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class DevicePresets extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get type => text()();
  // Type: PC | LAPTOP | MONITOR | PRINTER | ROUTER | SWITCH | SERVER | PHONE | TABLET | OTHER
  TextColumn get name => text()();
  TextColumn get serial => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── Datenbank ────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [
  Customers,
  Tasks,
  Sessions,
  Todos,
  Hardware,
  Notes,
  Photos,
  Workflows,
  WorkflowItems,
  WorkflowCustomers,
  HardwareBundles,
  HardwareBundleItems,
  AppSettings,
  DevicePresets,
  TaskTemplates,
  TaskTemplateWorkflows,
  TaskTemplateTodos,
  TaskLinks,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v1 → v2: plannedDate, Photos, HardwareBundles, HardwareBundleItems
        await m.addColumn(tasks, tasks.plannedDate);
        await m.createTable(photos);
        await m.createTable(hardwareBundles);
        await m.createTable(hardwareBundleItems);
      }
      if (from < 3) {
        // v2 → v3: DevicePresets (Geräte-Bibliothek)
        await m.createTable(devicePresets);
      }
      if (from < 4) {
        // v3 → v4: Recurring Tasks + Task-Vorlagen
        await m.addColumn(tasks, tasks.recurring);
        await m.addColumn(tasks, tasks.recurrenceType);
        await m.addColumn(tasks, tasks.recurrenceInterval);
        await m.createTable(taskTemplates);
      }
      if (from < 5) {
        // v4 → v5: Session-Notiz
        await m.addColumn(sessions, sessions.note);
      }
      if (from < 6) {
        // v5 → v6: Task-Priorität
        await m.addColumn(tasks, tasks.priority);
      }
      if (from < 7) {
        // v6 → v7: Wochentag & Monatstag für Wiederholung
        await m.addColumn(tasks, tasks.recurrenceWeekday);
        await m.addColumn(tasks, tasks.recurrenceMonthDay);
      }
      if (from < 8) {
        // v7 → v8: Template multi-workflow + custom todos
        await m.createTable(taskTemplateWorkflows);
        await m.createTable(taskTemplateTodos);
      }
      if (from < 9) {
        // v8 → v9: Zeitbudget, Abrechnungsstatus, Task-Verknüpfungen
        await m.addColumn(tasks, tasks.estimatedMinutes);
        await m.addColumn(tasks, tasks.billedAt);
        await m.createTable(taskLinks);
      }
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'pomtechflow.db');
  }
}

// ─── UUID Helper ──────────────────────────────────────────────────────────────

String _uuid() {
  // UUID v4 mit kryptographisch sicherem Zufallsgenerator
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
}
