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
import '../../providers/settings_provider.dart';
import '../../widgets/customer_picker.dart';
import '../../sync/sync_provider.dart';
import '../knowledge/knowledge_screen.dart' show knowledgeProvider;

class TaskFormScreen extends ConsumerStatefulWidget {
  final String? taskId;
  /// Bei neuem Task: Kunde vorauswählen (z.B. aus dem Kunden-Cockpit).
  final String? initialCustomerId;
  const TaskFormScreen({super.key, this.taskId, this.initialCustomerId});

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _assignedToCtrl = TextEditingController();
  String? _customerId;
  String _priority = 'NORMAL';
  DateTime? _plannedDate;
  bool _recurring = false;
  String _recurrenceType = 'WEEKLY';
  int _recurrenceInterval = 1;
  int? _recurrenceWeekday; // 1=Mo..7=So
  int? _recurrenceMonthDay; // 1..31
  final _budgetCtrl = TextEditingController();
  bool _loading = false;
  int _reminderOffsetValue = 0; // 0 = zur geplanten Zeit
  String _reminderUnit = 'MIN'; // MIN | HOUR | DAY | WEEK

  @override
  void initState() {
    super.initState();
    if (widget.taskId != null) {
      _loadTask();
    } else {
      _customerId = widget.initialCustomerId;
      // Neue Tasks: Techniker mit aktuellem Benutzer vorbelegen.
      _assignedToCtrl.text =
          ref.read(settingsProvider).valueOrNull?.technicianName ?? '';
    }
    _titleCtrl.addListener(() => setState(() {}));
  }

  Future<void> _loadTask() async {
    final db = ref.read(databaseProvider);
    final task = await (db.select(db.tasks)
          ..where((t) => t.id.equals(widget.taskId!)))
        .getSingleOrNull();
    if (!mounted || task == null) return;
    _titleCtrl.text = task.title;
    _descCtrl.text = task.description ?? '';
    _assignedToCtrl.text = task.assignedTo ?? '';
    setState(() {
      _customerId = task.customerId;
      _priority = task.priority;
      _plannedDate = task.plannedDate;
      _recurring = task.recurring;
      _recurrenceType = task.recurrenceType ?? 'WEEKLY';
      _recurrenceInterval = task.recurrenceInterval;
      _recurrenceWeekday = task.recurrenceWeekday;
      _recurrenceMonthDay = task.recurrenceMonthDay;
      if (task.estimatedMinutes != null) {
        _budgetCtrl.text = task.estimatedMinutes.toString();
      }
      final offsetMin = task.reminderOffsetMinutes ?? 0;
      if (offsetMin <= 0) {
        _reminderOffsetValue = 0;
        _reminderUnit = 'MIN';
      } else if (offsetMin % (7 * 24 * 60) == 0) {
        _reminderOffsetValue = offsetMin ~/ (7 * 24 * 60);
        _reminderUnit = 'WEEK';
      } else if (offsetMin % (24 * 60) == 0) {
        _reminderOffsetValue = offsetMin ~/ (24 * 60);
        _reminderUnit = 'DAY';
      } else if (offsetMin % 60 == 0) {
        _reminderOffsetValue = offsetMin ~/ 60;
        _reminderUnit = 'HOUR';
      } else {
        _reminderOffsetValue = offsetMin;
        _reminderUnit = 'MIN';
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _assignedToCtrl.dispose();
    _budgetCtrl.dispose();
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

  int _computeReminderOffsetMinutes() {
    if (_reminderOffsetValue <= 0) return 0;
    return switch (_reminderUnit) {
      'WEEK' => _reminderOffsetValue * 7 * 24 * 60,
      'DAY' => _reminderOffsetValue * 24 * 60,
      'HOUR' => _reminderOffsetValue * 60,
      _ => _reminderOffsetValue,
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final db = ref.read(databaseProvider);
      final now = DateTime.now();

      final budget = int.tryParse(_budgetCtrl.text.trim());
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
              estimatedMinutes: drift.Value(budget),
              reminderOffsetMinutes: drift.Value(_computeReminderOffsetMinutes()),
              assignedTo: drift.Value(_assignedToCtrl.text.trim().isEmpty
                  ? null
                  : _assignedToCtrl.text.trim()),
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
          estimatedMinutes: drift.Value(budget),
          reminderOffsetMinutes: drift.Value(_computeReminderOffsetMinutes()),
          assignedTo: drift.Value(_assignedToCtrl.text.trim().isEmpty
              ? null
              : _assignedToCtrl.text.trim()),
          updatedAt: drift.Value(now),
        ));
      }

      ref.invalidate(tasksProvider);

      // Notification schedulieren/abbrechen — Fehler blockieren das Speichern nicht
      try {
        if (_plannedDate != null) {
          final offsetMin = _computeReminderOffsetMinutes();
          final reminderTime = offsetMin > 0
              ? _plannedDate!.subtract(Duration(minutes: offsetMin))
              : _plannedDate!;
          if (reminderTime.isAfter(DateTime.now())) {
            await NotificationService.scheduleTaskReminder(
              widget.taskId ?? 'new_${DateTime.now().millisecondsSinceEpoch}',
              _titleCtrl.text.trim(),
              reminderTime,
            );
          } else if (widget.taskId != null) {
            await NotificationService.cancelTaskReminder(widget.taskId!);
          }
        } else if (widget.taskId != null) {
          await NotificationService.cancelTaskReminder(widget.taskId!);
        }
      } catch (_) {
        // Notification-Fehler (z.B. fehlende Berechtigung) blockieren das Speichern nicht
      }

      // Trigger sync if connected as CLIENT (fire and forget)
      final settings = ref.read(settingsProvider).valueOrNull;
      if (settings != null &&
          settings.syncRole == 'CLIENT' &&
          settings.syncServerHost.isNotEmpty) {
        triggerManualSync(ref);
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

  List<Widget> _buildKbSuggestions(
      BuildContext context, ColorScheme cs, List<KnowledgeEntry> suggestions) {
    if (suggestions.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: suggestions
            .map((e) => ActionChip(
                  avatar: Icon(Icons.menu_book_outlined,
                      size: 14, color: cs.secondary),
                  label: Text(e.title,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: cs.secondary)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showKbEntry(context, e),
                ))
            .toList(),
      ),
    ];
  }

  void _showKbEntry(BuildContext context, KnowledgeEntry entry) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(entry.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Problem',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(
                          color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 4),
              Text(entry.problem),
              const SizedBox(height: 12),
              Text('Lösung',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(
                          color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 4),
              SelectableText(entry.solution),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Schließen')),
        ],
      ),
    );
  }

