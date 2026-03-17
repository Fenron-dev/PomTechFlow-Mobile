import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database.dart';

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

    return {
      'version': 1,
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
    };
  }

  static Future<void> exportBackup(AppDatabase db) async {
    final json = const JsonEncoder.withIndent('  ')
        .convert(await _buildBackupMap(db));
    final dateStr = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final fileName = 'pomtechflow_backup_$dateStr.json';

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(json);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'PomTechFlow Backup $dateStr',
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

  static Future<String> importBackup(AppDatabase db) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return 'Abgebrochen';

    final filePath = result.files.single.path;
    if (filePath == null) return 'Datei konnte nicht gelesen werden';

    final Map<String, dynamic> backup;
    try {
      final json = await File(filePath).readAsString();
      backup = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return 'Ungültige Backup-Datei (kein gültiges JSON)';
    }

    final version = backup['version'] as int? ?? 0;
    if (version != 1) return 'Unbekanntes Backup-Format (Version $version)';

    try {
      await db.transaction(() async {
        // Settings
        for (final s in (backup['settings'] as List)) {
          await db.into(db.appSettings).insertOnConflictUpdate(
              AppSettingsCompanion.insert(key: s['key'], value: s['value']));
        }

        // Customers
        await db.delete(db.customers).go();
        for (final c in (backup['customers'] as List)) {
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
        for (final w in (backup['workflows'] as List)) {
          await db.into(db.workflows).insertOnConflictUpdate(WorkflowsCompanion(
            id: Value(w['id']),
            name: Value(w['name']),
            description: Value(w['description']),
          ));
        }
        await db.delete(db.workflowItems).go();
        for (final i in (backup['workflowItems'] as List)) {
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
        for (final t in (backup['tasks'] as List)) {
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
            createdAt: Value(DateTime.tryParse(t['createdAt'] ?? '') ?? DateTime.now()),
            updatedAt: Value(DateTime.tryParse(t['updatedAt'] ?? '') ?? DateTime.now()),
          ));
        }

        // Todos
        await db.delete(db.todos).go();
        for (final t in (backup['todos'] as List)) {
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
        for (final h in (backup['hardware'] as List)) {
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
        for (final n in (backup['notes'] as List)) {
          await db.into(db.notes).insertOnConflictUpdate(NotesCompanion(
            id: Value(n['id']),
            taskId: Value(n['taskId']),
            content: Value(n['content']),
            createdAt: Value(DateTime.tryParse(n['createdAt'] ?? '') ?? DateTime.now()),
          ));
        }

        // Sessions
        await db.delete(db.sessions).go();
        for (final s in (backup['sessions'] as List)) {
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
      });
    } catch (e) {
      return 'Fehler beim Importieren: $e';
    }

    return 'OK';
  }
}
