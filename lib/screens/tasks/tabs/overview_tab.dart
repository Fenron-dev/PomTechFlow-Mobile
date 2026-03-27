import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../providers/task_links_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final reports = await PdfService.listReports(
      widget.detail.task.id,
      taskTitle: widget.detail.task.title,
    );
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
      if (!mounted) return;

      final hardware = await (db.select(db.hardware)
            ..where((h) => h.taskId.equals(taskId)))
          .get();
      if (!mounted) return;

      final notes = await (db.select(db.notes)
            ..where((n) => n.taskId.equals(taskId)))
          .get();
      if (!mounted) return;

      Uint8List? logoBytes;
      if (settings?.logoPath != null) {
        final logoFile = File(settings!.logoPath!);
        if (await logoFile.exists()) {
          if (!mounted) return;
          logoBytes = await logoFile.readAsBytes();
          if (!mounted) return;
        }
      }

      final file = await PdfService.generateReport(
        PdfReportData(
          taskDetail: widget.detail,
          todos: todos,
          hardware: hardware,
          notes: notes,
          companyName: settings?.companyName ?? 'IT-Firma',
          technicianName: settings?.technicianName ?? '',
          aeMinutes: (settings?.aeMinutes ?? 10).toDouble(),
          logoBytes: logoBytes,
        ),
        storageBasePath: settings?.storageBasePath ?? '',
      );
      if (!mounted) return;

      await PdfService.shareReport(file);
      if (mounted) _loadReports();
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
    await EmailService.sendBillingDraft(
      billingEmail: settings?.billingEmail ?? '',
      taskTitle: detail.task.title,
      customerName: detail.customer?.name,
      totalMinutes: detail.task.totalMinutes,
      aeCount: detail.aeCount(aeMin),
      technicianName: settings?.technicianName ?? '',
      companyName: settings?.companyName ?? '',
      billedAt: detail.task.billedAt,
      estimatedMinutes: detail.task.estimatedMinutes,
    );
  }

  Future<void> _copyAe() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    final task = widget.detail.task;
    final ae = widget.detail.aeCount(settings?.aeMinutes ?? 10);
    final budgetPart = task.estimatedMinutes != null
        ? ' | Budget: ${task.estimatedMinutes} Min'
        : '';
    final text =
        'Task: ${task.title} | Zeit: ${task.totalMinutes} Min$budgetPart | AE: $ae';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('In Zwischenablage kopiert'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleBilled() async {
    final db = ref.read(databaseProvider);
    final task = widget.detail.task;
    final newBilledAt = task.billedAt == null ? DateTime.now() : null;
    await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(billedAt: drift.Value(newBilledAt)),
    );
    ref.invalidate(taskDetailProvider(task.id));
    ref.invalidate(tasksProvider);
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
            onStart: () => timerNotifier.start(task.id),
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
                unit: task.estimatedMinutes != null
                    ? 'Min / ${task.estimatedMinutes} Min'
                    : 'Min',
                icon: task.estimatedMinutes != null &&
                        task.totalMinutes > task.estimatedMinutes!
                    ? Icons.warning_amber_rounded
                    : Icons.schedule,
                color: task.estimatedMinutes != null &&
                        task.totalMinutes > task.estimatedMinutes!
                    ? Colors.orange.shade100
                    : cs.secondaryContainer,
              ),
            ),
          ],
        ),
        // Budget-Fortschrittsbalken
        if (task.estimatedMinutes != null) ...[
          const SizedBox(height: 8),
          _BudgetProgressBar(
            totalMinutes: task.totalMinutes,
            estimatedMinutes: task.estimatedMinutes!,
          ),
        ],
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
        const SizedBox(height: 8),
        // Aktionen: AE kopieren + Abgerechnet-Toggle
        Row(
          children: [
            TextButton.icon(
              onPressed: _copyAe,
              icon: const Icon(Icons.content_copy, size: 16),
              label: const Text('AE kopieren'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _toggleBilled,
              icon: Icon(
                task.billedAt != null
                    ? Icons.receipt_long
                    : Icons.receipt_long_outlined,
                size: 16,
                color: task.billedAt != null ? cs.primary : null,
              ),
              label: Text(
                task.billedAt != null ? 'Abgerechnet ✓' : 'Als abgerechnet',
                style: TextStyle(
                  color: task.billedAt != null ? cs.primary : null,
                ),
              ),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Verknüpfte Tasks
        _TaskLinksSection(taskId: task.id),
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

class _BudgetProgressBar extends StatelessWidget {
  final int totalMinutes;
  final int estimatedMinutes;
  const _BudgetProgressBar({
    required this.totalMinutes,
    required this.estimatedMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (totalMinutes / estimatedMinutes).clamp(0.0, 1.0);
    final overBudget = totalMinutes > estimatedMinutes;
    final color = overBudget ? Colors.red : Colors.orange;
    final barColor = overBudget
        ? Colors.red
        : (progress > 0.8 ? Colors.orange : Theme.of(context).colorScheme.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            color: barColor,
          ),
        ),
        if (overBudget)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  'Zeitbudget überschritten (+${totalMinutes - estimatedMinutes} Min)',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: color),
                ),
              ],
            ),
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

  /// Decodes "street||zip||city" and opens the native maps app.
  Future<void> _openMaps(String rawAddress) async {
    final parts = rawAddress.split('||');
    final address = parts.length == 3
        ? '${parts[0]} ${parts[1]} ${parts[2]}'.trim()
        : rawAddress;
    final encoded = Uri.encodeComponent(address);
    final nativeUri = Platform.isIOS
        ? Uri.parse('maps://?q=$encoded')
        : Uri.parse('geo:0,0?q=$encoded');
    if (await canLaunchUrl(nativeUri)) {
      await launchUrl(nativeUri);
    } else {
      await launchUrl(Uri.parse('https://maps.google.com/?q=$encoded'));
    }
  }

  /// Returns "Straße, PLZ Ort" from "street||zip||city" encoding.
  static String _formatAddress(String rawAddress) {
    final parts = rawAddress.split('||');
    if (parts.length == 3) {
      final street = parts[0].trim();
      final zipCity = '${parts[1]} ${parts[2]}'.trim();
      if (street.isNotEmpty && zipCity.trim().isNotEmpty) {
        return '$street, $zipCity';
      }
      return (street.isNotEmpty ? street : zipCity).trim();
    }
    return rawAddress;
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
        // Address row with "In Maps öffnen" button
        if (customer.address != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.location_on_outlined, size: 16, color: cs.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _formatAddress(customer.address!),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.tonalIcon(
                onPressed: () => _openMaps(customer.address!),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('In Maps öffnen'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ],
        if (customer.phone != null || customer.email != null) ...[
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
                  onPressed: () => _launch('mailto:${customer.email}'),
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
            initialValue: _type,
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

// ─── Task-Verknüpfungen ───────────────────────────────────────────────────────

class _TaskLinksSection extends ConsumerWidget {
  final String taskId;
  const _TaskLinksSection({required this.taskId});

  static const _linkLabels = {
    'RELATED': 'Verwandt',
    'BLOCKS': 'Blockiert',
    'FOLLOW_UP': 'Folge-Task',
  };
  static const _linkIcons = {
    'RELATED': Icons.link,
    'BLOCKS': Icons.block,
    'FOLLOW_UP': Icons.arrow_forward,
  };

  Future<void> _addLink(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<_LinkResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddLinkSheet(currentTaskId: taskId),
    );
    if (result == null) return;
    final db = ref.read(databaseProvider);
    await db.into(db.taskLinks).insert(TaskLinksCompanion.insert(
          taskId: taskId,
          linkedTaskId: result.linkedTaskId,
          linkType: drift.Value(result.linkType),
        ));
    ref.invalidate(taskLinksProvider(taskId));
  }

  Future<void> _removeLink(WidgetRef ref, String linkId) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.taskLinks)..where((l) => l.id.equals(linkId))).go();
    ref.invalidate(taskLinksProvider(taskId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linksAsync = ref.watch(taskLinksProvider(taskId));
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.link, size: 16, color: cs.outline),
            const SizedBox(width: 6),
            Text('Verknüpfte Tasks',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: cs.outline)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addLink(context, ref),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Verknüpfen'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        linksAsync.when(
          loading: () => const SizedBox(
              height: 24,
              child: Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)))),
          error: (_, _) => const SizedBox(),
          data: (links) {
            if (links.isEmpty) return const SizedBox();
            final directLinks =
                links.where((e) => !e.isBacklink).toList();
            final backlinks =
                links.where((e) => e.isBacklink).toList();

            Widget linkTile(TaskLinkEntry e) => ListTile(
                  dense: true,
                  leading: Icon(
                    e.isBacklink
                        ? Icons.reply
                        : (_linkIcons[e.link.linkType] ?? Icons.link),
                    size: 18,
                    color: e.isBacklink ? cs.secondary : cs.primary,
                  ),
                  title: Text(e.linkedTask.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(e.isBacklink
                      ? '↩ ${_linkLabels[e.link.linkType] ?? e.link.linkType}'
                      : (_linkLabels[e.link.linkType] ?? e.link.linkType)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => _removeLink(ref, e.link.id),
                    visualDensity: VisualDensity.compact,
                  ),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => context.push('/tasks/${e.linkedTask.id}'),
                );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...directLinks.map(linkTile),
                if (backlinks.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Rückverweise',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: cs.outline),
                  ),
                  ...backlinks.map(linkTile),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LinkResult {
  final String linkedTaskId;
  final String linkType;
  const _LinkResult({required this.linkedTaskId, required this.linkType});
}

class _AddLinkSheet extends ConsumerStatefulWidget {
  final String currentTaskId;
  const _AddLinkSheet({required this.currentTaskId});

  @override
  ConsumerState<_AddLinkSheet> createState() => _AddLinkSheetState();
}

class _AddLinkSheetState extends ConsumerState<_AddLinkSheet> {
  final _searchCtrl = TextEditingController();
  String _linkType = 'RELATED';
  String _filter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Task verknüpfen',
                        style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'RELATED',
                        icon: Icon(Icons.link, size: 16),
                        label: Text('Verwandt')),
                    ButtonSegment(
                        value: 'BLOCKS',
                        icon: Icon(Icons.block, size: 16),
                        label: Text('Blockiert')),
                    ButtonSegment(
                        value: 'FOLLOW_UP',
                        icon: Icon(Icons.arrow_forward, size: 16),
                        label: Text('Folge-Task')),
                  ],
                  selected: {_linkType},
                  onSelectionChanged: (s) =>
                      setState(() => _linkType = s.first),
                  style: ButtonStyle(
                      visualDensity: VisualDensity.compact),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Task suchen...',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _filter = v.toLowerCase()),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tasksAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (tasks) {
                final filtered = tasks
                    .where((t) =>
                        t.task.id != widget.currentTaskId &&
                        (_filter.isEmpty ||
                            t.task.title
                                .toLowerCase()
                                .contains(_filter)))
                    .toList();
                return ListView.builder(
                  controller: scrollCtrl,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final t = filtered[i];
                    return ListTile(
                      title: Text(t.task.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle:
                          t.customer != null ? Text(t.customer!.name) : null,
                      onTap: () => Navigator.pop(
                        context,
                        _LinkResult(
                            linkedTaskId: t.task.id, linkType: _linkType),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