  List<KnowledgeEntry> _filterKb(List<KnowledgeEntry> all, String title) {
    if (title.length < 3) return const [];
    final q = title.toLowerCase();
    return all.where((e) {
      return e.title.toLowerCase().contains(q) ||
          e.problem.toLowerCase().contains(q) ||
          (e.tags?.toLowerCase().contains(q) ?? false);
    }).take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);
    final cs = Theme.of(context).colorScheme;
    final kbAll = ref.watch(knowledgeProvider).valueOrNull ?? const [];

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
            ..._buildKbSuggestions(context, cs, _filterKb(kbAll, _titleCtrl.text.trim())),
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
              error: (_, _) => const SizedBox(),
              data: (customers) {
                final sel = {for (final c in customers) c.id: c}[_customerId];
                return InkWell(
                  onTap: () async {
                    final res = await showCustomerPicker(context, ref,
                        selectedId: _customerId);
                    if (res != null) {
                      setState(() => _customerId = res.customerId);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Kunde',
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sel?.name ?? 'Kein Kunde',
                            style: sel == null
                                ? TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.outline)
                                : null,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                );
              },
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
                        icon: Tooltip(message: 'Niedrig', child: Icon(Icons.arrow_downward, size: 16))),
                    ButtonSegment(
                        value: 'NORMAL',
                        icon: Tooltip(message: 'Normal', child: Icon(Icons.remove, size: 16))),
                    ButtonSegment(
                        value: 'HIGH',
                        icon: Tooltip(message: 'Hoch', child: Icon(Icons.arrow_upward, size: 16))),
                    ButtonSegment(
                        value: 'CRITICAL',
                        icon: Tooltip(message: 'Kritisch', child: Icon(Icons.priority_high, size: 16))),
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

            // ── Zugewiesen an ──────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _assignedToCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Zugewiesen an',
                      hintText: 'Techniker-Name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Consumer(builder: (context, ref, _) {
                  final techName = ref.watch(settingsProvider).valueOrNull?.technicianName ?? '';
                  return Tooltip(
                    message: 'Mir zuweisen ($techName)',
                    child: IconButton(
                      icon: const Icon(Icons.assignment_ind_outlined),
                      onPressed: techName.isEmpty
                          ? null
                          : () => setState(() => _assignedToCtrl.text = techName),
                    ),
                  );
                }),
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

            // ── Erinnerung ────────────────────────────────────────────
            if (_plannedDate != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_outlined, size: 20, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Erinnerung',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: cs.outline)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              SizedBox(
                                width: 64,
                                child: TextFormField(
                                  initialValue: _reminderOffsetValue > 0
                                      ? '$_reminderOffsetValue'
                                      : '',
                                  decoration: const InputDecoration(
                                    hintText: '0',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => setState(() =>
                                      _reminderOffsetValue =
                                          int.tryParse(v) ?? 0),
                                ),
                              ),
                              const SizedBox(width: 8),
                              DropdownButton<String>(
                                value: _reminderUnit,
                                isDense: true,
                                underline: const SizedBox(),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'MIN', child: Text('Minuten')),
                                  DropdownMenuItem(
                                      value: 'HOUR', child: Text('Stunden')),
                                  DropdownMenuItem(
                                      value: 'DAY', child: Text('Tage')),
                                  DropdownMenuItem(
                                      value: 'WEEK', child: Text('Wochen')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _reminderUnit = v!),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _reminderOffsetValue <= 0
                                    ? 'zur geplanten Zeit'
                                    : 'vorher',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Zeitbudget ────────────────────────────────────────────
            TextField(
              controller: _budgetCtrl,
              decoration: const InputDecoration(
                labelText: 'Zeitbudget (Minuten, optional)',
                hintText: 'z.B. 60',
                helperText: 'Warnung wenn Aufwand das Budget überschreitet',
                suffixText: 'Min',
              ),
              keyboardType: TextInputType.number,
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
                      initialValue: _recurrenceType,
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
