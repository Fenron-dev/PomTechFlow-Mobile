import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_provider.dart';
import '../db/database.dart';

class TaskLinkEntry {
  final TaskLink link;
  final Task linkedTask;
  /// true wenn diese Verknüpfung von einem anderen Task ausging (Rückverweis).
  final bool isBacklink;
  const TaskLinkEntry({
    required this.link,
    required this.linkedTask,
    this.isBacklink = false,
  });
}

/// Liefert alle Verknüpfungen für [taskId]:
/// - Direkte Links (taskId → andere Tasks)
/// - Rückverweise / Backlinks (andere Tasks → taskId)
final taskLinksProvider =
    FutureProvider.family<List<TaskLinkEntry>, String>((ref, taskId) async {
  final db = ref.watch(databaseProvider);

  // Direkte Links
  final directLinks = await (db.select(db.taskLinks)
        ..where((l) => l.taskId.equals(taskId)))
      .get();

  // Backlinks (dieser Task ist das Ziel)
  final backLinks = await (db.select(db.taskLinks)
        ..where((l) => l.linkedTaskId.equals(taskId)))
      .get();

  final result = <TaskLinkEntry>[];

  for (final link in directLinks) {
    final task = await (db.select(db.tasks)
          ..where((t) => t.id.equals(link.linkedTaskId)))
        .getSingleOrNull();
    if (task != null) {
      result.add(TaskLinkEntry(link: link, linkedTask: task));
    }
  }

  for (final link in backLinks) {
    final task = await (db.select(db.tasks)
          ..where((t) => t.id.equals(link.taskId)))
        .getSingleOrNull();
    if (task != null) {
      result.add(TaskLinkEntry(link: link, linkedTask: task, isBacklink: true));
    }
  }

  return result;
});
