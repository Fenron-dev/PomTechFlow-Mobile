import '../db/database.dart';
import 'package:drift/drift.dart' show Value;

/// JSON-Serialisierung aller sync-relevanten Tabellen.
/// Jede Tabelle hat eine toJson- und eine toCompanion-Methode.
/// Der Sync-Protokoll-Schlüssel für "letztes Änderungsdatum" ist immer 'modifiedAt'.
/// Für Tasks wird intern 'updatedAt' als 'modifiedAt' gemappt.
class SyncSerializer {
  // ── Customers ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> customerToJson(Customer c) => {
        'id': c.id,
        'name': c.name,
        'email': c.email,
        'phone': c.phone,
        'street': c.street,
        'houseNumber': c.houseNumber,
        'zipCode': c.zipCode,
        'city': c.city,
        'notes': c.notes,
        'isActive': c.isActive,
        'createdAt': c.createdAt.toIso8601String(),
        'modifiedAt': c.modifiedAt.toIso8601String(),
      };

  static CustomersCompanion customerFromJson(Map<String, dynamic> m) =>
      CustomersCompanion(
        id: Value(m['id'] as String),
        name: Value(m['name'] as String),
        email: Value(m['email'] as String?),
        phone: Value(m['phone'] as String?),
        street: Value(m['street'] as String?),
        houseNumber: Value(m['houseNumber'] as String?),
        zipCode: Value(m['zipCode'] as String?),
        city: Value(m['city'] as String?),
        notes: Value(m['notes'] as String?),
        isActive: Value(m['isActive'] as bool? ?? true),
        createdAt: Value(_dt(m['createdAt'])),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── Contacts ───────────────────────────────────────────────────────────────

  static Map<String, dynamic> contactToJson(Contact c) => {
        'id': c.id,
        'customerId': c.customerId,
        'firstName': c.firstName,
        'lastName': c.lastName,
        'position': c.position,
        'email': c.email,
        'phoneLandline': c.phoneLandline,
        'phoneMobile': c.phoneMobile,
        'location': c.location,
        'isActive': c.isActive,
        'createdAt': c.createdAt.toIso8601String(),
        'modifiedAt': c.modifiedAt.toIso8601String(),
      };

  static ContactsCompanion contactFromJson(Map<String, dynamic> m) =>
      ContactsCompanion(
        id: Value(m['id'] as String),
        customerId: Value(m['customerId'] as String),
        firstName: Value(m['firstName'] as String),
        lastName: Value(m['lastName'] as String),
        position: Value(m['position'] as String?),
        email: Value(m['email'] as String?),
        phoneLandline: Value(m['phoneLandline'] as String?),
        phoneMobile: Value(m['phoneMobile'] as String?),
        location: Value(m['location'] as String?),
        isActive: Value(m['isActive'] as bool? ?? true),
        createdAt: Value(_dt(m['createdAt'])),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── Tasks ─────────────────────────────────────────────────────────────────

  static Map<String, dynamic> taskToJson(Task t) => {
        'id': t.id,
        'title': t.title,
        'description': t.description,
        'customerId': t.customerId,
        'status': t.status,
        'totalMinutes': t.totalMinutes,
        'plannedDate': t.plannedDate?.toIso8601String(),
        'priority': t.priority,
        'recurring': t.recurring,
        'recurrenceType': t.recurrenceType,
        'recurrenceInterval': t.recurrenceInterval,
        'recurrenceWeekday': t.recurrenceWeekday,
        'recurrenceMonthDay': t.recurrenceMonthDay,
        'estimatedMinutes': t.estimatedMinutes,
        'billedAt': t.billedAt?.toIso8601String(),
        'archivedAt': t.archivedAt?.toIso8601String(),
        'reminderOffsetMinutes': t.reminderOffsetMinutes,
        'createdAt': t.createdAt.toIso8601String(),
        'modifiedAt': t.updatedAt.toIso8601String(), // updatedAt → modifiedAt
      };

  static TasksCompanion taskFromJson(Map<String, dynamic> m) => TasksCompanion(
        id: Value(m['id'] as String),
        title: Value(m['title'] as String),
        description: Value(m['description'] as String?),
        customerId: Value(m['customerId'] as String?),
        status: Value(m['status'] as String? ?? 'PLANNED'),
        totalMinutes: Value(m['totalMinutes'] as int? ?? 0),
        plannedDate: Value(m['plannedDate'] != null ? DateTime.tryParse(m['plannedDate'] as String) : null),
        priority: Value(m['priority'] as String? ?? 'NORMAL'),
        recurring: Value(m['recurring'] as bool? ?? false),
        recurrenceType: Value(m['recurrenceType'] as String?),
        recurrenceInterval: Value(m['recurrenceInterval'] as int? ?? 1),
        recurrenceWeekday: Value(m['recurrenceWeekday'] as int?),
        recurrenceMonthDay: Value(m['recurrenceMonthDay'] as int?),
        estimatedMinutes: Value(m['estimatedMinutes'] as int?),
        billedAt: Value(m['billedAt'] != null ? DateTime.tryParse(m['billedAt'] as String) : null),
        archivedAt: Value(m['archivedAt'] != null ? DateTime.tryParse(m['archivedAt'] as String) : null),
        reminderOffsetMinutes: Value(m['reminderOffsetMinutes'] as int?),
        createdAt: Value(_dt(m['createdAt'])),
        updatedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── Sessions ───────────────────────────────────────────────────────────────

  static Map<String, dynamic> sessionToJson(Session s) => {
        'id': s.id,
        'taskId': s.taskId,
        'startTime': s.startTime.toIso8601String(),
        'endTime': s.endTime?.toIso8601String(),
        'duration': s.duration,
        'type': s.type,
        'remote': s.remote,
        'note': s.note,
        'technicianName': s.technicianName,
        'createdAt': s.startTime.toIso8601String(),
        'modifiedAt': s.modifiedAt.toIso8601String(),
      };

  static SessionsCompanion sessionFromJson(Map<String, dynamic> m) =>
      SessionsCompanion(
        id: Value(m['id'] as String),
        taskId: Value(m['taskId'] as String),
        startTime: Value(_dt(m['startTime'])),
        endTime: Value(m['endTime'] != null ? DateTime.tryParse(m['endTime'] as String) : null),
        duration: Value(m['duration'] as int? ?? 0),
        type: Value(m['type'] as String? ?? 'WORK'),
        remote: Value(m['remote'] as bool? ?? false),
        note: Value(m['note'] as String?),
        technicianName: Value(m['technicianName'] as String? ?? ''),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── Todos ─────────────────────────────────────────────────────────────────

  static Map<String, dynamic> todoToJson(Todo t) => {
        'id': t.id,
        'taskId': t.taskId,
        'content': t.content,
        'completed': t.completed,
        'sortOrder': t.sortOrder,
        'workflowId': t.workflowId,
        'workflowName': t.workflowName,
        'modifiedAt': t.modifiedAt.toIso8601String(),
      };

  static TodosCompanion todoFromJson(Map<String, dynamic> m) =>
      TodosCompanion(
        id: Value(m['id'] as String),
        taskId: Value(m['taskId'] as String),
        content: Value(m['content'] as String),
        completed: Value(m['completed'] as bool? ?? false),
        sortOrder: Value(m['sortOrder'] as int? ?? 0),
        workflowId: Value(m['workflowId'] as String?),
        workflowName: Value(m['workflowName'] as String?),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── Hardware ───────────────────────────────────────────────────────────────

  static Map<String, dynamic> hardwareToJson(HardwareData h) => {
        'id': h.id,
        'taskId': h.taskId,
        'type': h.type,
        'name': h.name,
        'serial': h.serial,
        'notes': h.notes,
        'sortOrder': h.sortOrder,
        'modifiedAt': h.modifiedAt.toIso8601String(),
      };

  static HardwareCompanion hardwareFromJson(Map<String, dynamic> m) =>
      HardwareCompanion(
        id: Value(m['id'] as String),
        taskId: Value(m['taskId'] as String),
        type: Value(m['type'] as String),
        name: Value(m['name'] as String?),
        serial: Value(m['serial'] as String?),
        notes: Value(m['notes'] as String?),
        sortOrder: Value(m['sortOrder'] as int? ?? 0),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── Notes ─────────────────────────────────────────────────────────────────

  static Map<String, dynamic> noteToJson(Note n) => {
        'id': n.id,
        'taskId': n.taskId,
        'content': n.content,
        'createdAt': n.createdAt.toIso8601String(),
        'modifiedAt': n.modifiedAt.toIso8601String(),
      };

  static NotesCompanion noteFromJson(Map<String, dynamic> m) =>
      NotesCompanion(
        id: Value(m['id'] as String),
        taskId: Value(m['taskId'] as String),
        content: Value(m['content'] as String),
        createdAt: Value(_dt(m['createdAt'])),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── Photos ────────────────────────────────────────────────────────────────

  static Map<String, dynamic> photoToJson(Photo p) => {
        'id': p.id,
        'taskId': p.taskId,
        'filePath': p.filePath,
        'caption': p.caption,
        'createdAt': p.createdAt.toIso8601String(),
        'modifiedAt': p.modifiedAt.toIso8601String(),
      };

  static PhotosCompanion photoFromJson(Map<String, dynamic> m) =>
      PhotosCompanion(
        id: Value(m['id'] as String),
        taskId: Value(m['taskId'] as String),
        filePath: Value(m['filePath'] as String),
        caption: Value(m['caption'] as String?),
        createdAt: Value(_dt(m['createdAt'])),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── Workflows ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> workflowToJson(Workflow w) => {
        'id': w.id,
        'name': w.name,
        'description': w.description,
        'createdAt': w.createdAt.toIso8601String(),
        'modifiedAt': w.modifiedAt.toIso8601String(),
      };

  static WorkflowsCompanion workflowFromJson(Map<String, dynamic> m) =>
      WorkflowsCompanion(
        id: Value(m['id'] as String),
        name: Value(m['name'] as String),
        description: Value(m['description'] as String?),
        createdAt: Value(_dt(m['createdAt'])),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── WorkflowItems ─────────────────────────────────────────────────────────

  static Map<String, dynamic> workflowItemToJson(WorkflowItem i) => {
        'id': i.id,
        'workflowId': i.workflowId,
        'itemText': i.itemText,
        'sortOrder': i.sortOrder,
        'modifiedAt': i.modifiedAt.toIso8601String(),
      };

  static WorkflowItemsCompanion workflowItemFromJson(Map<String, dynamic> m) =>
      WorkflowItemsCompanion(
        id: Value(m['id'] as String),
        workflowId: Value(m['workflowId'] as String),
        itemText: Value(m['itemText'] as String),
        sortOrder: Value(m['sortOrder'] as int? ?? 0),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── HardwareBundles ───────────────────────────────────────────────────────

  static Map<String, dynamic> hardwareBundleToJson(HardwareBundle b) => {
        'id': b.id,
        'name': b.name,
        'description': b.description,
        'createdAt': b.createdAt.toIso8601String(),
        'modifiedAt': b.modifiedAt.toIso8601String(),
      };

  static HardwareBundlesCompanion hardwareBundleFromJson(Map<String, dynamic> m) =>
      HardwareBundlesCompanion(
        id: Value(m['id'] as String),
        name: Value(m['name'] as String),
        description: Value(m['description'] as String?),
        createdAt: Value(_dt(m['createdAt'])),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── HardwareBundleItems ───────────────────────────────────────────────────

  static Map<String, dynamic> hardwareBundleItemToJson(HardwareBundleItem i) => {
        'id': i.id,
        'bundleId': i.bundleId,
        'type': i.type,
        'name': i.name,
        'serial': i.serial,
        'notes': i.notes,
        'sortOrder': i.sortOrder,
        'modifiedAt': i.modifiedAt.toIso8601String(),
      };

  static HardwareBundleItemsCompanion hardwareBundleItemFromJson(Map<String, dynamic> m) =>
      HardwareBundleItemsCompanion(
        id: Value(m['id'] as String),
        bundleId: Value(m['bundleId'] as String),
        type: Value(m['type'] as String),
        name: Value(m['name'] as String?),
        serial: Value(m['serial'] as String?),
        notes: Value(m['notes'] as String?),
        sortOrder: Value(m['sortOrder'] as int? ?? 0),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── TaskTemplates ─────────────────────────────────────────────────────────

  static Map<String, dynamic> taskTemplateToJson(TaskTemplate t) => {
        'id': t.id,
        'title': t.title,
        'description': t.description,
        'customerId': t.customerId,
        'workflowId': t.workflowId,
        'hardwareBundleId': t.hardwareBundleId,
        'notes': t.notes,
        'createdAt': t.createdAt.toIso8601String(),
        'modifiedAt': t.modifiedAt.toIso8601String(),
      };

  static TaskTemplatesCompanion taskTemplateFromJson(Map<String, dynamic> m) =>
      TaskTemplatesCompanion(
        id: Value(m['id'] as String),
        title: Value(m['title'] as String),
        description: Value(m['description'] as String?),
        customerId: Value(m['customerId'] as String?),
        workflowId: Value(m['workflowId'] as String?),
        hardwareBundleId: Value(m['hardwareBundleId'] as String?),
        notes: Value(m['notes'] as String?),
        createdAt: Value(_dt(m['createdAt'])),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── TaskTemplateTodos ─────────────────────────────────────────────────────

  static Map<String, dynamic> taskTemplateTodoToJson(TaskTemplateTodo t) => {
        'id': t.id,
        'templateId': t.templateId,
        'content': t.content,
        'sortOrder': t.sortOrder,
        'modifiedAt': t.modifiedAt.toIso8601String(),
      };

  static TaskTemplateTodosCompanion taskTemplateTodoFromJson(Map<String, dynamic> m) =>
      TaskTemplateTodosCompanion(
        id: Value(m['id'] as String),
        templateId: Value(m['templateId'] as String),
        content: Value(m['content'] as String),
        sortOrder: Value(m['sortOrder'] as int? ?? 0),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── TaskLinks ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> taskLinkToJson(TaskLink l) => {
        'id': l.id,
        'taskId': l.taskId,
        'linkedTaskId': l.linkedTaskId,
        'linkType': l.linkType,
        'createdAt': l.createdAt.toIso8601String(),
        'modifiedAt': l.modifiedAt.toIso8601String(),
      };

  static TaskLinksCompanion taskLinkFromJson(Map<String, dynamic> m) =>
      TaskLinksCompanion(
        id: Value(m['id'] as String),
        taskId: Value(m['taskId'] as String),
        linkedTaskId: Value(m['linkedTaskId'] as String),
        linkType: Value(m['linkType'] as String? ?? 'RELATED'),
        createdAt: Value(_dt(m['createdAt'])),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── GeneralNotes ──────────────────────────────────────────────────────────

  static Map<String, dynamic> generalNoteToJson(GeneralNote n) => {
        'id': n.id,
        'content': n.content,
        'tags': n.tags,
        'createdAt': n.createdAt.toIso8601String(),
        'modifiedAt': n.updatedAt.toIso8601String(),
      };

  static GeneralNotesCompanion generalNoteFromJson(Map<String, dynamic> m) =>
      GeneralNotesCompanion(
        id: Value(m['id'] as String),
        content: Value(m['content'] as String),
        tags: Value(m['tags'] as String?),
        createdAt: Value(_dt(m['createdAt'])),
        updatedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── NoteTemplates ─────────────────────────────────────────────────────────

  static Map<String, dynamic> noteTemplateToJson(NoteTemplate t) => {
        'id': t.id,
        'name': t.name,
        'content': t.content,
        'tags': t.tags,
        'createdAt': t.createdAt.toIso8601String(),
        'modifiedAt': t.updatedAt.toIso8601String(),
      };

  static NoteTemplatesCompanion noteTemplateFromJson(Map<String, dynamic> m) =>
      NoteTemplatesCompanion(
        id: Value(m['id'] as String),
        name: Value(m['name'] as String),
        content: Value(m['content'] as String),
        tags: Value(m['tags'] as String?),
        createdAt: Value(_dt(m['createdAt'])),
        updatedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── KnowledgeEntries ──────────────────────────────────────────────────────

  static Map<String, dynamic> knowledgeEntryToJson(KnowledgeEntry e) => {
        'id': e.id,
        'title': e.title,
        'problem': e.problem,
        'solution': e.solution,
        'tags': e.tags,
        'createdAt': e.createdAt.toIso8601String(),
        'modifiedAt': e.updatedAt.toIso8601String(),
      };

  static KnowledgeEntriesCompanion knowledgeEntryFromJson(Map<String, dynamic> m) =>
      KnowledgeEntriesCompanion(
        id: Value(m['id'] as String),
        title: Value(m['title'] as String),
        problem: Value(m['problem'] as String),
        solution: Value(m['solution'] as String),
        tags: Value(m['tags'] as String?),
        createdAt: Value(_dt(m['createdAt'])),
        updatedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── DevicePresets ─────────────────────────────────────────────────────────

  static Map<String, dynamic> devicePresetToJson(DevicePreset p) => {
        'id': p.id,
        'type': p.type,
        'name': p.name,
        'serial': p.serial,
        'notes': p.notes,
        'maintenanceIntervalDays': p.maintenanceIntervalDays,
        'lastMaintenanceDate': p.lastMaintenanceDate?.toIso8601String(),
        'createdAt': p.createdAt.toIso8601String(),
        'modifiedAt': p.modifiedAt.toIso8601String(),
      };

  static DevicePresetsCompanion devicePresetFromJson(Map<String, dynamic> m) =>
      DevicePresetsCompanion(
        id: Value(m['id'] as String),
        type: Value(m['type'] as String),
        name: Value(m['name'] as String),
        serial: Value(m['serial'] as String?),
        notes: Value(m['notes'] as String?),
        maintenanceIntervalDays: Value(m['maintenanceIntervalDays'] as int?),
        lastMaintenanceDate: Value(m['lastMaintenanceDate'] != null
            ? DateTime.tryParse(m['lastMaintenanceDate'] as String)
            : null),
        createdAt: Value(_dt(m['createdAt'])),
        modifiedAt: Value(_dt(m['modifiedAt'])),
      );

  // ── AppSettings (optional) ────────────────────────────────────────────────

  // Keys that must never be overwritten on the receiving device
  static const _settingsBlacklist = {
    'deviceId',
    'syncRole',
    'syncServerHost',
    'syncServerPort',
    'syncPairingToken',
    'storageBasePath',
    'autoBackupPath',
  };

  static bool isSettingsSyncable(String key) =>
      !_settingsBlacklist.contains(key) && !key.startsWith('webdav');

  // ── Helper ────────────────────────────────────────────────────────────────

  static DateTime _dt(dynamic raw) =>
      raw != null ? (DateTime.tryParse(raw as String) ?? DateTime.now()) : DateTime.now();
}
