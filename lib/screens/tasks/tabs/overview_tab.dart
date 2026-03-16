import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../providers/tasks_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/timer_provider.dart';
import '../../../db/database.dart';
import 'package:drift/drift.dart' as drift;
import '../../../services/pdf_service.dart';
import '../../../services/email_service.dart';
import '../../../services/zip_export_service.dart';
import '../../../widgets/timer_session_dialogs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OverviewTab extends ConsumerStatefulWidget {
  final TaskWithDetails detail;
  final bool isActiveTask;
  final VoidCallback onStartTimer;
  final VoidCallback onMarkDone;

  const OverviewTab({
    super.key,
    required this.detail,
    required this.isActiveTask,
    required this.onStartTimer,
    required this.onMarkDone,
  });

  @override
  ConsumerState<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<OverviewTab> {
  bool _generatingPdf = false;
  bool _exportingZip = false;
  List<File> _previousReports = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final reports = await PdfService.listReports(widget.detail.task.id);
    if (mounted) setState(() => _previousReports = reports);
  }

  Future<void> _generatePdf() async {
    setState(() => _generatingPdf = true);
    try {
      final db = ref.read(databaseProvider);
      final settings = ref.read(settingsProvider).valueOrNull;
      final taskId = widget.detail.task.id;

      final todos = await (db.select(db.todos)
            ..where((t) => t.taskId.equals(taskId)))
          .get();
      final hardware = await (db.select(db.hardware)
            ..where((h) => h.taskId.equals(taskId)))
          .get();
      final notes = await (db.select(db.notes)
            ..where((n) => n.taskId.equals(taskId)))
          .get();

      Uint8List? logoBytes;
      if (settings?.logoPath != null) {
        final logoFile = File(settings!.logoPath!);
        if (await logoFile.exists()) logoBytes = await logoFile.readAsBytes();
      }
      final file = await PdfService.generateReport(PdfReportData(
        taskDetail: widget.detail,
        todos: todos,
        hardware: hardware,
        notes: notes,
        companyName: settings?.companyName ?? 'IT-Firma',
        technicianName: settings?.technicianName ?? '',
        aeMinutes: (settings?.aeMinutes ?? 10).toDouble(),
        logoBytes: logoBytes,
      ));
      await PdfService.shareReport(file);
      _loadReports();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _exportZip() async {
    setState(() => _exportingZip = true);
    try {
      final db = ref.read(databaseProvider);
      final settings = ref.read(settingsProvider).valueOrNull;
      await ZipExportService.exportTaskPackage(
        db: db,
        detail: widget.detail,
        settings: settings,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ZIP Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingZip = false);
    }
  }

  Future<void> _emailReport() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    final detail = widget.detail;
    final aeMin = settings?.aeMinutes ?? 10;
    await EmailService.sendReportEmail(
      customerEmail: detail.customer?.email,
      customerName: detail.customer?.name,
      taskTitle: detail.task.title,
      totalMinutes: detail.task.totalMinutes,
      aeCount: detail.aeCount(aeMin),
      technicianName: settings?.technicianName ?? '',
      companyName: settings?.companyName ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final detail = widget.detail;
    final onMarkDone = widget.onMarkDone;
    final task = detail.task;
    final aeMin = settings?.aeMinutes ?? 10;
    final ae = detail.aeCount(aeMin);
    final cs = Theme.of(context).colorScheme;
    final timerMap = ref.watch(timerProvider);
    final timerNotifier = ref.read(timerProvider.notifier);
    final isThisTask = timerMap.containsKey(task.id);
    final isRunning = timerMap[task.id]?.status == TimerStatus.running;
    final isPaused = timerMap[task.id]?.status == TimerStatus.paused;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status-Banner
        _StatusBanner(status: task.status),
        const SizedBox(height: 16),

        // ── Timer-Widget ──────────────────────────────────────────────
        if (task.status != 'COMPLETED')
          _TaskTimerWidget(
            taskId: task.id,
            timerEntry: timerMap[task.id],
            isThisTask: isThisTask,
            isRunning: isRunning,
            isPaused: isPaused,
            onStart: () async {
              final go = await showTimerStartDialog(context, ref, task.id);
              if (go && context.mounted) await timerNotifier.start(task.id);
            },
            onPause: () => timerNotifier.pause(task.id),
            onResume: () => timerNotifier.resume(task.id),
            onStop: () async {
              await handleTimerStop(context, ref, task.id);
              ref.invalidate(todosProvider(task.id));
              ref.invalidate(notesProvider(task.id));
            },
            onMarkDone: onMarkDone,
          ),
        const SizedBox(height: 8),
        // PDF Bericht + ZIP Paket
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _generatingPdf ? null : _generatePdf,
                icon: _generatingPdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(_generatingPdf ? 'Erstelle...' : 'PDF'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportingZip ? null : _exportZip,
                icon: _exportingZip
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.folder_zip_outlined),
                label: Text(_exportingZip ? 'Erstelle...' : 'ZIP Paket'),
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: _emailReport,
              icon: const Icon(Icons.email_outlined),
              label: const Text('Mail'),
            ),
          ],
        ),
        // Frühere Berichte
        if (_previousReports.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ReportHistory(
            reports: _previousReports,
            onRefresh: _loadReports,
          ),
        ],
        const SizedBox(height: 20),

        // Statistiken
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Arbeitseinheiten',
                value: ae.toString(),
                unit: 'AE',
                icon: Icons.timer_outlined,
                color: cs.primaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Zeitaufwand',
                value: task.totalMinutes.toString(),
                unit: 'Min',
                icon: Icons.schedule,
                color: cs.secondaryContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Checkliste',
                value: '${detail.todoDoneCount}/${detail.todoCount}',
                unit: 'Punkte',
                icon: Icons.checklist,
                color: cs.tertiaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Sessions',
                value: detail.sessionCount.toString(),
                unit: 'Pomodoros',
                icon: Icons.repeat,
                color: cs.surfaceContainerHighest,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Sessions
        _SessionsSection(taskId: task.id, onChanged: () {
          ref.invalidate(sessionsProvider(task.id));
          ref.invalidate(tasksProvider);
          ref.invalidate(taskDetailProvider(task.id));
        }),

        const SizedBox(height: 20),

        // Kunde mit Kontakt-Buttons
        if (detail.customer != null)
          _CustomerContactRow(customer: detail.customer!),

        // Beschreibung
        if (task.description != null && task.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.description_outlined,
            label: 'Beschreibung',
            value: task.description!,
          ),
        ],

        const SizedBox(height: 12),
        _InfoRow(
          icon: Icons.calendar_today_outlined,
          label: 'Erstellt',
          value: DateFormat('dd.MM.yyyy HH:mm').format(task.createdAt.toLocal()),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (color, icon, label) = switch (status) {
      'ACTIVE' => (cs.primaryContainer, Icons.play_circle_outline, 'Aktiv'),
      'COMPLETED' => (
          cs.secondaryContainer,
          Icons.check_circle_outline,
          'Abgeschlossen'
        ),
      'PAUSED' => (cs.tertiaryContainer, Icons.pause_circle_outline, 'Pausiert'),
      _ => (cs.surfaceContainerHighest, Icons.schedule, 'Geplant'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 3),
                    Text(unit,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.outline)),
                  ],
                ),
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: cs.outline)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Timer Widget ────────────────────────────────────────────────────────────

