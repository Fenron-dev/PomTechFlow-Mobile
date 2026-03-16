import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:go_router/go_router.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/timer_provider.dart';
import '../../db/database.dart';
import '../../services/task_handover_service.dart';
import 'tabs/overview_tab.dart';
import 'tabs/checklist_tab.dart';
import 'tabs/hardware_tab.dart';
import 'tabs/notes_tab.dart';
import 'tabs/photos_tab.dart';

class TaskDetailScreen extends ConsumerWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskDetailProvider(taskId));
    final timer = ref.watch(timerProvider);

    return taskAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (detail) {
        if (detail == null) {
          return const Scaffold(body: Center(child: Text('Task nicht gefunden')));
        }
        final task = detail.task;
        final isActiveTask = timer.activeTaskId == taskId;

        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    await context.push('/tasks/$taskId/edit'); // nested route: /tasks/:id/edit
                    ref.invalidate(taskDetailProvider(taskId));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share_outlined),
                  tooltip: 'Task übergeben',
                  onPressed: () async {
                    try {
                      final db = ref.read(databaseProvider);
                      await TaskHandoverService.exportTask(db, taskId);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Fehler: $e')),
                        );
                      }
                    }
                  },
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.info_outline), text: 'Übersicht'),
                  Tab(icon: Icon(Icons.checklist), text: 'Checkliste'),
                  Tab(icon: Icon(Icons.computer_outlined), text: 'Hardware'),
                  Tab(icon: Icon(Icons.notes), text: 'Notizen'),
                  Tab(icon: Icon(Icons.photo_library_outlined), text: 'Fotos'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                OverviewTab(
                  detail: detail,
                  isActiveTask: isActiveTask,
                  onStartTimer: () async {
                    await ref.read(timerProvider.notifier).start(taskId);
                    if (context.mounted) context.go('/timer');
                  },
                  onMarkDone: () => _markDone(ref, taskId),
                ),
                ChecklistTab(taskId: taskId),
                HardwareTab(taskId: taskId),
                NotesTab(taskId: taskId),
                PhotosTab(taskId: taskId),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _markDone(WidgetRef ref, String taskId) async {
    final db = ref.read(databaseProvider);
    final task = await (db.select(db.tasks)..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        status: const drift.Value('COMPLETED'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Wiederkehrenden Task anlegen
    if (task != null && task.recurring && task.recurrenceType != null) {
      final nextDate = _nextRecurrenceDate(
          task.plannedDate ?? DateTime.now(),
          task.recurrenceType!,
          task.recurrenceInterval);
      await db.into(db.tasks).insert(TasksCompanion.insert(
            title: task.title,
            description: drift.Value(task.description),
            customerId: drift.Value(task.customerId),
            plannedDate: drift.Value(nextDate),
            recurring: const drift.Value(true),
            recurrenceType: drift.Value(task.recurrenceType),
            recurrenceInterval: drift.Value(task.recurrenceInterval),
            updatedAt: drift.Value(DateTime.now()),
          ));
    }

    ref.invalidate(taskDetailProvider(taskId));
    ref.invalidate(tasksProvider);
  }

  DateTime _nextRecurrenceDate(
      DateTime base, String type, int interval) {
    return switch (type) {
      'DAILY' => base.add(Duration(days: interval)),
      'WEEKLY' => base.add(Duration(days: 7 * interval)),
      'MONTHLY' => DateTime(
          base.year, base.month + interval, base.day,
          base.hour, base.minute),
      'QUARTERLY' => DateTime(
          base.year, base.month + (3 * interval), base.day,
          base.hour, base.minute),
      _ => base.add(Duration(days: 7 * interval)),
    };
  }
}
