import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
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
  DateTime? _plannedDate;
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
      setState(() {
        _customerId = task.customerId;
        _plannedDate = task.plannedDate;
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _plannedDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    // Optional: Uhrzeit
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_plannedDate ?? now),
    );
    setState(() {
      _plannedDate = time == null
          ? picked
          : DateTime(picked.year, picked.month, picked.day,
              time.hour, time.minute);
    });
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
            plannedDate: drift.Value(_plannedDate),
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
        plannedDate: drift.Value(_plannedDate),
        updatedAt: drift.Value(now),
      ));
    }

    ref.invalidate(tasksProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.taskId == null ? 'Neuer Task' : 'Task bearbeiten'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(onPressed: _save, child: const Text('Speichern')),
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
            const SizedBox(height: 16),

            // ── Geplantes Datum ────────────────────────────────────────
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 20, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Geplantes Datum',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: cs.outline)),
                          Text(
                            _plannedDate == null
                                ? 'Kein Datum gesetzt'
                                : DateFormat('EEE, dd.MM.yyyy – HH:mm',
                                        'de_DE')
                                    .format(_plannedDate!),
                            style: _plannedDate == null
                                ? Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: cs.outline)
                                : Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (_plannedDate != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _plannedDate = null),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