class _TaskTimerWidget extends StatelessWidget {
  final String taskId;
  final TimerEntry? timerEntry;
  final bool isThisTask;
  final bool isRunning;
  final bool isPaused;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onMarkDone;

  const _TaskTimerWidget({
    required this.taskId,
    required this.timerEntry,
    required this.isThisTask,
    required this.isRunning,
    required this.isPaused,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onMarkDone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: isRunning
          ? cs.primaryContainer
          : isPaused
              ? cs.tertiaryContainer
              : cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Zeitanzeige
            if (isThisTask && timerEntry != null) ...[
              Text(
                timerEntry!.timeString,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isRunning ? cs.primary : cs.tertiary,
                    ),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: timerEntry!.progress,
                backgroundColor: cs.surfaceContainerHighest,
              ),
              const SizedBox(height: 12),
            ],
            // Buttons
            Row(
              children: [
                if (!isThisTask)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Timer starten'),
                    ),
                  )
                else ...[
                  if (isRunning)
                    IconButton.filled(
                      onPressed: onPause,
                      icon: const Icon(Icons.pause),
                      tooltip: 'Pausieren',
                    )
                  else
                    IconButton.filled(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow),
                      tooltip: 'Fortsetzen',
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onStop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stoppen & speichern'),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onMarkDone,
                  icon: const Icon(Icons.check),
                  label: const Text('Erledigt'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerContactRow extends StatelessWidget {
  final dynamic customer;
  const _CustomerContactRow({required this.customer});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.business_outlined, size: 18, color: cs.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kunde',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: cs.outline)),
                  Text(customer.name,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
        if (customer.phone != null ||
            customer.email != null ||
            customer.address != null) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (customer.phone != null)
                ActionChip(
                  avatar: const Icon(Icons.phone_outlined, size: 14),
                  label: Text(customer.phone!,
                      style: Theme.of(context).textTheme.labelSmall),
                  onPressed: () => _launch('tel:${customer.phone}'),
                  visualDensity: VisualDensity.compact,
                ),
              if (customer.email != null)
                ActionChip(
                  avatar: const Icon(Icons.email_outlined, size: 14),
                  label: Text(customer.email!,
                      style: Theme.of(context).textTheme.labelSmall),
                  onPressed: () =>
                      _launch('mailto:${customer.email}'),
                  visualDensity: VisualDensity.compact,
                ),
              if (customer.address != null)
                ActionChip(
                  avatar: const Icon(Icons.directions_outlined, size: 14),
                  label: const Text('Navigation'),
                  onPressed: () => _launch(
                      'https://maps.google.com/?q=${Uri.encodeComponent(customer.address!)}'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ReportHistory extends StatelessWidget {
  final List<File> reports;
  final VoidCallback onRefresh;

  const _ReportHistory({required this.reports, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frühere Berichte',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 4),
        ...reports.map((f) {
          final name = f.path.split('/').last;
          // Extract timestamp from filename: bericht_XXXXXXXX_<ts>.pdf
          final parts = name.replaceAll('.pdf', '').split('_');
          String dateStr = '';
          if (parts.length >= 3) {
            final ts = int.tryParse(parts.last);
            if (ts != null) {
              final dt = DateTime.fromMillisecondsSinceEpoch(ts);
              dateStr = DateFormat('dd.MM.yyyy HH:mm').format(dt.toLocal());
            }
          }
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            title: Text(dateStr.isNotEmpty ? dateStr : name,
                style: Theme.of(context).textTheme.bodySmall),
            trailing: IconButton(
              icon: const Icon(Icons.share_outlined, size: 18),
              onPressed: () => PdfService.shareReport(f),
              visualDensity: VisualDensity.compact,
            ),
          );
        }),
      ],
    );
  }
}

// ─── Sessions Section ────────────────────────────────────────────────────────

class _SessionsSection extends ConsumerWidget {
  final String taskId;
  final VoidCallback onChanged;
  const _SessionsSection({required this.taskId, required this.onChanged});

  String _typeLabel(String type) => switch (type) {
        'SHORT_BREAK' => 'Kurze Pause',
        'LONG_BREAK' => 'Lange Pause',
        _ => 'Arbeit',
      };

  Future<void> _recalcTotal(AppDatabase db) async {
    final sessions = await (db.select(db.sessions)
          ..where((s) => s.taskId.equals(taskId)))
        .get();
    final total = sessions.fold<int>(0, (s, r) => s + r.duration);
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        totalMinutes: drift.Value(total),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
  }

  Future<void> _addOrEdit(
      BuildContext context, WidgetRef ref, Session? existing) async {
    final result = await showModalBottomSheet<_SessionResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SessionForm(taskId: taskId, session: existing),
    );
    if (result == null) return;
    final db = ref.read(databaseProvider);
    if (existing == null) {
      await db.into(db.sessions).insert(SessionsCompanion.insert(
            taskId: taskId,
            startTime: result.start,
            endTime: drift.Value(result.end),
            duration: drift.Value(result.duration),
            type: drift.Value(result.type),
            note: drift.Value(result.note),
          ));
    } else {
      await (db.update(db.sessions)..where((s) => s.id.equals(existing.id)))
          .write(SessionsCompanion(
        startTime: drift.Value(result.start),
        endTime: drift.Value(result.end),
        duration: drift.Value(result.duration),
        type: drift.Value(result.type),
        note: drift.Value(result.note),
      ));
    }
    await _recalcTotal(db);
    onChanged();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Session s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Session löschen?'),
        content: const Text('Die Zeiterfassung dieser Session wird entfernt.'),
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
    await (db.delete(db.sessions)..where((r) => r.id.equals(s.id))).go();
    await _recalcTotal(db);
    onChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider(taskId));
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text('Sessions',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addOrEdit(context, ref, null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Hinzufügen'),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 4),
        sessionsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Fehler: $e',
              style: TextStyle(color: cs.error)),
          data: (sessions) {
            if (sessions.isEmpty) {
              return Text('Noch keine Sessions',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline));
            }
            return Column(
              children: sessions.map((s) {
                final start =
                    DateFormat('dd.MM. HH:mm').format(s.startTime.toLocal());
                final end = s.endTime != null
                    ? DateFormat('HH:mm').format(s.endTime!.toLocal())
                    : '—';
                return Card(
                  margin: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: Icon(
                      s.type == 'WORK'
                          ? Icons.timer_outlined
                          : Icons.coffee_outlined,
                      size: 18,
                      color: s.type == 'WORK' ? cs.primary : cs.tertiary,
                    ),
                    title: Text('$start – $end',
                        style: Theme.of(context).textTheme.bodySmall),
                    subtitle: Text(
                        '${s.duration} Min · ${_typeLabel(s.type)}'
                        '${s.note != null && s.note!.isNotEmpty ? ' · ${s.note}' : ''}',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: cs.outline)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _addOrEdit(context, ref, s),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 16, color: cs.error),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _delete(context, ref, s),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _SessionResult {
  final DateTime start;
  final DateTime end;
  final int duration; // minutes
  final String type;
  final String? note;
  _SessionResult(
      {required this.start,
      required this.end,
      required this.duration,
      required this.type,
      this.note});
}

class _SessionForm extends StatefulWidget {
  final String taskId;
  final Session? session;
  const _SessionForm({required this.taskId, this.session});

  @override
  State<_SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends State<_SessionForm> {
  late DateTime _start;
  late DateTime _end;
  String _type = 'WORK';
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = widget.session?.startTime.toLocal() ??
        now.subtract(const Duration(minutes: 25));
    _end = widget.session?.endTime?.toLocal() ?? now;
    _type = widget.session?.type ?? 'WORK';
    _noteCtrl = TextEditingController(text: widget.session?.note ?? '');
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _durationMinutes {
    final diff = _end.difference(_start);
    return diff.inMinutes < 0 ? 0 : diff.inMinutes;
  }

  Future<void> _pickDateTime(bool isStart) async {
    final initial = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = dt;
        // Ensure end is not before start
        if (_end.isBefore(_start)) _end = _start.add(const Duration(minutes: 1));
      } else {
        _end = dt;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.session == null ? 'Session hinzufügen' : 'Session bearbeiten',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_arrow_outlined),
            title: const Text('Startzeit'),
            subtitle: Text(fmt.format(_start)),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: () => _pickDateTime(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.stop_outlined),
            title: const Text('Endzeit'),
            subtitle: Text(fmt.format(_end)),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: () => _pickDateTime(false),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('Dauer: $_durationMinutes Minuten',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Typ'),
            items: const [
              DropdownMenuItem(value: 'WORK', child: Text('Arbeit')),
              DropdownMenuItem(
                  value: 'SHORT_BREAK', child: Text('Kurze Pause')),
              DropdownMenuItem(
                  value: 'LONG_BREAK', child: Text('Lange Pause')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'WORK'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Notiz (optional)',
              hintText: 'z.B. was wurde gemacht',
            ),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _durationMinutes > 0
                ? () => Navigator.pop(
                      context,
                      _SessionResult(
                        start: _start.toUtc(),
                        end: _end.toUtc(),
                        duration: _durationMinutes,
                        type: _type,
                        note: _noteCtrl.text.trim().isEmpty
                            ? null
                            : _noteCtrl.text.trim(),
                      ),
                    )
                : null,
            child: const Text('Speichern'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
