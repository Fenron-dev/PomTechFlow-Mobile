import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database.dart';
import 'crypto_service.dart';

/// Sentinel returned by [importBackup] when the file is encrypted but no
/// password was provided.  The caller should prompt for a password and retry.
const String kNeedsPassword = 'NEEDS_PASSWORD';

/// Sentinel returned when the supplied password is wrong.
const String kWrongPassword = 'WRONG_PASSWORD';

class BackupService {
  static Future<Map<String, dynamic>> _buildBackupMap(AppDatabase db) async {
    final customers = await db.select(db.customers).get();
    final tasks = await db.select(db.tasks).get();
    final todos = await db.select(db.todos).get();
    final hardware = await db.select(db.hardware).get();
    final notes = await db.select(db.notes).get();
    final sessions = await db.select(db.sessions).get();
    final workflows = await db.select(db.workflows).get();
    final workflowItems = await db.select(db.workflowItems).get();
    final appSettings = await db.select(db.appSettings).get();
    final generalNotes = await db.select(db.generalNotes).get();
    final noteTemplates = await db.select(db.noteTemplates).get();

    return {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'customers': customers.map((c) => {
        'id': c.id, 'name': c.name, 'email': c.email,
        'phone': c.phone, 'address': c.address, 'notes': c.notes,
        'createdAt': c.createdAt.toIso8601String(),
      }).toList(),
      'tasks': tasks.map((t) => {
        'id': t.id, 'title': t.title, 'description': t.description,
        'status': t.status, 'customerId': t.customerId,
        'priority': t.priority, 'totalMinutes': t.totalMinutes,
        'plannedDate': t.plannedDate?.toIso8601String(),
        'recurring': t.recurring,
        'recurrenceType': t.recurrenceType,
        'recurrenceInterval': t.recurrenceInterval,
        'recurrenceWeekday': t.recurrenceWeekday,
        'recurrenceMonthDay': t.recurrenceMonthDay,
        'estimatedMinutes': t.estimatedMinutes,
        'billedAt': t.billedAt?.toIso8601String(),
        'archivedAt': t.archivedAt?.toIso8601String(),
        'createdAt': t.createdAt.toIso8601String(),
        'updatedAt': t.updatedAt.toIso8601String(),
      }).toList(),
      'todos': todos.map((t) => {
        'id': t.id, 'taskId': t.taskId, 'content': t.content,
        'completed': t.completed, 'sortOrder': t.sortOrder,
        'workflowId': t.workflowId, 'workflowName': t.workflowName,
      }).toList(),
      'hardware': hardware.map((h) => {
        'id': h.id, 'taskId': h.taskId, 'type': h.type,
        'name': h.name, 'serial': h.serial, 'notes': h.notes,
      }).toList(),
      'notes': notes.map((n) => {
        'id': n.id, 'taskId': n.taskId, 'content': n.content,
        'createdAt': n.createdAt.toIso8601String(),
      }).toList(),
      'sessions': sessions.map((s) => {
        'id': s.id, 'taskId': s.taskId, 'duration': s.duration,
        'type': s.type, 'note': s.note,
        'startTime': s.startTime.toIso8601String(),
        'endTime': s.endTime?.toIso8601String(),
      }).toList(),
      'workflows': workflows.map((w) => {
        'id': w.id, 'name': w.name, 'description': w.description,
      }).toList(),
      'workflowItems': workflowItems.map((i) => {
        'id': i.id, 'workflowId': i.workflowId,
        'itemText': i.itemText, 'sortOrder': i.sortOrder,
      }).toList(),
      'settings': appSettings.map((s) => {
        'key': s.key, 'value': s.value,
      }).toList(),
      'generalNotes': generalNotes.map((n) => {
        'id': n.id, 'content': n.content, 'tags': n.tags,
        'createdAt': n.createdAt.toIso8601String(),
        'updatedAt': n.updatedAt.toIso8601String(),
      }).toList(),
      'noteTemplates': noteTemplates.map((t) => {
        'id': t.id, 'name': t.name, 'content': t.content, 'tags': t.tags,
        'createdAt': t.createdAt.toIso8601String(),
        'updatedAt': t.updatedAt.toIso8601String(),
      }).toList(),
    };
  }

