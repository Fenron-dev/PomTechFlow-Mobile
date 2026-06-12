import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database.dart';
import 'package:drift/drift.dart' as drift;

class TaskHandoverService {
  /// Exportiert einen kompletten Task inkl. aller Daten und Fotos als .ptf-Datei.
  static Future<void> exportTask(AppDatabase db, String taskId) async {
    final task = await (db.select(db.tasks)
          ..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
    if (task == null) throw Exception('Task nicht gefunden');

    Customer? customer;
    if (task.customerId != null) {
      customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(task.customerId!)))
          .getSingleOrNull();
    }

    final todos = await (db.select(db.todos)
          ..where((t) => t.taskId.equals(taskId))
          ..orderBy([(t) => drift.OrderingTerm.asc(t.sortOrder)]))
        .get();

    final hardware = await (db.select(db.hardware)
          ..where((h) => h.taskId.equals(taskId))
          ..orderBy([(h) => drift.OrderingTerm.asc(h.sortOrder)]))
        .get();

    final notes = await (db.select(db.notes)
          ..where((n) => n.taskId.equals(taskId))
          ..orderBy([(n) => drift.OrderingTerm.asc(n.createdAt)]))
        .get();

    final sessions = await (db.select(db.sessions)
          ..where((s) => s.taskId.equals(taskId)))
        .get();

    final photos = await (db.select(db.photos)
          ..where((p) => p.taskId.equals(taskId))
          ..orderBy([(p) => drift.OrderingTerm.asc(p.createdAt)]))
        .get();

    // Fotos komprimiert als Base64 einbetten (max 1200 px, JPEG 75 %)
    const maxDim  = 1200;
    const quality = 75;
    final photoData = <Map<String, dynamic>>[];
    for (final photo in photos) {
      final file = File(photo.filePath);
      if (!await file.exists()) continue;
      final raw = await file.readAsBytes();
      List<int> compressed;
      try {
        final decoded = img.decodeImage(raw);
        if (decoded != null) {
          final needsResize =
              decoded.width > maxDim || decoded.height > maxDim;
          final resized = needsResize
              ? img.copyResize(
                  decoded,
                  width:  decoded.width >= decoded.height ? maxDim : null,
                  height: decoded.height > decoded.width  ? maxDim : null,
                )
              : decoded;
          compressed = img.encodeJpg(resized, quality: quality);
        } else {
          compressed = raw; // fallback: unbekanntes Format, Original behalten
        }
      } catch (_) {
        compressed = raw; // fallback bei Decode-Fehler
      }
      photoData.add({
        'id': photo.id,
        'filePath': photo.filePath.split('/').last,
        'caption': photo.caption,
        'createdAt': photo.createdAt.toIso8601String(),
        'data': base64Encode(compressed),
      });
    }

    final export = {
      'version': 1,
      'type': 'task_handover',
      'exportedAt': DateTime.now().toIso8601String(),
      'task': {
        'title': task.title,
        'description': task.description,
        'status': task.status,
        'totalMinutes': task.totalMinutes,
        'plannedDate': task.plannedDate?.toIso8601String(),
        'createdAt': task.createdAt.toIso8601String(),
      },
      'customer': customer == null
          ? null
          : {
              'name': customer.name,
              'email': customer.email,
              'phone': customer.phone,
              'address': [
                if (customer.street != null) customer.street!,
                if (customer.houseNumber != null) customer.houseNumber!,
                if (customer.zipCode != null) customer.zipCode!,
                if (customer.city != null) customer.city!,
              ].join(' '),
            },
      'todos': todos
          .map((t) => {
                'content': t.content,
                'completed': t.completed,
                'sortOrder': t.sortOrder,
                'workflowName': t.workflowName,
              })
          .toList(),
      'hardware': hardware
          .map((h) => {
                'type': h.type,
                'name': h.name,
                'serial': h.serial,
                'notes': h.notes,
                'sortOrder': h.sortOrder,
              })
          .toList(),
      'notes': notes
          .map((n) => {
                'content': n.content,
                'createdAt': n.createdAt.toIso8601String(),
              })
          .toList(),
      'sessions': sessions
          .map((s) => {
                'startTime': s.startTime.toIso8601String(),
                'endTime': s.endTime?.toIso8601String(),
                'duration': s.duration,
                'type': s.type,
                'note': s.note,
              })
          .toList(),
      'photos': photoData,
    };

