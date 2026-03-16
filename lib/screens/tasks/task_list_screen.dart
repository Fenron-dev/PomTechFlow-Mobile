import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/timer_provider.dart';
import '../../providers/task_templates_provider.dart';
import '../../db/database.dart';
import '../../widgets/task_card.dart';
import '../../services/task_handover_service.dart';
import '../../widgets/timer_session_dialogs.dart';
import 'task_detail_screen.dart';
import 'package:drift/drift.dart' as drift;

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  String _filter = 'ALL';
  String _priorityFilter = 'ALL';
  String _sortBy = 'date_desc';
  String _search = '';
  bool _searchVisible = false;
  final _searchCtrl = TextEditingController();
  String? _selectedTaskId;

  static const double _tabletBreakpoint = 700;

  static int _priorityRank(String p) => switch (p) {
    'CRITICAL' => 3,
    'HIGH' => 2,
    'NORMAL' => 1,
    'LOW' => 0,
    _ => 1,
  };

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= _tabletBreakpoint;

    if (isTablet) {
      return _buildTabletLayout();
    }
    return _buildListScaffold(isTablet: false);
  }

  Widget _buildTabletLayout() {
    return Row(
      children: [
        SizedBox(
          width: 360,
          child: _buildListScaffold(isTablet: true),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: _selectedTaskId == null
              ? const _EmptyDetailPane()
              : TaskDetailScreen(
                  key: ValueKey(_selectedTaskId),
                  taskId: _selectedTaskId!,
                  embedded: true,
                  onDeleted: () => setState(() => _selectedTaskId = null),
                  onTaskChanged: () => ref.invalidate(tasksProvider),
                ),
        ),
      ],
    );
  }

  Widget _buildListScaffold({required bool isTablet}) {
    final tasksAsync = ref.watch(tasksProvider);
    final timer = ref.watch(timerProvider);
    final aeMinutes = ref.watch(settingsProvider).valueOrNull?.aeMinutes ?? 10;

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
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sortieren & Filtern',
            onSelected: (v) {
              if (v.startsWith('sort:')) {
                setState(() => _sortBy = v.substring(5));
              } else if (v.startsWith('prio:')) {
                setState(() => _priorityFilter = v.substring(5));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(enabled: false,
                  child: Text('— Sortierung —',
                      style: TextStyle(fontSize: 12))),
              _sortItem('sort:priority_desc', Icons.flag,
                  'Priorität (hoch→niedrig)', _sortBy == 'priority_desc'),
              _sortItem('sort:date_desc', Icons.calendar_today,
                  'Datum (neu→alt)', _sortBy == 'date_desc'),
              _sortItem('sort:date_asc', Icons.calendar_today_outlined,
                  'Datum (alt→neu)', _sortBy == 'date_asc'),
              _sortItem('sort:title_asc', Icons.sort_by_alpha,
                  'Titel (A–Z)', _sortBy == 'title_asc'),
              const PopupMenuDivider(),
              const PopupMenuItem(enabled: false,
                  child: Text('— Priorität filtern —',
                      style: TextStyle(fontSize: 12))),
              _sortItem('prio:ALL', Icons.filter_list, 'Alle',
                  _priorityFilter == 'ALL'),
              _sortItem('prio:CRITICAL', Icons.priority_high, 'Kritisch',
                  _priorityFilter == 'CRITICAL'),
              _sortItem('prio:HIGH', Icons.arrow_upward, 'Hoch',
                  _priorityFilter == 'HIGH'),
              _sortItem('prio:NORMAL', Icons.remove, 'Normal',
                  _priorityFilter == 'NORMAL'),
              _sortItem('prio:LOW', Icons.arrow_downward, 'Niedrig',
                  _priorityFilter == 'LOW'),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Task importieren (.ptf)',
            onPressed: () async {
              final db = ref.read(databaseProvider);
              final result = await TaskHandoverService.importTask(db);
              if (!context.mounted) return;
              if (result.isSuccess) {
                ref.invalidate(tasksProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Task importiert: ${result.taskTitle}')),
                );
              } else if (result.error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result.error!)),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              if (isTablet) {
                // On tablet, push new-task form; on return, refresh and select
                await context.push('/tasks/new');
                ref.invalidate(tasksProvider);
              } else {
                await context.push('/tasks/new');
                ref.invalidate(tasksProvider);
              }
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

          if (_priorityFilter != 'ALL') {
            filtered = filtered
                .where((t) => t.task.priority == _priorityFilter)
                .toList();
          }

          if (_search.isNotEmpty) {
            filtered = filtered
                .where((t) =>
                    t.task.title.toLowerCase().contains(_search) ||
                    (t.customer?.name.toLowerCase().contains(_search) ?? false))
                .toList();
          }

          // Sortierung
          filtered = List.of(filtered);
          switch (_sortBy) {
            case 'priority_desc':
              filtered.sort((a, b) =>
                  _priorityRank(b.task.priority)
                      .compareTo(_priorityRank(a.task.priority)));
            case 'date_asc':
              filtered.sort((a, b) =>
                  a.task.updatedAt.compareTo(b.task.updatedAt));
            case 'title_asc':
              filtered.sort((a, b) =>
                  a.task.title.compareTo(b.task.title));
            default: // date_desc
              filtered.sort((a, b) =>
                  b.task.updatedAt.compareTo(a.task.updatedAt));
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
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _createFromTemplate(context, ref, isTablet: isTablet),
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Aus Vorlage'),
                    ),
                  ],
                ],
              ),
            );
          }

          // Auto-clear selection if selected task no longer in filtered list
          if (_selectedTaskId != null &&
              !filtered.any((t) => t.task.id == _selectedTaskId)) {
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => setState(() => _selectedTaskId = null));
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tasksProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final taskId = filtered[i].task.id;
                final isRunning = timer.status == TimerStatus.running &&
                    timer.activeTaskId == taskId;
                final isPaused = timer.status == TimerStatus.paused &&
                    timer.activeTaskId == taskId;
                return TaskCard(
                  task: filtered[i],
                  isTimerRunning: isRunning,
                  isTimerPaused: isPaused,
                  aeMinutes: aeMinutes,
                  isSelected: isTablet && _selectedTaskId == taskId,
                  onTap: () async {
                    if (isTablet) {
                      setState(() => _selectedTaskId = taskId);
                    } else {
                      await context.push('/tasks/$taskId');
                      ref.invalidate(tasksProvider);
                    }
                  },
                  onDelete: () => _deleteTask(taskId, isTablet: isTablet),
                  onTimerStart: timer.status == TimerStatus.idle
                      ? () => ref.read(timerProvider.notifier).start(taskId)
                      : null,
                  onTimerPause: isRunning
                      ? () => ref.read(timerProvider.notifier).pause()
                      : null,
                  onTimerResume: isPaused
                      ? () => ref.read(timerProvider.notifier).resume()
                      : null,
                  onTimerStop: (isRunning || isPaused)
                      ? () => handleTimerStop(context, ref)
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _createFromTemplate(BuildContext context, WidgetRef ref,
      {required bool isTablet}) async {
    final templates = ref.read(taskTemplatesProvider).valueOrNull ?? [];
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Keine Vorlagen. Erst in Einstellungen anlegen.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<TemplateWithDetails>(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Vorlage wählen',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const Divider(height: 1),
          ...templates.map((twd) => ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(twd.template.title),
                subtitle: [
                  if (twd.customer != null) twd.customer!.name,
                  if (twd.workflow != null) twd.workflow!.name,
                  if (twd.bundle != null) twd.bundle!.name,
                ].join(' · ').isEmpty
                    ? null
                    : Text([
                        if (twd.customer != null) twd.customer!.name,
                        if (twd.workflow != null) twd.workflow!.name,
                        if (twd.bundle != null) twd.bundle!.name,
                      ].join(' · ')),
                onTap: () => Navigator.pop(context, twd),
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;

    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final newTaskId = 'task_${now.millisecondsSinceEpoch}';

    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: drift.Value(newTaskId),
          title: selected.template.title,
          description: drift.Value(selected.template.description),
          customerId: drift.Value(selected.template.customerId),
          updatedAt: drift.Value(now),
        ));

    if (selected.template.workflowId != null) {
      final items = await (db.select(db.workflowItems)
            ..where((i) =>
                i.workflowId.equals(selected.template.workflowId!))
            ..orderBy([(i) => drift.OrderingTerm.asc(i.sortOrder)]))
          .get();
      final workflow = selected.workflow;
      for (var i = 0; i < items.length; i++) {
        await db.into(db.todos).insert(TodosCompanion.insert(
              taskId: newTaskId,
              content: items[i].itemText,
              sortOrder: drift.Value(i),
              workflowId: drift.Value(selected.template.workflowId),
              workflowName: drift.Value(workflow?.name),
            ));
      }
    }

    if (selected.template.hardwareBundleId != null) {
      final bundleItems = await (db.select(db.hardwareBundleItems)
            ..where((i) =>
                i.bundleId.equals(selected.template.hardwareBundleId!))
            ..orderBy([(i) => drift.OrderingTerm.asc(i.sortOrder)]))
          .get();
      for (var i = 0; i < bundleItems.length; i++) {
        await db.into(db.hardware).insert(HardwareCompanion.insert(
              taskId: newTaskId,
              type: bundleItems[i].type,
              name: drift.Value(bundleItems[i].name),
              serial: drift.Value(bundleItems[i].serial),
              notes: drift.Value(bundleItems[i].notes),
              sortOrder: drift.Value(i),
            ));
      }
    }

    ref.invalidate(tasksProvider);
    if (!context.mounted) return;

    if (isTablet) {
      setState(() => _selectedTaskId = newTaskId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Task erstellt: ${selected.template.title}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Task erstellt: ${selected.template.title}')),
      );
      await context.push('/tasks/$newTaskId');
      ref.invalidate(tasksProvider);
    }
  }

  PopupMenuItem<String> _sortItem(
      String value, IconData icon, String label, bool active) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 18,
            color: active
                ? Theme.of(context).colorScheme.primary
                : null),
        const SizedBox(width: 10),
        Text(label,
            style: active
                ? TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold)
                : null),
      ]),
    );
  }

  String _filterLabel(String f) => switch (f) {
        'PLANNED' => 'geplante',
        'ACTIVE' => 'aktive',
        'COMPLETED' => 'erledigte',
        'CRM_DONE' => 'im CRM erfasste',
        _ => f,
      };

  Future<void> _deleteTask(String id, {required bool isTablet}) async {
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
    if (isTablet && _selectedTaskId == id) {
      setState(() => _selectedTaskId = null);
    }
    ref.invalidate(tasksProvider);
  }
}

class _EmptyDetailPane extends StatelessWidget {
  const _EmptyDetailPane();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Task auswählen',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
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
      ('CRM_DONE', 'Im CRM'),
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
