import 'package:drift/drift.dart' show Value;
import '../../db/database.dart' hide AppSettings;
import '../../providers/settings_provider.dart';
import '../sync_serializer.dart';
import '../server/sync_auth.dart';
import 'sync_api_client.dart';

enum SyncStatus { idle, syncing, success, error, offline, notConfigured }

class SyncResult {
  final SyncStatus status;
  final String? message;
  final List<Map<String, dynamic>> conflicts;
  final DateTime? completedAt;

  const SyncResult({
    required this.status,
    this.message,
    this.conflicts = const [],
    this.completedAt,
  });
}

class SyncService {
  final AppDatabase db;
  final AppSettings settings;

  SyncService({required this.db, required this.settings});

  SyncApiClient get _client => SyncApiClient(
        host: settings.syncServerHost,
        port: settings.syncServerPort,
      );

  /// Full sync cycle: pull → upsert → push changes → return conflicts.
  Future<SyncResult> sync() async {
    if (settings.syncRole != 'CLIENT') {
      return const SyncResult(status: SyncStatus.notConfigured);
    }
    if (settings.syncServerHost.isEmpty) {
      return const SyncResult(status: SyncStatus.notConfigured, message: 'Kein Server konfiguriert');
    }

    // Check connectivity first
    final health = await _client.checkHealth();
    if (health == null) {
      return const SyncResult(status: SyncStatus.offline, message: 'Server nicht erreichbar');
    }

    final peerId = health['deviceId'] as String? ?? settings.syncServerHost;
    final peerName = health['name'] as String?;

    // Load last sync state
    final syncStateRow = await (db.select(db.syncState)
          ..where((t) => t.peerId.equals(peerId)))
        .getSingleOrNull();
    final lastPullAt = syncStateRow?.lastPullAt;

    // ── Pull ──────────────────────────────────────────────────────────────
    final pullData = await _client.pull(since: lastPullAt);
    if (pullData == null) {
      return const SyncResult(status: SyncStatus.error, message: 'Pull fehlgeschlagen');
    }

    final now = DateTime.now();

    await db.transaction(() async {
      final tables = pullData['tables'] as Map<String, dynamic>? ?? {};
      final deletions = pullData['deletions'] as List<dynamic>? ?? [];

      // Apply tombstones first
      for (final d in deletions) {
        final type = d['entityType'] as String;
        final id = d['entityId'] as String;
        final deletedAt = DateTime.tryParse(d['deletedAt'] as String? ?? '') ?? now;
        await db.into(db.syncDeletions).insertOnConflictUpdate(SyncDeletionsCompanion(
          entityType: Value(type),
          entityId: Value(id),
          deletedAt: Value(deletedAt),
        ));
        await _deleteEntityLocal(type, id);
      }

      await _upsertAll(db, tables, settings.syncAppSettings);
    });

    // ── Push ──────────────────────────────────────────────────────────────
    final lastPushAt = syncStateRow?.lastPushAt;
    final pushPayload = await _buildPushPayload(lastPushAt);
    pushPayload['deviceId'] = settings.deviceId;

    final conflicts = await _client.push(pushPayload) ?? [];

    // Update sync state
    await db.into(db.syncState).insertOnConflictUpdate(SyncStateCompanion(
      peerId: Value(peerId),
      peerName: Value(peerName),
      lastPullAt: Value(now),
      lastPushAt: Value(now),
    ));

    return SyncResult(
      status: SyncStatus.success,
      conflicts: conflicts,
      completedAt: now,
    );
  }