    final json = const JsonEncoder.withIndent('  ').convert(export);
    final dir = await getApplicationDocumentsDirectory();
    final safeName = task.title
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-äöüÄÖÜß ]'), '_')
        .trim()
        .replaceAll(' ', '_');
    final file = File('${dir.path}/task_${safeName}_${DateTime.now().millisecondsSinceEpoch}.ptf');
    await file.writeAsString(json);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Task-Übergabe: ${task.title}',
        text: 'PomTechFlow Task-Übergabe: ${task.title}',
      ),
    );
  }

  /// Importiert einen Task aus einer .ptf-Datei. Erstellt neuen Task mit neuer ID.
  static Future<TaskHandoverImportResult> importTask(AppDatabase db) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) {
      return TaskHandoverImportResult.cancelled();
    }

    final path = result.files.first.path;
    if (path == null) return TaskHandoverImportResult.cancelled();

    try {
      final file = File(path);
      final fileSize = await file.length();
      if (fileSize > 50 * 1024 * 1024) {
        return TaskHandoverImportResult.error(
            'Datei zu groß (max. 50 MB). Bitte eine gültige .ptf-Datei wählen.');
      }
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      if (data['type'] != 'task_handover') {
        return TaskHandoverImportResult.error(
            'Keine gültige Task-Übergabe-Datei (.ptf).');
      }

      final taskData = data['task'] as Map<String, dynamic>;
      final customerData = data['customer'] as Map<String, dynamic>?;

      // Fotos speichern
      final appDir = await getApplicationDocumentsDirectory();
      final photoDir = Directory('${appDir.path}/photos');
      await photoDir.create(recursive: true);

      await db.transaction(() async {
        // Kunde suchen oder erstellen
        String? customerId;
        if (customerData != null) {
          final customerName = customerData['name'] as String;
          final existing = await (db.select(db.customers)
                ..where((c) => c.name.equals(customerName)))
              .getSingleOrNull();
          if (existing != null) {
            customerId = existing.id;
          } else {
            final newId = 'cust_${DateTime.now().millisecondsSinceEpoch}';
            await db.into(db.customers).insert(CustomersCompanion.insert(
                  id: drift.Value(newId),
                  name: customerName,
                  email: drift.Value(customerData['email'] as String?),
                  phone: drift.Value(customerData['phone'] as String?),
                  street: drift.Value(customerData['address'] as String?),
                ));
            customerId = newId;
          }
        }

        // Task erstellen
        final newTaskId = 'task_${DateTime.now().millisecondsSinceEpoch}';
        final plannedDateStr = taskData['plannedDate'] as String?;
        await db.into(db.tasks).insert(TasksCompanion.insert(
              id: drift.Value(newTaskId),
              title: '[Übergabe] ${taskData['title'] as String}',
              description: drift.Value(taskData['description'] as String?),
              customerId: drift.Value(customerId),
              status: drift.Value('PLANNED'),
              totalMinutes:
                  drift.Value(taskData['totalMinutes'] as int? ?? 0),
              plannedDate: drift.Value(plannedDateStr != null
                  ? DateTime.tryParse(plannedDateStr)
                  : null),
              updatedAt: drift.Value(DateTime.now()),
            ));

        // Todos
        final todos = data['todos'] as List? ?? [];
        for (int i = 0; i < todos.length; i++) {
          final t = todos[i] as Map<String, dynamic>;
          await db.into(db.todos).insert(TodosCompanion.insert(
                taskId: newTaskId,
                content: t['content'] as String,
                completed:
                    drift.Value(t['completed'] as bool? ?? false),
                sortOrder: drift.Value(t['sortOrder'] as int? ?? i),
                workflowName:
                    drift.Value(t['workflowName'] as String?),
              ));
        }

        // Hardware
        final hardware = data['hardware'] as List? ?? [];
        for (int i = 0; i < hardware.length; i++) {
          final h = hardware[i] as Map<String, dynamic>;
          await db.into(db.hardware).insert(HardwareCompanion.insert(
                taskId: newTaskId,
                type: h['type'] as String,
                name: drift.Value(h['name'] as String?),
                serial: drift.Value(h['serial'] as String?),
                notes: drift.Value(h['notes'] as String?),
                sortOrder: drift.Value(h['sortOrder'] as int? ?? i),
              ));
        }

        // Notizen
        final notes = data['notes'] as List? ?? [];
        for (final n in notes) {
          final nd = n as Map<String, dynamic>;
          await db.into(db.notes).insert(NotesCompanion.insert(
                taskId: newTaskId,
                content: nd['content'] as String,
                createdAt: drift.Value(DateTime.tryParse(
                        nd['createdAt'] as String? ?? '') ??
                    DateTime.now()),
              ));
        }

        // Sessions (Zeiteinträge übernehmen, aber nicht in Timer)
        final sessions = data['sessions'] as List? ?? [];
        for (final s in sessions) {
          final sd = s as Map<String, dynamic>;
          final endStr = sd['endTime'] as String?;
          await db.into(db.sessions).insert(SessionsCompanion.insert(
                taskId: newTaskId,
                startTime:
                    DateTime.tryParse(sd['startTime'] as String? ?? '') ??
                        DateTime.now(),
                endTime: drift.Value(
                    endStr != null ? DateTime.tryParse(endStr) : null),
                duration: drift.Value(sd['duration'] as int? ?? 0),
                type: drift.Value(sd['type'] as String? ?? 'WORK'),
                note: drift.Value(sd['note'] as String?),
              ));
        }

        // Fotos aus Base64 wiederherstellen
        final photos = data['photos'] as List? ?? [];
        for (final p in photos) {
          final pd = p as Map<String, dynamic>;
          final base64Data = pd['data'] as String?;
          if (base64Data == null) continue;
          final bytes = base64Decode(base64Data);
          final fileName =
              'photo_import_${DateTime.now().millisecondsSinceEpoch}_${pd['filePath'] as String? ?? 'img.jpg'}';
          final photoFile = File('${photoDir.path}/$fileName');
          await photoFile.writeAsBytes(bytes);
          await db.into(db.photos).insert(PhotosCompanion.insert(
                taskId: newTaskId,
                filePath: photoFile.path,
                caption: drift.Value(pd['caption'] as String?),
                createdAt: drift.Value(
                    DateTime.tryParse(pd['createdAt'] as String? ?? '') ??
                        DateTime.now()),
              ));
        }
      });

      return TaskHandoverImportResult.success(
          title: '[Übergabe] ${taskData['title'] as String}');
    } catch (e) {
      return TaskHandoverImportResult.error('Fehler beim Importieren: $e');
    }
  }
}

class TaskHandoverImportResult {
  final bool cancelled;
  final String? error;
  final String? taskTitle;

  TaskHandoverImportResult._({
    this.cancelled = false,
    this.error,
    this.taskTitle,
  });

  factory TaskHandoverImportResult.cancelled() =>
      TaskHandoverImportResult._(cancelled: true);
  factory TaskHandoverImportResult.error(String msg) =>
      TaskHandoverImportResult._(error: msg);
  factory TaskHandoverImportResult.success({required String title}) =>
      TaskHandoverImportResult._(taskTitle: title);

  bool get isSuccess => !cancelled && error == null;
}
