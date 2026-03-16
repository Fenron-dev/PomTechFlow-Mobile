import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../providers/tasks_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/timer_provider.dart';
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

      final file = await PdfService.generateReport(PdfReportData(
        taskDetail: widget.detail,
        todos: todos,
        hardware: hardware,
        notes: notes,
        companyName: settings?.companyName ?? 'IT-Firma',
        technicianName: settings?.technicianName ?? '',
        aeMinutes: (settings?.aeMinutes ?? 10).toDouble(),
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
    final timer = ref.watch(timerProvider);
    final timerNotifier = ref.read(timerProvider.notifier);
    final isThisTask = timer.activeTaskId == task.id;
    final isRunning = isThisTask && timer.status == TimerStatus.running;
    final isPaused = isThisTask && timer.status == TimerStatus.paused;

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
            timer: timer,
            isThisTask: isThisTask,
            isRunning: isRunning,
            isPaused: isPaused,
            onStart: () async {
              final go = await showTimerStartDialog(context, ref, task.id);
              if (go && context.mounted) await timerNotifier.start(task.id);
            },
            onPause: () => timerNotifier.pause(),
            onResume: () => timerNotifier.resume(),
            onStop: () async {
              final elapsed = timer.totalSeconds - timer.secondsLeft;
              final mins = (elapsed / 60).ceil();
              final result = await showTimerStopDialog(
                  context, ref, task.id, mins);
              if (result != null) {
                final db = ref.read(databaseProvider);
                await applyTimerStopResult(db, task.id, result);
                await timerNotifier.stop();
                ref.invalidate(todosProvider(task.id));
                ref.invalidate(notesProvider(task.id));
                ref.invalidate(tasksProvider);
              }
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(unit,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

// ─── Timer Widget ────────────────────────────────────────────────────────────

class _TaskTimerWidget extends StatelessWidget {
  final String taskId;
  final TimerState timer;
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
    required this.timer,
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
            if (isThisTask) ...[
              Text(
                timer.timeString,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isRunning ? cs.primary : cs.tertiary,
                    ),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: timer.progress,
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
  final customer;
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
