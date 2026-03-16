import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../../providers/tasks_provider.dart';
import '../../../providers/workflows_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../db/database.dart';

class ChecklistTab extends ConsumerStatefulWidget {
  final String taskId;
  const ChecklistTab({super.key, required this.taskId});

  @override
  ConsumerState<ChecklistTab> createState() => _ChecklistTabState();
}

class _ChecklistTabState extends ConsumerState<ChecklistTab> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _reorderTodos(
      List<Todo> todos, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return;
    final list = List.of(todos);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    final db = ref.read(databaseProvider);
    for (int i = 0; i < list.length; i++) {
      await (db.update(db.todos)..where((t) => t.id.equals(list[i].id)))
          .write(TodosCompanion(sortOrder: drift.Value(i)));
    }
    ref.invalidate(todosProvider(widget.taskId));
  }

  Future<void> _addTodo() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final db = ref.read(databaseProvider);
    final existing = await (db.select(db.todos)
          ..where((t) => t.taskId.equals(widget.taskId)))
        .get();
    await db.into(db.todos).insert(TodosCompanion.insert(
          taskId: widget.taskId,
          content: text,
          sortOrder: drift.Value(existing.length),
        ));
    _ctrl.clear();
    ref.invalidate(todosProvider(widget.taskId));
  }

  Future<void> _toggleTodo(Todo todo) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.todos)..where((t) => t.id.equals(todo.id)))
        .write(TodosCompanion(completed: drift.Value(!todo.completed)));
    ref.invalidate(todosProvider(widget.taskId));
  }

  Future<void> _deleteTodo(String id) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.todos)..where((t) => t.id.equals(id))).go();
    ref.invalidate(todosProvider(widget.taskId));
  }

  Future<void> _applyWorkflow(WorkflowWithDetails wf) async {
    final db = ref.read(databaseProvider);
    final existing = await (db.select(db.todos)
          ..where((t) => t.taskId.equals(widget.taskId)))
        .get();
    int sortBase = existing.length;
    for (final item in wf.items) {
      await db.into(db.todos).insert(TodosCompanion.insert(
            taskId: widget.taskId,
            content: item.itemText,
            sortOrder: drift.Value(sortBase++),
            workflowId: drift.Value(wf.workflow.id),
            workflowName: drift.Value(wf.workflow.name),
          ));
    }
    ref.invalidate(todosProvider(widget.taskId));
  }

  Future<void> _showWorkflowPicker() async {
    final workflows = ref.read(workflowsProvider).valueOrNull ?? [];
    if (workflows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Workflows vorhanden')),
      );
      return;
    }
    final selected = await showModalBottomSheet<List<WorkflowWithDetails>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WorkflowMultiPicker(workflows: workflows),
    );
    if (selected == null || selected.isEmpty) return;
    for (final wf in selected) {
      await _applyWorkflow(wf);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todosAsync = ref.watch(todosProvider(widget.taskId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                    hintText: 'Neuer Checklistenpunkt...',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addTodo(),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(icon: const Icon(Icons.add), onPressed: _addTodo),
              IconButton(
                icon: const Icon(Icons.folder_open_outlined),
                tooltip: 'Workflow anwenden',
                onPressed: _showWorkflowPicker,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: todosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (todos) {
              if (todos.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.checklist,
                          size: 48,
                          color: Theme.of(context).colorScheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text('Noch keine Checklistenpunkte',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _showWorkflowPicker,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Workflow anwenden'),
                      ),
                    ],
                  ),
                );
              }

              // Aufteilen: ohne Workflow vs. pro Workflow
              final ungrouped =
                  todos.where((t) => t.workflowId == null).toList();
              final grouped = <String, _WorkflowGroup>{};
              for (final todo in todos.where((t) => t.workflowId != null)) {
                grouped.putIfAbsent(
                  todo.workflowId!,
                  () => _WorkflowGroup(
                    id: todo.workflowId!,
                    name: todo.workflowName ?? 'Workflow',
                    todos: [],
                  ),
                ).todos.add(todo);
              }

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (ungrouped.isNotEmpty)
                    _UngroupedSection(
                      todos: ungrouped,
                      onToggle: _toggleTodo,
                      onDelete: _deleteTodo,
                      onReorder: (o, n) =>
                          _reorderTodos(ungrouped, o, n),
                    ),
                  if (ungrouped.isNotEmpty && grouped.isNotEmpty)
                    const SizedBox(height: 8),
                  ...grouped.values.map((group) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _WorkflowGroupCard(
                          group: group,
                          onToggle: _toggleTodo,
                          onDelete: _deleteTodo,
                        ),
                      )),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WorkflowGroup {
  final String id;
  final String name;
  final List<Todo> todos;
  _WorkflowGroup({required this.id, required this.name, required this.todos});
  int get done => todos.where((t) => t.completed).length;
  bool get allDone => done == todos.length && todos.isNotEmpty;
}

class _UngroupedSection extends StatelessWidget {
  final List<Todo> todos;
  final ValueChanged<Todo> onToggle;
  final ValueChanged<String> onDelete;
  final void Function(int, int) onReorder;

  const _UngroupedSection({
    required this.todos,
    required this.onToggle,
    required this.onDelete,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text('Allgemein',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: onReorder,
          buildDefaultDragHandles: false,
          children: todos
              .asMap()
              .entries
              .map((e) => _TodoTile(
                    key: ValueKey(e.value.id),
                    todo: e.value,
                    index: e.key,
                    onToggle: () => onToggle(e.value),
                    onDelete: () => onDelete(e.value.id),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _WorkflowGroupCard extends StatefulWidget {
  final _WorkflowGroup group;
  final ValueChanged<Todo> onToggle;
  final ValueChanged<String> onDelete;
  const _WorkflowGroupCard(
      {required this.group, required this.onToggle, required this.onDelete});

  @override
  State<_WorkflowGroupCard> createState() => _WorkflowGroupCardState();
}

class _WorkflowGroupCardState extends State<_WorkflowGroupCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = !widget.group.allDone;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final group = widget.group;
    final progress =
        group.todos.isEmpty ? 0.0 : group.done / group.todos.length;
    final allDone = group.allDone;

    return Card(
      margin: EdgeInsets.zero,
      elevation: allDone ? 0 : 1,
      color: allDone ? cs.secondaryContainer.withValues(alpha: 0.4) : null,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(12),
              bottom: _expanded ? Radius.zero : const Radius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    allDone ? Icons.folder : Icons.folder_open,
                    size: 20,
                    color: allDone ? cs.secondary : cs.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                decoration: allDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: allDone ? cs.outline : null,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 5,
                                  backgroundColor: cs.surfaceContainerHighest,
                                  color:
                                      allDone ? cs.secondary : cs.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${group.done}/${group.todos.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: cs.outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
          // ── Todos ────────────────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            ...group.todos.map((todo) => _TodoTile(
                  key: ValueKey(todo.id),
                  todo: todo,
                  onToggle: () => widget.onToggle(todo),
                  onDelete: () => widget.onDelete(todo.id),
                )),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  final Todo todo;
  final int? index; // null = in workflow group (no drag handle)
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  const _TodoTile({
    super.key,
    required this.todo,
    this.index,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: todo.completed,
        onChanged: (_) => onToggle(),
      ),
      title: Text(
        todo.content,
        style: TextStyle(
          decoration: todo.completed ? TextDecoration.lineThrough : null,
          color: todo.completed
              ? Theme.of(context).colorScheme.outline
              : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
          ),
          if (index != null)
            ReorderableDragStartListener(
              index: index!,
              child: const Icon(Icons.drag_handle,
                  size: 18, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}

// ─── Multi-Workflow Picker ────────────────────────────────────────────────────

class _WorkflowMultiPicker extends StatefulWidget {
  final List<WorkflowWithDetails> workflows;
  const _WorkflowMultiPicker({required this.workflows});

  @override
  State<_WorkflowMultiPicker> createState() => _WorkflowMultiPickerState();
}

class _WorkflowMultiPickerState extends State<_WorkflowMultiPicker> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Text('Workflows anwenden',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                            context,
                            widget.workflows
                                .where((w) => _selected.contains(w.workflow.id))
                                .toList(),
                          ),
                  icon: const Icon(Icons.check),
                  label: Text(_selected.isEmpty
                      ? 'Anwenden'
                      : 'Anwenden (${_selected.length})'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: widget.workflows.length,
              itemBuilder: (_, i) {
                final wf = widget.workflows[i];
                final checked = _selected.contains(wf.workflow.id);
                return CheckboxListTile(
                  value: checked,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(wf.workflow.id);
                    } else {
                      _selected.remove(wf.workflow.id);
                    }
                  }),
                  secondary: const Icon(Icons.folder_outlined),
                  title: Text(wf.workflow.name),
                  subtitle: Text('${wf.items.length} Punkte'),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
