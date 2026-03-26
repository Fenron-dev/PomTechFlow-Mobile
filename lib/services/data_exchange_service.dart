import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../db/database.dart';
import 'package:drift/drift.dart' as drift;

class DataExchangeService {
  /// Exportiert ausgewählte Datenkategorien als JSON-Datei und teilt sie.
  static Future<void> exportData(
    AppDatabase db, {
    bool customers = true,
    bool workflows = true,
    bool hardwareBundles = true,
    bool generalNotes = false,
    bool noteTemplates = false,
    bool tasks = false,
  }) async {
    final Map<String, dynamic> data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'type': 'data_exchange',
    };

    if (customers) {
      final rows = await db.select(db.customers).get();
      data['customers'] = rows
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'email': c.email,
                'phone': c.phone,
                'address': c.address,
                'notes': c.notes,
              })
          .toList();
    }

    if (workflows) {
      final wfs = await db.select(db.workflows).get();
      final wfList = [];
      for (final wf in wfs) {
        final items = await (db.select(db.workflowItems)
              ..where((i) => i.workflowId.equals(wf.id))
              ..orderBy([(i) => drift.OrderingTerm.asc(i.sortOrder)]))
            .get();
        wfList.add({
          'id': wf.id,
          'name': wf.name,
          'description': wf.description,
          'items': items.map((i) => {'id': i.id, 'itemText': i.itemText, 'sortOrder': i.sortOrder}).toList(),
        });
      }
      data['workflows'] = wfList;
    }

    if (hardwareBundles) {
      final bundles = await db.select(db.hardwareBundles).get();
      final bundleList = [];
      for (final b in bundles) {
        final items = await (db.select(db.hardwareBundleItems)
              ..where((i) => i.bundleId.equals(b.id))
              ..orderBy([(i) => drift.OrderingTerm.asc(i.sortOrder)]))
            .get();
        bundleList.add({
          'id': b.id,
          'name': b.name,
          'description': b.description,
          'items': items
              .map((i) => {
                    'type': i.type,
                    'name': i.name,
                    'serial': i.serial,
                    'notes': i.notes,
                    'sortOrder': i.sortOrder,
                  })
              .toList(),
        });
      }
      data['hardwareBundles'] = bundleList;
    }

    if (generalNotes) {
      final notes = await db.select(db.generalNotes).get();
      data['generalNotes'] = notes
          .map((n) => {
                'id': n.id,
                'content': n.content,
                'tags': n.tags,
                'createdAt': n.createdAt.toIso8601String(),
                'updatedAt': n.updatedAt.toIso8601String(),
              })
          .toList();
    }

    if (noteTemplates) {
      final tmpl = await db.select(db.noteTemplates).get();
      data['noteTemplates'] = tmpl
          .map((t) => {
                'id': t.id,
                'name': t.name,
                'content': t.content,
                'tags': t.tags,
                'createdAt': t.createdAt.toIso8601String(),
                'updatedAt': t.updatedAt.toIso8601String(),
              })
          .toList();
    }

    if (tasks) {
      final taskRows = await db.select(db.tasks).get();
      final taskList = [];
      for (final t in taskRows) {
        final todos = await (db.select(db.todos)
              ..where((td) => td.taskId.equals(t.id))
              ..orderBy([(td) => drift.OrderingTerm.asc(td.sortOrder)]))
            .get();
        final hardware = await (db.select(db.hardware)
              ..where((h) => h.taskId.equals(t.id)))
            .get();
        final notes = await (db.select(db.notes)
              ..where((n) => n.taskId.equals(t.id))
              ..orderBy([(n) => drift.OrderingTerm.asc(n.createdAt)]))
            .get();
        final sessions = await (db.select(db.sessions)
              ..where((s) => s.taskId.equals(t.id))
              ..orderBy([(s) => drift.OrderingTerm.asc(s.startTime)]))
            .get();
        taskList.add({
          'id': t.id,
          'title': t.title,
          'description': t.description,
          'customerId': t.customerId,
          'status': t.status,
          'priority': t.priority,
          'totalMinutes': t.totalMinutes,
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
          'todos': todos.map((td) => {
            'id': td.id, 'content': td.content,
            'completed': td.completed, 'sortOrder': td.sortOrder,
            'workflowId': td.workflowId, 'workflowName': td.workflowName,
          }).toList(),
          'hardware': hardware.map((h) => {
            'id': h.id, 'type': h.type, 'name': h.name,
            'serial': h.serial, 'notes': h.notes,
          }).toList(),
          'notes': notes.map((n) => {
            'id': n.id, 'content': n.content,
            'createdAt': n.createdAt.toIso8601String(),
          }).toList(),
          'sessions': sessions.map((s) => {
            'id': s.id, 'duration': s.duration, 'type': s.type,
            'note': s.note,
            'startTime': s.startTime.toIso8601String(),
            'endTime': s.endTime?.toIso8601String(),
          }).toList(),
        });
      }
      data['tasks'] = taskList;
    }

    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/ptf_data_$ts.json');
    await file.writeAsString(json);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'PomTechFlow Daten',
      text: 'PomTechFlow Stammdaten-Export',
    );
  }

  /// Importiert Daten aus einer JSON-Datei. Bereits vorhandene Einträge (gleiche ID) werden übersprungen.
  static Future<DataImportResult> importData(AppDatabase db) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) {
      return DataImportResult.cancelled();
    }

    final path = result.files.first.path;
    if (path == null) return DataImportResult.cancelled();

    try {
      final content = await File(path).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      if (data['type'] != 'data_exchange') {
        return DataImportResult.error('Keine gültige Datenaustausch-Datei.');
      }

      int importedCustomers = 0;
      int importedWorkflows = 0;
      int importedBundles = 0;
      int importedNotes = 0;
      int importedTemplates = 0;
      int importedTasks = 0;

      await db.transaction(() async {
        // Kunden
        final customerList = data['customers'] as List? ?? [];
        for (final c in customerList) {
          final existing = await (db.select(db.customers)
                ..where((row) => row.id.equals(c['id'] as String)))
              .getSingleOrNull();
          if (existing == null) {
            await db.into(db.customers).insert(CustomersCompanion.insert(
                  id: drift.Value(c['id'] as String),
                  name: c['name'] as String,
                  email: drift.Value(c['email'] as String?),
                  phone: drift.Value(c['phone'] as String?),
                  address: drift.Value(c['address'] as String?),
                  notes: drift.Value(c['notes'] as String?),
                ));
            importedCustomers++;
          }
        }

        // Workflows
        final workflowList = data['workflows'] as List? ?? [];
        for (final wf in workflowList) {
          final existing = await (db.select(db.workflows)
                ..where((row) => row.id.equals(wf['id'] as String)))
              .getSingleOrNull();
          if (existing == null) {
            await db.into(db.workflows).insert(WorkflowsCompanion.insert(
                  id: drift.Value(wf['id'] as String),
                  name: wf['name'] as String,
                  description: drift.Value(wf['description'] as String?),
                ));
            for (final item in (wf['items'] as List? ?? [])) {
              await db.into(db.workflowItems).insert(
                    WorkflowItemsCompanion.insert(
                      id: drift.Value(item['id'] as String),
                      workflowId: wf['id'] as String,
                      itemText: item['itemText'] as String,
                      sortOrder: drift.Value(item['sortOrder'] as int? ?? 0),
                    ),
                  );
            }
            importedWorkflows++;
          }
        }

        // Hardware Bundles
        final bundleList = data['hardwareBundles'] as List? ?? [];
        for (final b in bundleList) {
          final existing = await (db.select(db.hardwareBundles)
                ..where((row) => row.id.equals(b['id'] as String)))
              .getSingleOrNull();
          if (existing == null) {
            await db.into(db.hardwareBundles).insert(
                  HardwareBundlesCompanion.insert(
                    id: drift.Value(b['id'] as String),
                    name: b['name'] as String,
                    description: drift.Value(b['description'] as String?),
                  ),
                );
            int sortIdx = 0;
            for (final item in (b['items'] as List? ?? [])) {
              await db.into(db.hardwareBundleItems).insert(
                    HardwareBundleItemsCompanion.insert(
                      bundleId: b['id'] as String,
                      type: item['type'] as String,
                      name: drift.Value(item['name'] as String?),
                      serial: drift.Value(item['serial'] as String?),
                      notes: drift.Value(item['notes'] as String?),
                      sortOrder: drift.Value(sortIdx++),
                    ),
                  );
            }
            importedBundles++;
          }
        }

        // Allgemeine Notizen
        final noteList = data['generalNotes'] as List? ?? [];
        for (final n in noteList) {
          final existing = await (db.select(db.generalNotes)
                ..where((row) => row.id.equals(n['id'] as String)))
              .getSingleOrNull();
          if (existing == null) {
            await db.into(db.generalNotes).insert(GeneralNotesCompanion.insert(
                  id: drift.Value(n['id'] as String),
                  content: n['content'] as String,
                  tags: drift.Value(n['tags'] as String?),
                  createdAt: drift.Value(
                    DateTime.tryParse(n['createdAt'] as String? ?? '') ??
                        DateTime.now(),
                  ),
                  updatedAt: drift.Value(
                    DateTime.tryParse(n['updatedAt'] as String? ?? '') ??
                        DateTime.now(),
                  ),
                ));
            importedNotes++;
          }
        }

        // Notiz-Vorlagen
        final templateList = data['noteTemplates'] as List? ?? [];
        for (final t in templateList) {
          final existing = await (db.select(db.noteTemplates)
                ..where((row) => row.id.equals(t['id'] as String)))
              .getSingleOrNull();
          if (existing == null) {
            await db.into(db.noteTemplates).insert(
                  NoteTemplatesCompanion.insert(
                    id: drift.Value(t['id'] as String),
                    name: t['name'] as String,
                    content: t['content'] as String,
                    tags: drift.Value(t['tags'] as String?),
                    createdAt: drift.Value(
                      DateTime.tryParse(t['createdAt'] as String? ?? '') ??
                          DateTime.now(),
                    ),
                    updatedAt: drift.Value(
                      DateTime.tryParse(t['updatedAt'] as String? ?? '') ??
                          DateTime.now(),
                    ),
                  ),
                );
            importedTemplates++;
          }
        }

        // Tasks (inkl. Todos, Hardware, Notizen, Sessions)
        final taskList = data['tasks'] as List? ?? [];
        for (final t in taskList) {
          final taskId = t['id'] as String;
          final existing = await (db.select(db.tasks)
                ..where((row) => row.id.equals(taskId)))
              .getSingleOrNull();
          if (existing == null) {
            await db.into(db.tasks).insert(TasksCompanion.insert(
              id: drift.Value(taskId),
              title: t['title'] as String,
              description: drift.Value(t['description'] as String?),
              customerId: drift.Value(t['customerId'] as String?),
              status: drift.Value(t['status'] as String? ?? 'PLANNED'),
              priority: drift.Value(t['priority'] as String? ?? 'NORMAL'),
              totalMinutes: drift.Value(t['totalMinutes'] as int? ?? 0),
              plannedDate: drift.Value(t['plannedDate'] != null
                  ? DateTime.tryParse(t['plannedDate'] as String)
                  : null),
              recurring: drift.Value(t['recurring'] as bool? ?? false),
              recurrenceType: drift.Value(t['recurrenceType'] as String?),
              recurrenceInterval: drift.Value(t['recurrenceInterval'] as int? ?? 1),
              recurrenceWeekday: drift.Value(t['recurrenceWeekday'] as int?),
              recurrenceMonthDay: drift.Value(t['recurrenceMonthDay'] as int?),
              estimatedMinutes: drift.Value(t['estimatedMinutes'] as int?),
              billedAt: drift.Value(t['billedAt'] != null
                  ? DateTime.tryParse(t['billedAt'] as String)
                  : null),
              archivedAt: drift.Value(t['archivedAt'] != null
                  ? DateTime.tryParse(t['archivedAt'] as String)
                  : null),
              createdAt: drift.Value(
                DateTime.tryParse(t['createdAt'] as String? ?? '') ?? DateTime.now(),
              ),
              updatedAt: drift.Value(
                DateTime.tryParse(t['updatedAt'] as String? ?? '') ?? DateTime.now(),
              ),
            ));
            for (final td in (t['todos'] as List? ?? [])) {
              await db.into(db.todos).insertOnConflictUpdate(TodosCompanion.insert(
                id: drift.Value(td['id'] as String),
                taskId: taskId,
                content: td['content'] as String,
                completed: drift.Value(td['completed'] as bool? ?? false),
                sortOrder: drift.Value(td['sortOrder'] as int? ?? 0),
                workflowId: drift.Value(td['workflowId'] as String?),
                workflowName: drift.Value(td['workflowName'] as String?),
              ));
            }
            for (final h in (t['hardware'] as List? ?? [])) {
              await db.into(db.hardware).insertOnConflictUpdate(HardwareCompanion.insert(
                id: drift.Value(h['id'] as String),
                taskId: taskId,
                type: h['type'] as String,
                name: drift.Value(h['name'] as String?),
                serial: drift.Value(h['serial'] as String?),
                notes: drift.Value(h['notes'] as String?),
              ));
            }
            for (final n in (t['notes'] as List? ?? [])) {
              await db.into(db.notes).insertOnConflictUpdate(NotesCompanion.insert(
                id: drift.Value(n['id'] as String),
                taskId: taskId,
                content: n['content'] as String,
                createdAt: drift.Value(
                  DateTime.tryParse(n['createdAt'] as String? ?? '') ?? DateTime.now(),
                ),
              ));
            }
            for (final s in (t['sessions'] as List? ?? [])) {
              await db.into(db.sessions).insertOnConflictUpdate(SessionsCompanion.insert(
                id: drift.Value(s['id'] as String),
                taskId: taskId,
                startTime: DateTime.tryParse(s['startTime'] as String? ?? '') ?? DateTime.now(),
                endTime: drift.Value(s['endTime'] != null
                    ? DateTime.tryParse(s['endTime'] as String)
                    : null),
                duration: drift.Value(s['duration'] as int? ?? 0),
                type: drift.Value(s['type'] as String? ?? 'WORK'),
                note: drift.Value(s['note'] as String?),
              ));
            }
            importedTasks++;
          }
        }
      });

      return DataImportResult.success(
        customers: importedCustomers,
        workflows: importedWorkflows,
        bundles: importedBundles,
        notes: importedNotes,
        templates: importedTemplates,
        tasks: importedTasks,
      );
    } catch (e) {
      return DataImportResult.error('Fehler beim Importieren: $e');
    }
  }
}

