import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/database_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../db/database.dart';
import '../../services/notification_service.dart';

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
  String _priority = 'NORMAL';
  DateTime? _plannedDate;
  bool _recurring = false;
  String _recurrenceType = 'WEEKLY';
  int _recurrenceInterval = 1;
  int? _recurrenceWeekday; // 1=Mo..7=So
  int? _recurrenceMonthDay; // 1..31
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
        _priority = task.priority;
        _plannedDate = task.plannedDate;
        _recurring = task.recurring;
        _recurrenceType = task.recurrenceType ?? 'WEEKLY';
        _recurrenceInterval = task.recurrenceInterval;
        _recurrenceWeekday = task.recurrenceWeekday;
        _recurrenceMonthDay = task.recurrenceMonthDay;
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
    if (picked == null || !mounted) return;
    // Optional: Uhrzeit
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_plannedDate ?? now),
    );
    if (!mounted) return;
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

    try {
      final db = ref.read(databaseProvider);
      final now = DateTime.now();

      if (widget.taskId == null) {
        await db.into(db.tasks).insert(TasksCompanion.insert(
              title: _titleCtrl.text.trim(),
              description: drift.Value(_descCtrl.text.trim().isEmpty
                  ? null
                  : _descCtrl.text.trim()),
              customerId: drift.Value(_customerId),
              priority: drift.Value(_priority),
              plannedDate: drift.Value(_plannedDate),
              recurring: drift.Value(_recurring),
              recurrenceType:
                  drift.Value(_recurring ? _recurrenceType : null),
              recurrenceInterval: drift.Value(_recurrenceInterval),
              recurrenceWeekday: drift.Value(
                  _recurring && _recurrenceType == 'WEEKLY'
                      ? _recurrenceWeekday
                      : null),
              recurrenceMonthDay: drift.Value(
                  _recurring && _recurrenceType == 'MONTHLY'
                      ? _recurrenceMonthDay
                      : null),
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
          priority: drift.Value(_priority),
          plannedDate: drift.Value(_plannedDate),
          recurring: drift.Value(_recurring),
          recurrenceType: drift.Value(_recurring ? _recurrenceType : null),
          recurrenceInterval: drift.Value(_recurrenceInterval),
          recurrenceWeekday: drift.Value(
              _recurring && _recurrenceType == 'WEEKLY'
                  ? _recurrenceWeekday
                  : null),
          recurrenceMonthDay: drift.Value(
              _recurring && _recurrenceType == 'MONTHLY'
                  ? _recurrenceMonthDay
                  : null),
          updatedAt: drift.Value(now),
        ));
      }

      ref.invalidate(tasksProvider);

      // Notification schedulieren/abbrechen — Fehler blockieren das Speichern nicht
      try {
        if (_plannedDate != null && _plannedDate!.isAfter(DateTime.now())) {
          await NotificationService.scheduleTaskReminder(
            widget.taskId ?? 'new_${DateTime.now().millisecondsSinceEpoch}',
            _titleCtrl.text.trim(),
            _plannedDate!,
          );
        } else if (widget.taskId != null) {
          await NotificationService.cancelTaskReminder(widget.taskId!);
        }
      } catch (_) {
        // Notification-Fehler (z.B. fehlende Berechtigung) blockieren das Speichern nicht
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Speichern: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

            // ── Priorität ─────────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Priorität',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.outline)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'LOW',
                        label: Text('Niedrig'),
                        icon: Icon(Icons.arrow_downward, size: 16)),
                    ButtonSegment(
                        value: 'NORMAL',
                        label: Text('Normal'),
                        icon: Icon(Icons.remove, size: 16)),
                    ButtonSegment(
                        value: 'HIGH',
                        label: Text('Hoch'),
                        icon: Icon(Icons.arrow_upward, size: 16)),
                    ButtonSegment(
                        value: 'CRITICAL',
                        label: Text('Kritisch'),
                        icon: Icon(Icons.priority_high, size: 16)),
                  ],
                  selected: {_priority},
                  onSelectionChanged: (s) =>
                      setState(() => _priority = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
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
            const SizedBox(height: 16),

            // ── Wiederkehrend ──────────────────────────────────────────
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
              title: const Text('Wiederkehrender Task'),
              subtitle: const Text('Neuer Task nach Abschluss'),
              secondary: Icon(
                Icons.repeat,
                color: _recurring ? cs.primary : cs.outline,
              ),
            ),
            if (_recurring) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _recurrenceType,
                      decoration:
                          const InputDecoration(labelText: 'Intervall'),
                      items: const [
                        DropdownMenuItem(
                            value: 'DAILY', child: Text('Täglich')),
                        DropdownMenuItem(
                            value: 'WEEKLY', child: Text('Wöchentlich')),
                        DropdownMenuItem(
                            value: 'MONTHLY', child: Text('Monatlich')),
                        DropdownMenuItem(
                            value: 'QUARTERLY',
                            child: Text('Vierteljährlich')),
                      ],
                      onChanged: (v) =>
                          setState(() => _recurrenceType = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: _recurrenceInterval > 1
                              ? () => setState(
                                  () => _recurrenceInterval--)
                              : null,
                        ),
                        Text('$_recurrenceInterval',
                            style:
                                Theme.of(context).textTheme.titleMedium),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _recurrenceInterval < 52
                              ? () => setState(
                                  () => _recurrenceInterval++)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Alle $_recurrenceInterval ${_recurrenceLabel(_recurrenceType)}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: cs.primary),
                ),
              ),

              // Wochentag-Picker für WEEKLY
              if (_recurrenceType == 'WEEKLY') ...[
                const SizedBox(height: 12),
                Text('Am Wochentag',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: cs.outline)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (int day = 1; day <= 7; day++)
                      ChoiceChip(
                        label: Text(_weekdayLabel(day)),
                        selected: _recurrenceWeekday == day,
                        onSelected: (_) => setState(() =>
                            _recurrenceWeekday =
                                _recurrenceWeekday == day ? null : day),
                      ),
                  ],
                ),
              ],

              // Monatstag-Picker für MONTHLY
              if (_recurrenceType == 'MONTHLY') ...[
                const SizedBox(height: 12),
                Text('Am Tag des Monats',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: cs.outline)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (int d = 1; d <= 28; d++)
                      ChoiceChip(
                        label: Text('$d.'),
                        selected: _recurrenceMonthDay == d,
                        onSelected: (_) => setState(() =>
                            _recurrenceMonthDay =
                                _recurrenceMonthDay == d ? null : d),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (_recurrenceMonthDay == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Kein Tag gewählt → nach Intervall wiederholen',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: cs.outline),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _recurrenceLabel(String type) => switch (type) {
        'DAILY' => _recurrenceInterval == 1 ? 'Tag' : 'Tage',
        'WEEKLY' => _recurrenceInterval == 1 ? 'Woche' : 'Wochen',
        'MONTHLY' => _recurrenceInterval == 1 ? 'Monat' : 'Monate',
        'QUARTERLY' => _recurrenceInterval == 1 ? 'Quartal' : 'Quartale',
        _ => type,
      };

  String _weekdayLabel(int day) => switch (day) {
        1 => 'Mo',
        2 => 'Di',
        3 => 'Mi',
        4 => 'Do',
        5 => 'Fr',
        6 => 'Sa',
        7 => 'So',
        _ => '$day',
      };
}
