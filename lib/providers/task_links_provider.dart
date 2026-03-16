import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'database_provider.dart';
import '../db/database.dart';

class TaskLinkEntry {
  final TaskLink link;
  final Task linkedTask;
  const TaskLinkEntry({required this.link, required this.linkedTask});
}

final taskLinksProvider =
    FutureProvider.family<List<TaskLinkEntry>, String>((ref, taskId) async {
  final db = ref.watch(databaseProvider);
  final links = await (db.select(db.taskLinks)
        ..where((l) => l.taskId.equals(taskId)))
      .get();
  final result = <TaskLinkEntry>[];
  for (final link in links) {
    final task = await (db.select(db.tasks)
          ..where((t) => t.id.equals(link.linkedTaskId)))
        .getSingleOrNull();
    if (task != null) result.add(TaskLinkEntry(link: link, linkedTask: task));
  }
  return result;
});