  /// Returns the raw backup JSON string (e.g. for WebDAV upload).
  static Future<String> buildJsonString(AppDatabase db) async =>
      const JsonEncoder.withIndent('  ').convert(await _buildBackupMap(db));

  /// Imports a backup directly from a JSON string (e.g. downloaded from WebDAV).
  /// Returns 'OK' on success or a human-readable error message.
  static Future<String> importFromString(AppDatabase db, String rawJson) async {
    final Map<String, dynamic> backup;
    try {
      backup = jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (_) {
      return 'Ungültige Backup-Datei (kein gültiges JSON)';
    }
    final version = backup['version'] as int? ?? 0;
    if (version < 1 || version > 2) return 'Unbekanntes Backup-Format (Version $version)';
    try {
      await _applyBackup(db, backup);
    } catch (e) {
      return 'Fehler beim Importieren: $e';
    }
    return 'OK';
  }

  /// Exports a full backup and opens the system share sheet.
  /// If [password] is non-empty the backup is AES-256 encrypted.
  static Future<void> exportBackup(AppDatabase db, {String? password}) async {
    String content = const JsonEncoder.withIndent('  ')
        .convert(await _buildBackupMap(db));

    final encrypted = password != null && password.isNotEmpty;
    if (encrypted) {
      content = CryptoService.encryptBackup(content, password);
    }

    final dateStr = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final suffix = encrypted ? '_enc' : '';
    final fileName = 'pomtechflow_backup_$dateStr$suffix.json';

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'PomTechFlow Backup $dateStr${encrypted ? " (verschlüsselt)" : ""}',
    );
  }

