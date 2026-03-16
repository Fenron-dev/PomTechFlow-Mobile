import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/workflows_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/database_provider.dart';
import '../../db/database.dart';

class WorkflowsScreen extends ConsumerWidget {
  const WorkflowsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflowsAsync = ref.watch(workflowsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workflows & Vorlagen')),
      body: workflowsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (workflows) {
          if (workflows.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('Noch keine Workflows'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showForm(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Neuer Workflow'),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: workflows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _WorkflowCard(
              wf: workflows[i],
              onEdit: () => _showForm(context, ref, workflows[i]),
              onDelete: () => _delete(context, ref, workflows[i].workflow.id),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, ref, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showForm(
      BuildContext context, WidgetRef ref, WorkflowWithDetails? wf) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WorkflowForm(existing: wf),
    );
    ref.invalidate(workflowsProvider);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Workflow löschen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(databaseProvider);
    await (db.delete(db.workflows)..where((w) => w.id.equals(id))).go();
    ref.invalidate(workflowsProvider);
  }
}

class _WorkflowCard extends StatelessWidget {
  final WorkflowWithDetails wf;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _WorkflowCard(
      {required this.wf, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(wf.workflow.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact),
                IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact),
              ],
            ),
            if (wf.customers.isNotEmpty)
              Text(
                wf.customers.map((c) => c.name).join(', '),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.primary),
              )
            else
              Text('Allgemeine Vorlage',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline)),
            if (wf.workflow.description != null) ...[
              const SizedBox(height: 4),
              Text(wf.workflow.description!,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                Chip(
                  label: Text('${wf.items.length} Punkte'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (wf.items.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...wf.items.take(3).map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Icon(Icons.radio_button_unchecked,
                            size: 14, color: cs.outline),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(item.itemText,
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  )),
              if (wf.items.length > 3)
                Text('+${wf.items.length - 3} weitere',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: cs.outline)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Formular ─────────────────────────────────────────────────────────────────

class _WorkflowForm extends ConsumerStatefulWidget {
  final WorkflowWithDetails? existing;
  const _WorkflowForm({this.existing});

  @override
  ConsumerState<_WorkflowForm> createState() => _WorkflowFormState();
}

class _WorkflowFormState extends ConsumerState<_WorkflowForm> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _itemCtrl = TextEditingController();
  List<String> _items = [];
  List<String> _selectedCustomerIds = [];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final wf = widget.existing!;
      _nameCtrl.text = wf.workflow.name;
      _descCtrl.text = wf.workflow.description ?? '';
      _items = wf.items.map((i) => i.itemText).toList();
      _selectedCustomerIds = wf.customers.map((c) => c.id).toList();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _itemCtrl.dispose();
    super.dispose();
  }

  void _addItem() {
    final text = _itemCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add(text);
      _itemCtrl.clear();
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);

    String wfId;
    if (widget.existing == null) {
      // Neu anlegen
      wfId = 'wf_${DateTime.now().millisecondsSinceEpoch}';
      await db.into(db.workflows).insert(WorkflowsCompanion.insert(
            id: drift.Value(wfId),
            name: _nameCtrl.text.trim(),
            description: drift.Value(_descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim()),
          ));
    } else {
      wfId = widget.existing!.workflow.id;
      await (db.update(db.workflows)..where((w) => w.id.equals(wfId))).write(
        WorkflowsCompanion(
          name: drift.Value(_nameCtrl.text.trim()),
          description: drift.Value(
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim()),
        ),
      );
      // Alte Items + Kunden löschen
      await (db.delete(db.workflowItems)
            ..where((i) => i.workflowId.equals(wfId)))
          .go();
      await (db.delete(db.workflowCustomers)
            ..where((wc) => wc.workflowId.equals(wfId)))
          .go();
    }

    // Items speichern
    for (var i = 0; i < _items.length; i++) {
      await db.into(db.workflowItems).insert(WorkflowItemsCompanion.insert(
            workflowId: wfId,
            itemText: _items[i],
            sortOrder: drift.Value(i),
          ));
    }

    // Kunden speichern
    for (final cId in _selectedCustomerIds) {
      await db.into(db.workflowCustomers).insert(
            WorkflowCustomersCompanion.insert(
                workflowId: wfId, customerId: cId),
          );
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Text(
                    widget.existing == null
                        ? 'Neuer Workflow'
                        : 'Workflow bearbeiten',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  FilledButton(
                      onPressed: _save, child: const Text('Speichern')),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Beschreibung'),
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 20),

                  // Kunden
                  customersAsync.maybeWhen(
                    data: (customers) => customers.isEmpty
                        ? const SizedBox()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Kunden (optional)',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: customers
                                    .map((c) => FilterChip(
                                          label: Text(c.name),
                                          selected: _selectedCustomerIds
                                              .contains(c.id),
                                          onSelected: (v) => setState(() {
                                            if (v) {
                                              _selectedCustomerIds.add(c.id);
                                            } else {
                                              _selectedCustomerIds.remove(c.id);
                                            }
                                          }),
                                        ))
                                    .toList(),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                    orElse: () => const SizedBox(),
                  ),

                  // Checklistenpunkte
                  Text('Checklistenpunkte',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _itemCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Neuer Punkt...',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addItem(),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                          icon: const Icon(Icons.add), onPressed: _addItem),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _items.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _items.removeAt(oldIndex);
                        _items.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (_, i) => ListTile(
                      key: ValueKey(i),
                      dense: true,
                      leading: const Icon(Icons.drag_handle),
                      title: Text(_items[i]),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            setState(() => _items.removeAt(i)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
