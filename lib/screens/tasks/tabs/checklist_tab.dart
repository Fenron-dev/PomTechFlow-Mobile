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
    await showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Workflow anwenden',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const Divider(height: 1),
          ...workflows.map((wf) => ListTile(
                title: Text(wf.workflow.name),
                subtitle: Text('${wf.items.length} Punkte'),
                onTap: () {
                  Navigator.pop(context);
                  _applyWorkflow(wf);
                },
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todosAsync = ref.watch(todosProvider(widget.taskId));

    return Column(
      children: [
        // Eingabe
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
              IconButton.filled(
                icon: const Icon(Icons.add),
                onPressed: _addTodo,
              ),
              IconButton(
                icon: const Icon(Icons.folder_open_outlined),
                tooltip: 'Workflow anwenden',
                onPressed: _showWorkflowPicker,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Liste
        Expanded(
          child: todosAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (todos) {
              if (todos.isEmpty) {
                return Center(
                  child: Text(
                    'Noch keine Checklistenpunkte',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                );
              }

              // Gruppieren nach workflowName
              final grouped = <String?, List<Todo>>{};
              for (final todo in todos) {
                grouped.putIfAbsent(todo.workflowName, () => []).add(todo);
              }

              final sections = <Widget>[];
              grouped.forEach((groupName, groupTodos) {
                if (groupName != null) {
                  sections.add(_GroupHeader(name: groupName, todos: groupTodos));
                }
                sections.addAll(groupTodos.map((todo) => _TodoItem(
                      todo: todo,
                      onToggle: () => _toggleTodo(todo),
                      onDelete: () => _deleteTodo(todo.id),
                    )));
              });

              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: sections,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String name;
  final List<Todo> todos;
  const _GroupHeader({required this.name, required this.todos});

  @override
  Widget build(BuildContext context) {
    final done = todos.where((t) => t.completed).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold)),
          ),
          Text('$done/${todos.length}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}

class _TodoItem extends StatelessWidget {
  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TodoItem(
      {required this.todo, required this.onToggle, required this.onDelete});

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
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18),
        onPressed: onDelete,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