  /// Saves backup directly to [dirPath] without a share sheet.
  /// Returns the saved file path, or throws on error.
  /// Deletes backups in [dirPath] older than [keepDays] days.
  static Future<String> exportBackupToDir(
    AppDatabase db,
    String dirPath, {
    int keepDays = 7,
  }) async {
    final json = const JsonEncoder.withIndent('  ').convert(
      await _buildBackupMap(db),
    );
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fileName = 'pomtechflow_backup_$dateStr.json';
    final file = File('$dirPath/$fileName');
    await file.writeAsString(json);

    // Clean up old backups
    try {
      final dir = Directory(dirPath);
      final cutoff = DateTime.now().subtract(Duration(days: keepDays));
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.path.contains('pomtechflow_backup_') &&
            entity.path.endsWith('.json')) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        }
      }
    } catch (_) {
      // Cleanup failure is non-fatal
    }

    return file.path;
  }

  /// Imports a backup from a user-picked file.
  ///
  /// Returns:
  /// - `'OK'`              on success
  /// - `'Abgebrochen'`     when the user cancelled the picker
  /// - [kNeedsPassword]    when the file is encrypted and no [password] was supplied
  /// - [kWrongPassword]    when the supplied [password] is incorrect
  /// - any other string    is a human-readable error message
  static Future<String> importBackup(AppDatabase db, {String? password}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true, // iOS: temp paths vanish; read bytes directly
    );
    if (result == null || result.files.isEmpty) return 'Abgebrochen';

    final picked = result.files.single;
    String rawJson;
    try {
      if (picked.bytes != null) {
        rawJson = utf8.decode(picked.bytes!);
      } else if (picked.path != null) {
        rawJson = await File(picked.path!).readAsString();
      } else {
        return 'Datei konnte nicht gelesen werden';
      }
    } catch (_) {
      return 'Datei konnte nicht gelesen werden';
    }

    // Encrypted backup?
    if (CryptoService.isEncrypted(rawJson)) {
      if (password == null || password.isEmpty) return kNeedsPassword;
      try {
        rawJson = CryptoService.decryptBackup(rawJson, password);
      } on WrongPasswordException {
        return kWrongPassword;
      } catch (_) {
        return kWrongPassword;
      }
    }

    final Map<String, dynamic> backup;
    try {
      backup = jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (_) {
      return 'Ungültige Backup-Datei (kein gültiges JSON)';
    }

    final version = backup['version'] as int? ?? 0;
    if (version < 1 || version > 2) return 'Unbekanntes Backup-Format (Version $version)';

    try {
      await _applyBackup(db, backup);
    } catch (e) {
      return 'Fehler beim Importieren: $e';
    }
    return 'OK';
  }

  /// Validates required fields in a parsed backup map.
  /// Returns null on success or a human-readable error string on failure.
  /// Called BEFORE any database modification so no data is ever at risk.
  static String? _validateBackup(Map<String, dynamic> backup) {
    String? checkList(String key, List<String> required) {
      final list = backup[key];
      if (list == null) { return null; } // optional section
      if (list is! List) { return '$key muss eine Liste sein'; }
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is! Map) { return '$key[$i]: kein Objekt'; }
        for (final field in required) {
          if (item[field] == null) {
            return '$key[$i]: Pflichtfeld "$field" fehlt oder ist null';
          }
        }
      }
      return null;
    }

    return checkList('customers', ['id', 'name']) ??
        checkList('tasks', ['id', 'title', 'status', 'priority']) ??
        checkList('todos', ['id', 'taskId', 'content']) ??
        checkList('hardware', ['id', 'taskId', 'type']) ??
        checkList('notes', ['id', 'taskId', 'content']) ??
        checkList('sessions', ['id', 'taskId', 'startTime']) ??
        checkList('workflows', ['id', 'name']) ??
        checkList('workflowItems', ['id', 'workflowId', 'itemText']) ??
        checkList('generalNotes', ['id', 'content']) ??
        checkList('noteTemplates', ['id', 'name', 'content']);
  }

  /// Applies a parsed backup map to the database inside a transaction.
  static Future<void> _applyBackup(
      AppDatabase db, Map<String, dynamic> backup) async {
    // Validate structure before touching the database — fast, no side effects.
    final validationError = _validateBackup(backup);
    if (validationError != null) {
      throw Exception('Backup-Validierung fehlgeschlagen: $validationError');
    }

    await db.transaction(() async {
      // Settings
      for (final s in (backup['settings'] as List? ?? [])) {
        await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: s['key'], value: s['value']));
      }

      // Customers
      await db.delete(db.customers).go();
      for (final c in (backup['customers'] as List? ?? [])) {
        await db.into(db.customers).insertOnConflictUpdate(CustomersCompanion(
          id: Value(c['id']),
          name: Value(c['name']),
          email: Value(c['email']),
          phone: Value(c['phone']),
          address: Value(c['address']),
          notes: Value(c['notes']),
          createdAt: Value(DateTime.tryParse(c['createdAt'] ?? '') ?? DateTime.now()),
        ));
      }

      // Workflows
      await db.delete(db.workflows).go();
      for (final w in (backup['workflows'] as List? ?? [])) {
        await db.into(db.workflows).insertOnConflictUpdate(WorkflowsCompanion(
          id: Value(w['id']),
          name: Value(w['name']),
          description: Value(w['description']),
        ));
      }
      await db.delete(db.workflowItems).go();
      for (final i in (backup['workflowItems'] as List? ?? [])) {
        await db.into(db.workflowItems).insertOnConflictUpdate(
            WorkflowItemsCompanion(
          id: Value(i['id']),
          workflowId: Value(i['workflowId']),
          itemText: Value(i['itemText']),
          sortOrder: Value(i['sortOrder'] ?? 0),
        ));
      }

      // Tasks
      await db.delete(db.tasks).go();
      for (final t in (backup['tasks'] as List? ?? [])) {
        await db.into(db.tasks).insertOnConflictUpdate(TasksCompanion(
          id: Value(t['id']),
          title: Value(t['title']),
          description: Value(t['description']),
          status: Value(t['status']),
          customerId: Value(t['customerId']),
          priority: Value(t['priority'] ?? 'NORMAL'),
          totalMinutes: Value(t['totalMinutes'] ?? 0),
          plannedDate: Value(t['plannedDate'] != null
              ? DateTime.tryParse(t['plannedDate'])
              : null),
          recurring: Value(t['recurring'] ?? false),
          recurrenceType: Value(t['recurrenceType']),
          recurrenceInterval: Value(t['recurrenceInterval'] ?? 1),
          recurrenceWeekday: Value(t['recurrenceWeekday']),
          recurrenceMonthDay: Value(t['recurrenceMonthDay']),
          estimatedMinutes: Value(t['estimatedMinutes']),
          billedAt: Value(t['billedAt'] != null
              ? DateTime.tryParse(t['billedAt'])
              : null),
          archivedAt: Value(t['archivedAt'] != null
              ? DateTime.tryParse(t['archivedAt'])
              : null),
          createdAt: Value(DateTime.tryParse(t['createdAt'] ?? '') ?? DateTime.now()),
          updatedAt: Value(DateTime.tryParse(t['updatedAt'] ?? '') ?? DateTime.now()),
        ));
      }

      // Todos
      await db.delete(db.todos).go();
      for (final t in (backup['todos'] as List? ?? [])) {
        await db.into(db.todos).insertOnConflictUpdate(TodosCompanion(
          id: Value(t['id']),
          taskId: Value(t['taskId']),
          content: Value(t['content']),
          completed: Value(t['completed'] ?? false),
          sortOrder: Value(t['sortOrder'] ?? 0),
          workflowId: Value(t['workflowId']),
          workflowName: Value(t['workflowName']),
        ));
      }

      // Hardware
      await db.delete(db.hardware).go();
      for (final h in (backup['hardware'] as List? ?? [])) {
        await db.into(db.hardware).insertOnConflictUpdate(HardwareCompanion(
          id: Value(h['id']),
          taskId: Value(h['taskId']),
          type: Value(h['type']),
          name: Value(h['name']),
          serial: Value(h['serial']),
          notes: Value(h['notes']),
        ));
      }

      // Notes
      await db.delete(db.notes).go();
      for (final n in (backup['notes'] as List? ?? [])) {
        await db.into(db.notes).insertOnConflictUpdate(NotesCompanion(
          id: Value(n['id']),
          taskId: Value(n['taskId']),
          content: Value(n['content']),
          createdAt: Value(DateTime.tryParse(n['createdAt'] ?? '') ?? DateTime.now()),
        ));
      }

      // Sessions
      await db.delete(db.sessions).go();
      for (final s in (backup['sessions'] as List? ?? [])) {
        await db.into(db.sessions).insertOnConflictUpdate(SessionsCompanion(
          id: Value(s['id']),
          taskId: Value(s['taskId']),
          duration: Value(s['duration'] ?? 0),
          type: Value(s['type'] ?? 'WORK'),
          note: Value(s['note']),
          startTime: Value(DateTime.tryParse(s['startTime'] ?? '') ?? DateTime.now()),
          endTime: Value(s['endTime'] != null
              ? DateTime.tryParse(s['endTime'])
              : null),
        ));
      }

      // Allgemeine Notizen
      await db.delete(db.generalNotes).go();
      for (final n in (backup['generalNotes'] as List? ?? [])) {
        await db.into(db.generalNotes).insertOnConflictUpdate(
            GeneralNotesCompanion(
          id: Value(n['id']),
          content: Value(n['content']),
          tags: Value(n['tags']),
          createdAt: Value(DateTime.tryParse(n['createdAt'] ?? '') ?? DateTime.now()),
          updatedAt: Value(DateTime.tryParse(n['updatedAt'] ?? '') ?? DateTime.now()),
        ));
      }

      // Notiz-Vorlagen
      await db.delete(db.noteTemplates).go();
      for (final t in (backup['noteTemplates'] as List? ?? [])) {
        await db.into(db.noteTemplates).insertOnConflictUpdate(
            NoteTemplatesCompanion(
          id: Value(t['id']),
          name: Value(t['name']),
          content: Value(t['content']),
          tags: Value(t['tags']),
          createdAt: Value(DateTime.tryParse(t['createdAt'] ?? '') ?? DateTime.now()),
          updatedAt: Value(DateTime.tryParse(t['updatedAt'] ?? '') ?? DateTime.now()),
        ));
      }
    });
  }
}
