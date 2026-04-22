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
  // Strukturierte Adressfelder (kompatibel mit WaWi-Schema). v15+
  // Die alte address-Spalte bleibt als Legacy in der DB (SQLite DROP nicht möglich).
  TextColumn get street => text().nullable()();
  TextColumn get houseNumber => text().nullable()();
  TextColumn get zipCode => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ansprechpartner eines Kunden — kompatibel mit WaWi-Contacts-Schema.
class Contacts extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get customerId =>
      text().references(Customers, #id, onDelete: KeyAction.cascade)();
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  TextColumn get position => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phoneLandline => text().nullable()();
  TextColumn get phoneMobile => text().nullable()();
  TextColumn get location => text().nullable()(); // Standort / Büro
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)();

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
  DateTimeColumn get archivedAt => dateTime().nullable()(); // NEU v11: null=aktiv, gesetzt=archiviert
  IntColumn get reminderOffsetMinutes => integer().nullable()(); // NEU v13: Erinnerungsvorlauf in Minuten vor plannedDate
  TextColumn get assignedTo => text().nullable()(); // v17: Zugewiesener Techniker
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
  BoolColumn get remote => boolean().withDefault(const Constant(false))(); // v14: false=Vor Ort, true=Fernwartung
  TextColumn get note => text().nullable()();
  // v16: Techniker-Name (denormalisiert für Multi-Techniker-Sync)
  TextColumn get technicianName => text().withDefault(const Constant(''))();
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)();

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
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

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
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get taskId => text().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

  @override
  Set<Column> get primaryKey => {id};
}

class Workflows extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

  @override
  Set<Column> get primaryKey => {id};
}

class WorkflowItems extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get workflowId => text().references(Workflows, #id, onDelete: KeyAction.cascade)();
  TextColumn get itemText => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

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
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

  @override
  Set<Column> get primaryKey => {id};
}

class HardwareBundles extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

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
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

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
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

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
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

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
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

  @override
  Set<Column> get primaryKey => {id};
}

class GeneralNotes extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get content => text()();
  TextColumn get tags => text().nullable()(); // kommagetrennte Tags, z.B. "linux,on/linux/install"
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteTemplates extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get name => text()(); // Anzeigename der Vorlage
  TextColumn get content => text()(); // Vorlagen-Inhalt (kann Platzhalter wie [Problem] enthalten)
  TextColumn get tags => text().nullable()(); // kommagetrennte Vorausfüll-Tags
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

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
  IntColumn get maintenanceIntervalDays => integer().nullable()(); // v14: Wartungsintervall in Tagen
  DateTimeColumn get lastMaintenanceDate => dateTime().nullable()(); // v14: Datum der letzten Wartungs-Task-Erstellung
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)(); // v16

  @override
  Set<Column> get primaryKey => {id};
}

class KnowledgeEntries extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  TextColumn get title => text()(); // Kurztitel / Symptom
  TextColumn get problem => text()(); // Problembeschreibung
  TextColumn get solution => text()(); // Lösungstext (Markdown)
  TextColumn get tags => text().nullable()(); // kommagetrennte Tags
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// v16: Tombstone-Tabelle — erfasst gelöschte Entities für Sync-Propagierung
class SyncDeletions extends Table {
  TextColumn get id => text().clientDefault(() => _uuid())();
  // Tabellenname in snake_case, z.B. 'tasks', 'sessions', 'customers'
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get deletedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get deletedByDeviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {entityType, entityId};
}

// v16: Speichert Sync-Status pro Peer (Server aus Client-Perspektive)
class SyncState extends Table {
  // UUID des Server-Geräts
  TextColumn get peerId => text()();
  TextColumn get peerName => text().nullable()();
  DateTimeColumn get lastPullAt => dateTime().nullable()();
  DateTimeColumn get lastPushAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {peerId};
}

