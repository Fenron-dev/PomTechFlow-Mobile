import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../providers/customers_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import 'customer_quick_create.dart';

/// Leichtes Sheet zum schnellen Zuordnen von Titel / Kunde / Techniker an einen
/// (ggf. laufenden) Task – ohne das volle Bearbeiten-Formular.
Future<void> showQuickAssignSheet(
    BuildContext context, WidgetRef ref, String taskId) async {
  final db = ref.read(databaseProvider);
  final task = await (db.select(db.tasks)..where((t) => t.id.equals(taskId)))
      .getSingleOrNull();
  if (task == null || !context.mounted) return;
  final defaultTech =
      ref.read(settingsProvider).valueOrNull?.technicianName ?? '';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _QuickAssignSheet(task: task, defaultTechnician: defaultTech),
  );
}

class _QuickAssignSheet extends ConsumerStatefulWidget {
  final Task task;
  final String defaultTechnician;
  const _QuickAssignSheet(
      {required this.task, required this.defaultTechnician});

  @override
  ConsumerState<_QuickAssignSheet> createState() => _QuickAssignSheetState();
}

class _QuickAssignSheetState extends ConsumerState<_QuickAssignSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _techCtrl;
  String? _customerId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
    final tech = (widget.task.assignedTo?.isNotEmpty ?? false)
        ? widget.task.assignedTo!
        : widget.defaultTechnician;
    _techCtrl = TextEditingController(text: tech);
    _customerId = widget.task.customerId;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _techCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    drift.Value<String?> nv(String s) =>
        drift.Value(s.trim().isEmpty ? null : s.trim());
    await (db.update(db.tasks)..where((t) => t.id.equals(widget.task.id)))
        .write(TasksCompanion(
      title: drift.Value(title),
      customerId: drift.Value(_customerId),
      assignedTo: nv(_techCtrl.text),
      updatedAt: drift.Value(DateTime.now()),
    ));
    ref.invalidate(tasksProvider);
    ref.invalidate(taskDetailProvider(widget.task.id));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.sell_outlined),
            const SizedBox(width: 10),
            Text('Task zuordnen',
                style: Theme.of(context).textTheme.titleLarge),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Titel *'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          customersAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Fehler: $e'),
            data: (customers) => Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _customerId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kunde'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Kein Kunde')),
                    ...customers.map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setState(() => _customerId = v),
                ),
              ),
              IconButton(
                tooltip: 'Neuer Kunde',
                icon: const Icon(Icons.person_add_outlined),
                onPressed: () async {
                  final id = await showQuickCreateCustomerDialog(context, ref);
                  if (id != null && mounted) setState(() => _customerId = id);
                },
              ),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _techCtrl,
            decoration: const InputDecoration(labelText: 'Techniker'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Speichern'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
