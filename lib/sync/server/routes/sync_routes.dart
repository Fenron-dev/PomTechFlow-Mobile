import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../../db/database.dart';
import '../../sync_serializer.dart';

Router syncRouter(
  AppDatabase db,
  String serverDeviceId,
  bool syncAppSettings, [
  void Function(String deviceId, String deviceName)? onClientSeen,
]) {
  final router = Router();

  // GET /api/v1/sync?since=<ISO8601>
  // Returns all rows modified after `since`, plus tombstones.
  router.get('/api/v1/sync', (Request req) async {
    // Track client activity
    final clientDeviceId = req.context['clientDeviceId'] as String? ?? '';
    final clientDeviceName = req.url.queryParameters['deviceName'] ?? '';
    onClientSeen?.call(clientDeviceId, clientDeviceName);

    final sinceStr = req.url.queryParameters['since'];
    final since = sinceStr != null ? DateTime.tryParse(sinceStr) : null;

    final tables = <String, List<Map<String, dynamic>>>{};

    // Pull all changed rows — if `since` is null, pull everything (initial sync)
    Future<List<Map<String, dynamic>>> q<T>(
        Future<List<T>> Function() getter, Map<String, dynamic> Function(T) toJson) async {
      final rows = await getter();
      if (since == null) return rows.map(toJson).toList();
      // Filter in Dart — avoids custom drift expressions for now
      return rows.map(toJson).where((m) {
        final dt = DateTime.tryParse(m['modifiedAt'] as String? ?? '');
        return dt != null && dt.isAfter(since);
      }).toList();
    }

    tables['customers'] = await q(() => db.select(db.customers).get(), SyncSerializer.customerToJson);
    tables['contacts'] = await q(() => db.select(db.contacts).get(), SyncSerializer.contactToJson);
    tables['tasks'] = await q(() => db.select(db.tasks).get(), SyncSerializer.taskToJson);
    tables['sessions'] = await q(() => db.select(db.sessions).get(), SyncSerializer.sessionToJson);
    tables['todos'] = await q(() => db.select(db.todos).get(), SyncSerializer.todoToJson);
    tables['hardware'] = await q(() => db.select(db.hardware).get(), SyncSerializer.hardwareToJson);
    tables['notes'] = await q(() => db.select(db.notes).get(), SyncSerializer.noteToJson);
    tables['photos'] = await q(() => db.select(db.photos).get(), SyncSerializer.photoToJson);
    tables['workflows'] = await q(() => db.select(db.workflows).get(), SyncSerializer.workflowToJson);
    tables['workflowItems'] = await q(() => db.select(db.workflowItems).get(), SyncSerializer.workflowItemToJson);
    tables['hardwareBundles'] = await q(() => db.select(db.hardwareBundles).get(), SyncSerializer.hardwareBundleToJson);
    tables['hardwareBundleItems'] = await q(() => db.select(db.hardwareBundleItems).get(), SyncSerializer.hardwareBundleItemToJson);
    tables['taskTemplates'] = await q(() => db.select(db.taskTemplates).get(), SyncSerializer.taskTemplateToJson);
    tables['taskTemplateTodos'] = await q(() => db.select(db.taskTemplateTodos).get(), SyncSerializer.taskTemplateTodoToJson);
    tables['taskLinks'] = await q(() => db.select(db.taskLinks).get(), SyncSerializer.taskLinkToJson);
    tables['generalNotes'] = await q(() => db.select(db.generalNotes).get(), SyncSerializer.generalNoteToJson);
    tables['noteTemplates'] = await q(() => db.select(db.noteTemplates).get(), SyncSerializer.noteTemplateToJson);
    tables['knowledgeEntries'] = await q(() => db.select(db.knowledgeEntries).get(), SyncSerializer.knowledgeEntryToJson);
    tables['devicePresets'] = await q(() => db.select(db.devicePresets).get(), SyncSerializer.devicePresetToJson);

    if (syncAppSettings) {
      final rows = await db.select(db.appSettings).get();
      tables['appSettings'] = rows
          .where((r) => SyncSerializer.isSettingsSyncable(r.key))
          .map((r) => {'key': r.key, 'value': r.value})
          .toList();
    }

    // Tombstones
    final deletions = await db.select(db.syncDeletions).get();
    final filteredDeletions = since != null
        ? deletions.where((d) => d.deletedAt.isAfter(since)).toList()
        : deletions;

    return Response.ok(
      jsonEncode({
        'syncedAt': DateTime.now().toUtc().toIso8601String(),
        'serverDeviceId': serverDeviceId,
        'tables': tables,
        'deletions': filteredDeletions.map((d) => {
              'entityType': d.entityType,
              'entityId': d.entityId,
              'deletedAt': d.deletedAt.toIso8601String(),
            }).toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  // POST /api/v1/sync/push
  // Body: { "deviceId": "...", "tables": {...}, "deletions": [...] }
  // Returns: { "conflicts": [...] }
  router.post('/api/v1/sync/push', (Request req) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return Response(400,
          body: jsonEncode({'error': 'invalid_json'}),
          headers: {'content-type': 'application/json'});
    }

    final tables = body['tables'] as Map<String, dynamic>? ?? {};
    final deletions = body['deletions'] as List<dynamic>? ?? [];
    final clientDeviceId = body['deviceId'] as String? ?? '';
    final clientDeviceName = body['deviceName'] as String? ?? '';
    // Track client activity on push
    onClientSeen?.call(clientDeviceId, clientDeviceName);

    final conflicts = <Map<String, dynamic>>[];

    await db.transaction(() async {
      // Process tombstones first — deleted wins over updated
      for (final d in deletions) {
        final entityType = d['entityType'] as String;
        final entityId = d['entityId'] as String;
        final deletedAt = DateTime.tryParse(d['deletedAt'] as String? ?? '') ?? DateTime.now();

        await db.into(db.syncDeletions).insertOnConflictUpdate(
          SyncDeletionsCompanion(
            entityType: Value(entityType),
            entityId: Value(entityId),
            deletedAt: Value(deletedAt),
            deletedByDeviceId: Value(clientDeviceId),
          ),
        );
        // Apply actual delete
        await _deleteEntity(db, entityType, entityId);
      }

      // Helper to check if entityId is a known tombstone
      Future<bool> isTombstone(String type, String id) async {
        final row = await (db.select(db.syncDeletions)
              ..where((t) => t.entityType.equals(type) & t.entityId.equals(id)))
            .getSingleOrNull();
        return row != null;
      }

      // Process each table
      Future<void> upsertRows<T>(
        String tableKey,
        Future<T?> Function(String id) getExisting,
        DateTime? Function(T) getModifiedAt,
        Future<void> Function(Map<String, dynamic>) upsert,
      ) async {
        final rows = (tables[tableKey] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        for (final row in rows) {
          final id = row['id'] as String;
          if (await isTombstone(tableKey, id)) continue;

          final existing = await getExisting(id);
          if (existing != null) {
            final existingMod = getModifiedAt(existing);
            final incomingMod = DateTime.tryParse(row['modifiedAt'] as String? ?? '');
            if (existingMod != null && incomingMod != null && existingMod.isAfter(incomingMod)) {
              // Server version is newer → conflict
              conflicts.add({'table': tableKey, 'id': id, 'serverModifiedAt': existingMod.toIso8601String()});
              continue;
            }
          }
          await upsert(row);
        }
      }

      // Sessions: no conflict if different technicianName — they're separate rows
      final sessionRows = (tables['sessions'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      for (final row in sessionRows) {
        final id = row['id'] as String;
        if (await isTombstone('sessions', id)) continue;
        await db.into(db.sessions).insertOnConflictUpdate(SyncSerializer.sessionFromJson(row));
      }

      // All other tables with Last-Write-Wins
      await upsertRows<Customer>('customers',
          (id) => (db.select(db.customers)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (c) => c.modifiedAt, (r) async => db.into(db.customers).insertOnConflictUpdate(SyncSerializer.customerFromJson(r)));

      await upsertRows<Contact>('contacts',
          (id) => (db.select(db.contacts)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (c) => c.modifiedAt, (r) async => db.into(db.contacts).insertOnConflictUpdate(SyncSerializer.contactFromJson(r)));

      await upsertRows<Task>('tasks',
          (id) => (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (t) => t.updatedAt, (r) async => db.into(db.tasks).insertOnConflictUpdate(SyncSerializer.taskFromJson(r)));

      await upsertRows<Todo>('todos',
          (id) => (db.select(db.todos)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (t) => t.modifiedAt, (r) async => db.into(db.todos).insertOnConflictUpdate(SyncSerializer.todoFromJson(r)));

      await upsertRows<HardwareData>('hardware',
          (id) => (db.select(db.hardware)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (h) => h.modifiedAt, (r) async => db.into(db.hardware).insertOnConflictUpdate(SyncSerializer.hardwareFromJson(r)));

      await upsertRows<Note>('notes',
          (id) => (db.select(db.notes)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (n) => n.modifiedAt, (r) async => db.into(db.notes).insertOnConflictUpdate(SyncSerializer.noteFromJson(r)));

      await upsertRows<Photo>('photos',
          (id) => (db.select(db.photos)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (p) => p.modifiedAt, (r) async => db.into(db.photos).insertOnConflictUpdate(SyncSerializer.photoFromJson(r)));

      await upsertRows<Workflow>('workflows',
          (id) => (db.select(db.workflows)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (w) => w.modifiedAt, (r) async => db.into(db.workflows).insertOnConflictUpdate(SyncSerializer.workflowFromJson(r)));

      await upsertRows<WorkflowItem>('workflowItems',
          (id) => (db.select(db.workflowItems)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (i) => i.modifiedAt, (r) async => db.into(db.workflowItems).insertOnConflictUpdate(SyncSerializer.workflowItemFromJson(r)));

      await upsertRows<HardwareBundle>('hardwareBundles',
          (id) => (db.select(db.hardwareBundles)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (b) => b.modifiedAt, (r) async => db.into(db.hardwareBundles).insertOnConflictUpdate(SyncSerializer.hardwareBundleFromJson(r)));

      await upsertRows<HardwareBundleItem>('hardwareBundleItems',
          (id) => (db.select(db.hardwareBundleItems)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (i) => i.modifiedAt, (r) async => db.into(db.hardwareBundleItems).insertOnConflictUpdate(SyncSerializer.hardwareBundleItemFromJson(r)));

      await upsertRows<TaskTemplate>('taskTemplates',
          (id) => (db.select(db.taskTemplates)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (t) => t.modifiedAt, (r) async => db.into(db.taskTemplates).insertOnConflictUpdate(SyncSerializer.taskTemplateFromJson(r)));

      await upsertRows<TaskTemplateTodo>('taskTemplateTodos',
          (id) => (db.select(db.taskTemplateTodos)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (t) => t.modifiedAt, (r) async => db.into(db.taskTemplateTodos).insertOnConflictUpdate(SyncSerializer.taskTemplateTodoFromJson(r)));

      await upsertRows<TaskLink>('taskLinks',
          (id) => (db.select(db.taskLinks)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (l) => l.modifiedAt, (r) async => db.into(db.taskLinks).insertOnConflictUpdate(SyncSerializer.taskLinkFromJson(r)));

      await upsertRows<GeneralNote>('generalNotes',
          (id) => (db.select(db.generalNotes)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (n) => n.updatedAt, (r) async => db.into(db.generalNotes).insertOnConflictUpdate(SyncSerializer.generalNoteFromJson(r)));

      await upsertRows<NoteTemplate>('noteTemplates',
          (id) => (db.select(db.noteTemplates)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (t) => t.updatedAt, (r) async => db.into(db.noteTemplates).insertOnConflictUpdate(SyncSerializer.noteTemplateFromJson(r)));

      await upsertRows<KnowledgeEntry>('knowledgeEntries',
          (id) => (db.select(db.knowledgeEntries)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (e) => e.updatedAt, (r) async => db.into(db.knowledgeEntries).insertOnConflictUpdate(SyncSerializer.knowledgeEntryFromJson(r)));

      await upsertRows<DevicePreset>('devicePresets',
          (id) => (db.select(db.devicePresets)..where((t) => t.id.equals(id))).getSingleOrNull(),
          (p) => p.modifiedAt, (r) async => db.into(db.devicePresets).insertOnConflictUpdate(SyncSerializer.devicePresetFromJson(r)));

      // App-Settings (optional, with blacklist)
      if (syncAppSettings) {
        final settingRows = (tables['appSettings'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        for (final row in settingRows) {
          final key = row['key'] as String? ?? '';
          if (!SyncSerializer.isSettingsSyncable(key)) continue;
          await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: key, value: row['value'] as String? ?? ''),
          );
        }
      }
    });

    return Response.ok(
      jsonEncode({'conflicts': conflicts}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}

Future<void> _deleteEntity(AppDatabase db, String type, String id) async {
  switch (type) {
    case 'customers':
      await (db.delete(db.customers)..where((t) => t.id.equals(id))).go();
    case 'contacts':
      await (db.delete(db.contacts)..where((t) => t.id.equals(id))).go();
    case 'tasks':
      await (db.delete(db.tasks)..where((t) => t.id.equals(id))).go();
    case 'sessions':
      await (db.delete(db.sessions)..where((t) => t.id.equals(id))).go();
    case 'todos':
      await (db.delete(db.todos)..where((t) => t.id.equals(id))).go();
    case 'hardware':
      await (db.delete(db.hardware)..where((t) => t.id.equals(id))).go();
    case 'notes':
      await (db.delete(db.notes)..where((t) => t.id.equals(id))).go();
    case 'photos':
      await (db.delete(db.photos)..where((t) => t.id.equals(id))).go();
    case 'workflows':
      await (db.delete(db.workflows)..where((t) => t.id.equals(id))).go();
    case 'workflowItems':
      await (db.delete(db.workflowItems)..where((t) => t.id.equals(id))).go();
    case 'hardwareBundles':
      await (db.delete(db.hardwareBundles)..where((t) => t.id.equals(id))).go();
    case 'hardwareBundleItems':
      await (db.delete(db.hardwareBundleItems)..where((t) => t.id.equals(id))).go();
    case 'taskTemplates':
      await (db.delete(db.taskTemplates)..where((t) => t.id.equals(id))).go();
    case 'taskTemplateTodos':
      await (db.delete(db.taskTemplateTodos)..where((t) => t.id.equals(id))).go();
    case 'taskLinks':
      await (db.delete(db.taskLinks)..where((t) => t.id.equals(id))).go();
    case 'generalNotes':
      await (db.delete(db.generalNotes)..where((t) => t.id.equals(id))).go();
    case 'noteTemplates':
      await (db.delete(db.noteTemplates)..where((t) => t.id.equals(id))).go();
    case 'knowledgeEntries':
      await (db.delete(db.knowledgeEntries)..where((t) => t.id.equals(id))).go();
    case 'devicePresets':
      await (db.delete(db.devicePresets)..where((t) => t.id.equals(id))).go();
  }
}
