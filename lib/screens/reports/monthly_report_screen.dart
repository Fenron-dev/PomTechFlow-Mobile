import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
import '../../db/database.dart';
import '../../services/pdf_service.dart';
import 'package:printing/printing.dart';
import 'package:drift/drift.dart' as drift;

class MonthlyReportScreen extends ConsumerStatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  ConsumerState<MonthlyReportScreen> createState() =>
      _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends ConsumerState<MonthlyReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String? _customerId; // null = all customers
  bool _generating = false;
  bool _markBilled = false;

  void _prevMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
  void _nextMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month + 1, 1));

  List<TaskWithDetails> _filterTasks(List<TaskWithDetails> all) {
    final start = _month;
    final end = DateTime(_month.year, _month.month + 1, 1);
    return all.where((t) {
      // Customer filter
      if (_customerId != null && t.task.customerId != _customerId) return false;
      // Month filter: prefer plannedDate, fallback to createdAt
      final date = t.task.plannedDate ?? t.task.createdAt;
      return date.isAfter(start.subtract(const Duration(seconds: 1))) &&
          date.isBefore(end);
    }).toList();
  }

  Future<void> _generate(List<TaskWithDetails> filteredTasks) async {
    setState(() => _generating = true);
    try {
      final settings = ref.read(settingsProvider).valueOrNull;
      final customersAsync = ref.read(customersProvider);
      final allCustomers = customersAsync.valueOrNull ?? [];
      final customer = _customerId == null
          ? null
          : allCustomers.firstWhere((c) => c.id == _customerId,
              orElse: () => allCustomers.first);

      Uint8List? logoBytes;
      if (settings?.logoPath != null) {
        final f = File(settings!.logoPath!);
        if (await f.exists()) logoBytes = await f.readAsBytes();
      }

      final file = await PdfService.generateMonthlyReport(
        tasks: filteredTasks,
        customer: customer,
        month: _month,
        companyName: settings?.companyName ?? 'IT-Firma',
        technicianName: settings?.technicianName ?? '',
        aeMinutes: (settings?.aeMinutes ?? 10).toDouble(),
        logoBytes: logoBytes,
        storageBasePath: settings?.storageBasePath ?? '',
      );

      if (_markBilled) {
        final db = ref.read(databaseProvider);
        final now = DateTime.now();
        for (final t in filteredTasks) {
          if (t.task.billedAt == null) {
            await (db.update(db.tasks)
                  ..where((row) => row.id.equals(t.task.id)))
                .write(TasksCompanion(billedAt: drift.Value(now)));
          }
        }
        ref.invalidate(tasksProvider);
      }

      await Printing.sharePdf(
        bytes: await file.readAsBytes(),
        filename: file.path.split('/').last,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);
    final customersAsync = ref.watch(customersProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final aeMin = settings?.aeMinutes ?? 10;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Monatsabschluss')),
      body: Column(
        children: [
          // ── Filter-Leiste ──────────────────────────────────────────
          Container(
            color: cs.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Monat-Picker
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _prevMonth,
                    ),
                    SizedBox(
                      width: 160,
                      child: Text(
                        DateFormat('MMMM yyyy', 'de_DE').format(_month),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _nextMonth,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Kunden-Filter
                customersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox(),
                  data: (customers) => DropdownButtonFormField<String?>(
                    value: _customerId,
                    decoration: const InputDecoration(
                      labelText: 'Kunde',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Alle Kunden')),
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
          const Divider(height: 1),

          // ── Task-Liste ─────────────────────────────────────────────
          Expanded(
            child: tasksAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (all) {
                final filtered = _filterTasks(all);
                final totalMinutes = filtered.fold<int>(
                    0, (s, t) => s + t.task.totalMinutes);
                final totalAe = filtered.fold<int>(
                    0, (s, t) => s + t.aeCount(aeMin));

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 56,
                            color: cs.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          'Keine Tasks für diesen Monat',
                          style: TextStyle(color: cs.outline),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    // Zusammenfassung
                    Container(
                      color: cs.primaryContainer.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SummaryChip(
                              label: 'Tasks',
                              value: '${filtered.length}',
                            ),
                          ),
                          Expanded(
                            child: _SummaryChip(
                              label: 'Minuten',
                              value: '$totalMinutes',
                            ),
                          ),
                          Expanded(
                            child: _SummaryChip(
                              label: 'AE',
                              value: '$totalAe',
                              highlight: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Task-Liste
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
                        itemBuilder: (_, i) {
                          final t = filtered[i];
                          final ae = t.aeCount(aeMin);
                          return ListTile(
                            dense: true,
                            tileColor: t.task.billedAt != null
                                ? cs.secondaryContainer.withValues(alpha: 0.3)
                                : null,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            leading: Icon(
                              t.task.billedAt != null
                                  ? Icons.receipt_long
                                  : Icons.task_outlined,
                              size: 20,
                              color: t.task.billedAt != null
                                  ? cs.primary
                                  : cs.outline,
                            ),
                            title: Text(t.task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: t.customer != null
                                ? Text(t.customer!.name)
                                : null,
                            trailing: Text(
                              '${t.task.totalMinutes}m · $ae AE',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: cs.primary,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Als abgerechnet markieren
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _markBilled,
                              onChanged: (v) =>
                                  setState(() => _markBilled = v ?? false),
                              title: const Text(
                                  'Alle als abgerechnet markieren'),
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              dense: true,
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _generating
                                ? null
                                : () => _generate(filtered),
                            icon: _generating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : const Icon(Icons.picture_as_pdf_outlined),
                            label: Text(
                                _generating ? 'Erstelle...' : 'PDF erstellen'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _SummaryChip(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: highlight ? cs.primary : null),
        ),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.outline)),
      ],
    );
  }
}