// ─── Datenbank ────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [
  Customers,
  Contacts,
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
  GeneralNotes,
  NoteTemplates,
  KnowledgeEntries,
  SyncDeletions,
  SyncState,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 17;

  // ── Migration helpers ────────────────────────────────────────────────────────

  Future<bool> _hasColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    return rows.any((r) => (r.data['name'] as String?) == column);
  }

  Future<bool> _hasTable(String table) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'",
    ).get();
    return rows.isNotEmpty;
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Every step is guarded with _hasColumn/_hasTable to survive partial
      // migrations caused by earlier crashes where user_version was not updated.
      if (from < 2) {
        if (!await _hasColumn('tasks', 'planned_date'))
          await m.addColumn(tasks, tasks.plannedDate);
        if (!await _hasTable('photos')) await m.createTable(photos);
        if (!await _hasTable('hardware_bundles'))
          await m.createTable(hardwareBundles);
        if (!await _hasTable('hardware_bundle_items'))
          await m.createTable(hardwareBundleItems);
      }
      if (from < 3) {
        if (!await _hasTable('device_presets'))
          await m.createTable(devicePresets);
      }
      if (from < 4) {
        if (!await _hasColumn('tasks', 'recurring'))
          await m.addColumn(tasks, tasks.recurring);
        if (!await _hasColumn('tasks', 'recurrence_type'))
          await m.addColumn(tasks, tasks.recurrenceType);
        if (!await _hasColumn('tasks', 'recurrence_interval'))
          await m.addColumn(tasks, tasks.recurrenceInterval);
        if (!await _hasTable('task_templates'))
          await m.createTable(taskTemplates);
      }
      if (from < 5) {
        if (!await _hasColumn('sessions', 'note'))
          await m.addColumn(sessions, sessions.note);
      }
      if (from < 6) {
        if (!await _hasColumn('tasks', 'priority'))
          await m.addColumn(tasks, tasks.priority);
      }
      if (from < 7) {
        if (!await _hasColumn('tasks', 'recurrence_weekday'))
          await m.addColumn(tasks, tasks.recurrenceWeekday);
        if (!await _hasColumn('tasks', 'recurrence_month_day'))
          await m.addColumn(tasks, tasks.recurrenceMonthDay);
      }
      if (from < 8) {
        if (!await _hasTable('task_template_workflows'))
          await m.createTable(taskTemplateWorkflows);
        if (!await _hasTable('task_template_todos'))
          await m.createTable(taskTemplateTodos);
      }
      if (from < 9) {
        if (!await _hasColumn('tasks', 'estimated_minutes'))
          await m.addColumn(tasks, tasks.estimatedMinutes);
        if (!await _hasColumn('tasks', 'billed_at'))
          await m.addColumn(tasks, tasks.billedAt);
        if (!await _hasTable('task_links')) await m.createTable(taskLinks);
      }
      if (from < 10) {
        if (!await _hasTable('general_notes'))
          await m.createTable(generalNotes);
      }
      if (from < 11) {
        if (!await _hasColumn('tasks', 'archived_at'))
          await m.addColumn(tasks, tasks.archivedAt);
      }
      if (from < 12) {
        if (!await _hasTable('note_templates'))
          await m.createTable(noteTemplates);
      }
      if (from < 13) {
        if (!await _hasColumn('tasks', 'reminder_offset_minutes'))
          await m.addColumn(tasks, tasks.reminderOffsetMinutes);
      }
      if (from < 14) {
        if (!await _hasColumn('sessions', 'remote'))
          await m.addColumn(sessions, sessions.remote);
        if (!await _hasColumn('device_presets', 'maintenance_interval_days'))
          await m.addColumn(devicePresets, devicePresets.maintenanceIntervalDays);
        if (!await _hasColumn('device_presets', 'last_maintenance_date'))
          await m.addColumn(devicePresets, devicePresets.lastMaintenanceDate);
        if (!await _hasTable('knowledge_entries'))
          await m.createTable(knowledgeEntries);
      }
      if (from < 15) {
        if (!await _hasColumn('customers', 'street'))
          await m.addColumn(customers, customers.street);
        if (!await _hasColumn('customers', 'house_number'))
          await m.addColumn(customers, customers.houseNumber);
        if (!await _hasColumn('customers', 'zip_code'))
          await m.addColumn(customers, customers.zipCode);
        if (!await _hasColumn('customers', 'city'))
          await m.addColumn(customers, customers.city);
        if (!await _hasColumn('customers', 'is_active'))
          await m.addColumn(customers, customers.isActive);
        if (!await _hasColumn('customers', 'modified_at'))
          await customStatement(
              'ALTER TABLE "customers" ADD COLUMN "modified_at" INTEGER NOT NULL DEFAULT 0');
        if (!await _hasTable('contacts')) await m.createTable(contacts);
        // Address migration: idempotent UPDATE — safe to repeat.
        await customStatement('''
          UPDATE customers
          SET
            street   = CASE WHEN instr(COALESCE(address,''), '||') > 0
                            THEN substr(address, 1, instr(address,'||')-1)
                            ELSE address END,
            zip_code = CASE WHEN length(COALESCE(address,'')) - length(replace(COALESCE(address,''),'||','')) >= 2
                            THEN trim(substr(
                              substr(address, instr(address,'||')+2),
                              1,
                              instr(substr(address, instr(address,'||')+2),'||')-1
                            ))
                            ELSE NULL END,
            city     = CASE WHEN length(COALESCE(address,'')) - length(replace(COALESCE(address,''),'||','')) >= 2
                            THEN trim(substr(
                              address,
                              instr(address,'||') + 2 +
                              instr(substr(address, instr(address,'||')+2),'||')
                            ))
                            ELSE NULL END
          WHERE address IS NOT NULL AND street IS NULL
        ''');
      }
      if (from < 16) {
        if (!await _hasColumn('sessions', 'technician_name'))
          await m.addColumn(sessions, sessions.technicianName);
        if (!await _hasColumn('sessions', 'modified_at'))
          await customStatement(
              'ALTER TABLE "sessions" ADD COLUMN "modified_at" INTEGER NOT NULL DEFAULT 0');
        await customStatement('''
          UPDATE sessions
          SET technician_name = COALESCE(
            (SELECT value FROM app_settings WHERE key = 'technicianName'), ''
          )
          WHERE technician_name = ''
        ''');
        for (final t in [
          'todos', 'hardware', 'notes', 'photos', 'workflows',
          'workflow_items', 'hardware_bundles', 'hardware_bundle_items',
          'task_templates', 'task_template_todos', 'task_links', 'device_presets',
        ]) {
          if (!await _hasColumn(t, 'modified_at'))
            await customStatement(
                'ALTER TABLE "$t" ADD COLUMN "modified_at" INTEGER NOT NULL DEFAULT 0');
        }
        if (!await _hasTable('sync_deletions'))
          await m.createTable(syncDeletions);
        if (!await _hasTable('sync_state'))
          await m.createTable(syncState);
      }
      if (from < 17) {
        // v16 → v17: Techniker-Zuweisung auf Tasks
        if (!await _hasColumn('tasks', 'assigned_to'))
          await m.addColumn(tasks, tasks.assignedTo);
      }
    },
  );

  /// Löscht eine Entity und trägt sie in SyncDeletions ein (Tombstone).
  /// Immer statt direktem db.delete() für sync-relevante Tabellen verwenden.
  Future<void> softDeleteEntity(
    String entityType,
    String entityId, {
    String? deviceId,
  }) async {
    await into(syncDeletions).insertOnConflictUpdate(SyncDeletionsCompanion(
      entityType: Value(entityType),
      entityId: Value(entityId),
      deletedAt: Value(DateTime.now()),
      deletedByDeviceId: Value(deviceId),
    ));
  }

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
