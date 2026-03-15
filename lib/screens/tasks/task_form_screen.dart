import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/database_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../db/database.dart';

class TaskFormScreen extends ConsumerStatefulWidget {
  final String? taskId;
  const TaskFormScreen({super.key, this.taskId});

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _customerId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.taskId != null) _loadTask();
  }

  Future<void> _loadTask() async {
    final db = ref.read(databaseProvider);
    final task = await (db.select(db.tasks)
          ..where((t) => t.id.equals(widget.taskId!)))
        .getSingleOrNull();
    if (task != null) {
      _titleCtrl.text = task.title;
      _descCtrl.text = task.description ?? '';
      setState(() => _customerId = task.customerId);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final db = ref.read(databaseProvider);
    final now = DateTime.now();

    if (widget.taskId == null) {
      await db.into(db.tasks).insert(TasksCompanion.insert(
            title: _titleCtrl.text.trim(),
            description: drift.Value(_descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim()),
            customerId: drift.Value(_customerId),
            updatedAt: drift.Value(now),
          ));
    } else {
      await (db.update(db.tasks)
            ..where((t) => t.id.equals(widget.taskId!)))
          .write(TasksCompanion(
        title: drift.Value(_titleCtrl.text.trim()),
        description: drift.Value(
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim()),
        customerId: drift.Value(_customerId),
        updatedAt: drift.Value(now),
      ));
    }

    ref.invalidate(tasksProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.taskId == null ? 'Neuer Task' : 'Task bearbeiten'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titel *',
                hintText: 'z.B. PC Einrichtung - Müller GmbH',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Titel erforderlich' : null,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Beschreibung',
                hintText: 'Optionale Details...',
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            customersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox(),
              data: (customers) => DropdownButtonFormField<String>(
                value: _customerId,
                decoration: const InputDecoration(labelText: 'Kunde'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Kein Kunde')),
                  ...customers.map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name),
                      )),
                ],
                onChanged: (v) => setState(() => _customerId = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
