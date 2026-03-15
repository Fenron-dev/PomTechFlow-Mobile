import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/timer_provider.dart';
import '../../widgets/task_card.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  String _filter = 'ALL';
  String _search = '';
  bool _searchVisible = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);
    final timer = ref.watch(timerProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searchVisible
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Tasks suchen...',
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              )
            : const Text('Tasks'),
        actions: [
          IconButton(
            icon: Icon(_searchVisible ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searchVisible = !_searchVisible;
              if (!_searchVisible) {
                _search = '';
                _searchCtrl.clear();
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await context.push('/tasks/new');
              ref.invalidate(tasksProvider);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _FilterBar(
            selected: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tasks) {
          var filtered = _filter == 'ALL'
              ? tasks
              : tasks.where((t) => t.task.status == _filter).toList();

          if (_search.isNotEmpty) {
            filtered = filtered
                .where((t) =>
                    t.task.title.toLowerCase().contains(_search) ||
                    (t.customer?.name.toLowerCase().contains(_search) ?? false))
                .toList();
          }

          if (filtered.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.checklist,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    _search.isNotEmpty
                        ? 'Keine Ergebnisse für "$_search"'
                        : _filter == 'ALL'
                            ? 'Noch keine Tasks'
                            : 'Keine ${_filterLabel(_filter)} Tasks',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                  if (_search.isEmpty) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        await context.push('/tasks/new');
                        ref.invalidate(tasksProvider);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Neuer Task'),
                    ),
                  ],
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tasksProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => TaskCard(
                task: filtered[i],
                isTimerRunning: timer.activeTaskId == filtered[i].task.id,
                onTap: () async {
                  await context.push('/tasks/${filtered[i].task.id}');
                  ref.invalidate(tasksProvider);
                },
                onDelete: () => _deleteTask(filtered[i].task.id),
              ),
            ),
          );
        },
      ),
    );
  }

  String _filterLabel(String f) => switch (f) {
        'PLANNED' => 'geplante',
        'ACTIVE' => 'aktive',
        'COMPLETED' => 'erledigte',
        _ => f,
      };

  Future<void> _deleteTask(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Task löschen?'),
        content: const Text('Alle Daten dieses Tasks werden gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(databaseProvider);
    await (db.delete(db.tasks)..where((t) => t.id.equals(id))).go();
    ref.invalidate(tasksProvider);
  }
}

class _FilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _FilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('ALL', 'Alle'),
      ('PLANNED', 'Geplant'),
      ('ACTIVE', 'Aktiv'),
      ('COMPLETED', 'Erledigt'),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: filters
            .map((f) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f.$2),
                    selected: selected == f.$1,
                    onSelected: (_) => onChanged(f.$1),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