class DataImportResult {
  final bool cancelled;
  final String? error;
  final int customers;
  final int workflows;
  final int bundles;
  final int notes;
  final int templates;
  final int tasks;

  DataImportResult._({
    this.cancelled = false,
    this.error,
    this.customers = 0,
    this.workflows = 0,
    this.bundles = 0,
    this.notes = 0,
    this.templates = 0,
    this.tasks = 0,
  });

  factory DataImportResult.cancelled() => DataImportResult._(cancelled: true);
  factory DataImportResult.error(String msg) => DataImportResult._(error: msg);
  factory DataImportResult.success({
    required int customers,
    required int workflows,
    required int bundles,
    int notes = 0,
    int templates = 0,
    int tasks = 0,
  }) =>
      DataImportResult._(
          customers: customers,
          workflows: workflows,
          bundles: bundles,
          notes: notes,
          templates: templates,
          tasks: tasks);

  bool get isSuccess => !cancelled && error == null;

  String get summary {
    final parts = <String>[
      if (tasks > 0) '$tasks Tasks',
      if (customers > 0) '$customers Kunden',
      if (workflows > 0) '$workflows Workflows',
      if (bundles > 0) '$bundles Bundles',
      if (notes > 0) '$notes Notizen',
      if (templates > 0) '$templates Vorlagen',
    ];
    return parts.isEmpty ? 'Keine neuen Einträge' : '${parts.join(', ')} importiert';
  }
}