  Future<Map<String, dynamic>> _buildPushPayload(DateTime? since) async {
    final tables = <String, List<Map<String, dynamic>>>{};

    Future<List<Map<String, dynamic>>> q<T>(
        Future<List<T>> Function() getter, Map<String, dynamic> Function(T) toJson) async {
      final rows = await getter();
      if (since == null) return rows.map(toJson).toList();
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

    if (settings.syncAppSettings) {
      final rows = await db.select(db.appSettings).get();
      tables['appSettings'] = rows
          .where((r) => SyncSerializer.isSettingsSyncable(r.key))
          .map((r) => {'key': r.key, 'value': r.value})
          .toList();
    }

    // Local tombstones since last push
    final localDeletions = await db.select(db.syncDeletions).get();
    final filteredDeletions = since != null
        ? localDeletions.where((d) => d.deletedAt.isAfter(since)).toList()
        : localDeletions;

    return {
      'tables': tables,
      'deletions': filteredDeletions.map((d) => {
            'entityType': d.entityType,
            'entityId': d.entityId,
            'deletedAt': d.deletedAt.toIso8601String(),
          }).toList(),
    };
  }

  Future<void> _deleteEntityLocal(String type, String id) async {
    switch (type) {
      case 'customers': await (db.delete(db.customers)..where((t) => t.id.equals(id))).go();
      case 'contacts': await (db.delete(db.contacts)..where((t) => t.id.equals(id))).go();
      case 'tasks': await (db.delete(db.tasks)..where((t) => t.id.equals(id))).go();
      case 'sessions': await (db.delete(db.sessions)..where((t) => t.id.equals(id))).go();
      case 'todos': await (db.delete(db.todos)..where((t) => t.id.equals(id))).go();
      case 'hardware': await (db.delete(db.hardware)..where((t) => t.id.equals(id))).go();
      case 'notes': await (db.delete(db.notes)..where((t) => t.id.equals(id))).go();
      case 'photos': await (db.delete(db.photos)..where((t) => t.id.equals(id))).go();
      case 'workflows': await (db.delete(db.workflows)..where((t) => t.id.equals(id))).go();
      case 'workflowItems': await (db.delete(db.workflowItems)..where((t) => t.id.equals(id))).go();
      case 'hardwareBundles': await (db.delete(db.hardwareBundles)..where((t) => t.id.equals(id))).go();
      case 'hardwareBundleItems': await (db.delete(db.hardwareBundleItems)..where((t) => t.id.equals(id))).go();
      case 'taskTemplates': await (db.delete(db.taskTemplates)..where((t) => t.id.equals(id))).go();
      case 'taskTemplateTodos': await (db.delete(db.taskTemplateTodos)..where((t) => t.id.equals(id))).go();
      case 'taskLinks': await (db.delete(db.taskLinks)..where((t) => t.id.equals(id))).go();
      case 'generalNotes': await (db.delete(db.generalNotes)..where((t) => t.id.equals(id))).go();
      case 'noteTemplates': await (db.delete(db.noteTemplates)..where((t) => t.id.equals(id))).go();
      case 'knowledgeEntries': await (db.delete(db.knowledgeEntries)..where((t) => t.id.equals(id))).go();
      case 'devicePresets': await (db.delete(db.devicePresets)..where((t) => t.id.equals(id))).go();
    }
  }

  static Future<void> _upsertAll(
      AppDatabase db, Map<String, dynamic> tables, bool syncAppSettings) async {
    Future<void> ins<C>(String key, C Function(Map<String, dynamic>) fromJson,
        Future<void> Function(C) insert) async {
      for (final row in (tables[key] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()) {
        await insert(fromJson(row));
      }
    }

    await ins('customers', SyncSerializer.customerFromJson,
        (c) => db.into(db.customers).insertOnConflictUpdate(c));
    await ins('contacts', SyncSerializer.contactFromJson,
        (c) => db.into(db.contacts).insertOnConflictUpdate(c));
    await ins('tasks', SyncSerializer.taskFromJson,
        (t) => db.into(db.tasks).insertOnConflictUpdate(t));
    await ins('sessions', SyncSerializer.sessionFromJson,
        (s) => db.into(db.sessions).insertOnConflictUpdate(s));
    await ins('todos', SyncSerializer.todoFromJson,
        (t) => db.into(db.todos).insertOnConflictUpdate(t));
    await ins('hardware', SyncSerializer.hardwareFromJson,
        (h) => db.into(db.hardware).insertOnConflictUpdate(h));
    await ins('notes', SyncSerializer.noteFromJson,
        (n) => db.into(db.notes).insertOnConflictUpdate(n));
    await ins('photos', SyncSerializer.photoFromJson,
        (p) => db.into(db.photos).insertOnConflictUpdate(p));
    await ins('workflows', SyncSerializer.workflowFromJson,
        (w) => db.into(db.workflows).insertOnConflictUpdate(w));
    await ins('workflowItems', SyncSerializer.workflowItemFromJson,
        (i) => db.into(db.workflowItems).insertOnConflictUpdate(i));
    await ins('hardwareBundles', SyncSerializer.hardwareBundleFromJson,
        (b) => db.into(db.hardwareBundles).insertOnConflictUpdate(b));
    await ins('hardwareBundleItems', SyncSerializer.hardwareBundleItemFromJson,
        (i) => db.into(db.hardwareBundleItems).insertOnConflictUpdate(i));
    await ins('taskTemplates', SyncSerializer.taskTemplateFromJson,
        (t) => db.into(db.taskTemplates).insertOnConflictUpdate(t));
    await ins('taskTemplateTodos', SyncSerializer.taskTemplateTodoFromJson,
        (t) => db.into(db.taskTemplateTodos).insertOnConflictUpdate(t));
    await ins('taskLinks', SyncSerializer.taskLinkFromJson,
        (l) => db.into(db.taskLinks).insertOnConflictUpdate(l));
    await ins('generalNotes', SyncSerializer.generalNoteFromJson,
        (n) => db.into(db.generalNotes).insertOnConflictUpdate(n));
    await ins('noteTemplates', SyncSerializer.noteTemplateFromJson,
        (t) => db.into(db.noteTemplates).insertOnConflictUpdate(t));
    await ins('knowledgeEntries', SyncSerializer.knowledgeEntryFromJson,
        (e) => db.into(db.knowledgeEntries).insertOnConflictUpdate(e));
    await ins('devicePresets', SyncSerializer.devicePresetFromJson,
        (p) => db.into(db.devicePresets).insertOnConflictUpdate(p));

    if (syncAppSettings) {
      for (final row in (tables['appSettings'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()) {
        final key = row['key'] as String? ?? '';
        if (!SyncSerializer.isSettingsSyncable(key)) continue;
        await db.into(db.appSettings).insertOnConflictUpdate(
              AppSettingsCompanion.insert(key: key, value: row['value'] as String? ?? ''),
            );
      }
    }
  }

  Future<void> unpair() async {
    await SyncAuth.clearClientTokens();
    // Clear sync state
    await db.delete(db.syncState).go();
  }
}
