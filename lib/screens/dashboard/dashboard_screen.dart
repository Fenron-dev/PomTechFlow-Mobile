import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/tasks_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/timer_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/general_notes_provider.dart';
import '../../db/database.dart';
import '../../widgets/timer_session_dialogs.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final timer = ref.watch(timerProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(settings?.companyName ?? 'PomTechFlow'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Alle Berichte',
            onPressed: () => context.push('/reports'),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Statistiken',
            onPressed: () => context.push('/statistics'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Neuer Task',
            onPressed: () async {
              await context.push('/tasks/new');
              ref.invalidate(tasksProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'quickstart',
        onPressed: () => _quickStart(context, ref),
        icon: const Icon(Icons.bolt),
        label: const Text('Schnellstart'),
        tooltip: 'Timer sofort starten',
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tasks) {
          final active = tasks.where((t) => t.task.status == 'ACTIVE').toList();
          final completed = tasks.where((t) => t.task.status == 'COMPLETED').length;
          final planned = tasks.where((t) => t.task.status == 'PLANNED').length;
          final today = DateTime.now();
          final todayTasks = tasks.where((t) {
            final d = t.task.plannedDate;
            if (d == null) return false;
            return d.year == today.year &&
                d.month == today.month &&
                d.day == today.day;
          }).toList()
            ..sort((a, b) => a.task.plannedDate!.compareTo(b.task.plannedDate!));
          final totalMinutes = tasks.fold<int>(0, (s, t) => s + t.task.totalMinutes);
          final aeMin = settings?.aeMinutes ?? 10;
          // Summe der aufgerundeten AE pro Task
          final totalAE = tasks.fold<int>(0, (s, t) => s + t.aeCount(aeMin));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tasksProvider),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Schnellnotiz
                const _QuickNoteCard(),
                const SizedBox(height: 12),
                // Stats
                LayoutBuilder(builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 500 ? 4 : 2;
                  final ratio = cols == 4 ? 2.2 : 1.4;
                  return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: ratio,
                  children: [
                    _StatCard(
                      label: 'Gesamt AE',
                      value: totalAE.toString(),
                      sub: '$totalMinutes Min',
                      icon: Icons.timer_outlined,
                      color: cs.primaryContainer,
                    ),
                    _StatCard(
                      label: 'Aktive Tasks',
                      value: active.length.toString(),
                      sub: '$planned geplant',
                      icon: Icons.play_circle_outline,
                      color: cs.secondaryContainer,
                    ),
                    _StatCard(
                      label: 'Abgeschlossen',
                      value: completed.toString(),
                      sub: '${tasks.length} gesamt',
                      icon: Icons.check_circle_outline,
                      color: cs.tertiaryContainer,
                    ),
                    _StatCard(
                      label: '1 AE =',
                      value: '$aeMin Min',
                      sub: 'konfigurierbar',
                      icon: Icons.settings_outlined,
                      color: cs.surfaceContainerHighest,
                      onTap: () => context.go('/settings'),
                    ),
                  ],
                );
                }),
                const SizedBox(height: 24),

                // ── Heute geplant ───────────────────────────────────────
                if (todayTasks.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Heute geplant',
                    icon: Icons.today,
                    count: todayTasks.length,
                  ),
                  const SizedBox(height: 8),
                  ...todayTasks.map((t) => _PlannedTaskRow(
                        task: t,
                        aeMin: aeMin,
                        onTap: () => context.push('/tasks/${t.task.id}'),
                      )),
                  const SizedBox(height: 16),
                ],

                // Aktive Tasks
                if (active.isNotEmpty) ...[
                  Row(
                    children: [
                      _SectionHeader(
                          title: 'Aktiv', icon: Icons.play_circle_outline, count: active.length),
                      const Spacer(),
                      TextButton(
                          onPressed: () => context.go('/tasks'),
                          child: const Text('Alle')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...active.take(3).map((t) {
                    final isRunning = timer[t.task.id]?.status == TimerStatus.running;
                    final isPaused = timer[t.task.id]?.status == TimerStatus.paused;
                    return _TaskRow(
                      task: t,
                      isTimerRunning: isRunning,
                      isTimerPaused: isPaused,
                      aeMin: aeMin,
                      onTap: () => context.push('/tasks/${t.task.id}'),
                      onTimerStart: !timer.containsKey(t.task.id)
                          ? () async {
                              await ref.read(timerProvider.notifier).start(t.task.id);
                              ref.invalidate(tasksProvider);
                            }
                          : null,
                      onTimerPause: isRunning
                          ? () => ref.read(timerProvider.notifier).pause(t.task.id)
                          : null,
                      onTimerResume: isPaused
                          ? () => ref.read(timerProvider.notifier).resume(t.task.id)
                          : null,
                      onTimerStop: (isRunning || isPaused)
                          ? () => handleTimerStop(context, ref, t.task.id)
                          : null,
                    );
                  }),
                ],

                // Geplante Tasks
                if (planned > 0) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _SectionHeader(
                          title: 'Geplant', icon: Icons.checklist_outlined, count: planned),
                      const Spacer(),
                      TextButton(
                          onPressed: () => context.go('/tasks'),
                          child: const Text('Alle')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...tasks
                      .where((t) => t.task.status == 'PLANNED')
                      .take(3)
                      .map((t) => _TaskRow(
                            task: t,
                            isTimerRunning: timer[t.task.id]?.status == TimerStatus.running,
                            isTimerPaused: timer[t.task.id]?.status == TimerStatus.paused,
                            aeMin: aeMin,
                            onTap: () => context.push('/tasks/${t.task.id}'),
                            onTimerStart: !timer.containsKey(t.task.id)
                                ? () async {
                                    await ref.read(timerProvider.notifier).start(t.task.id);
                                    ref.invalidate(tasksProvider);
                                  }
                                : null,
                            onTimerPause: timer[t.task.id]?.status == TimerStatus.running
                                ? () => ref.read(timerProvider.notifier).pause(t.task.id)
                                : null,
                            onTimerResume: timer[t.task.id]?.status == TimerStatus.paused
                                ? () => ref.read(timerProvider.notifier).resume(t.task.id)
                                : null,
                            onTimerStop: (timer[t.task.id] != null)
                                ? () => handleTimerStop(context, ref, t.task.id)
                                : null,
                          )),
                ],

                if (tasks.isEmpty) ...[
                  const SizedBox(height: 32),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.rocket_launch_outlined,
                            size: 64, color: cs.outlineVariant),
                        const SizedBox(height: 16),
                        Text('Willkommen bei PomTechFlow!',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Erstelle deinen ersten Task',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: cs.outline)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () async {
                            await context.push('/tasks/new');
                            ref.invalidate(tasksProvider);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Neuer Task'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
          );
        },
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  const _SectionHeader(
      {required this.title, required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
        ),
      ],
    );
  }
}

class _PlannedTaskRow extends StatelessWidget {
  final TaskWithDetails task;
  final int aeMin;
  final VoidCallback onTap;
  const _PlannedTaskRow(
      {required this.task, required this.aeMin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = task.task.plannedDate!;
    final timeStr = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(timeStr,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(task.task.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: task.customer != null ? Text(task.customer!.name) : null,
        trailing: _StatusDot(status: task.task.status),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'ACTIVE' => Colors.blue,
      'COMPLETED' => Colors.green,
      _ => Theme.of(context).colorScheme.outline,
    };
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const Spacer(),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label,
                style: Theme.of(context).textTheme.labelSmall),
            Text(sub,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final TaskWithDetails task;
  final bool isTimerRunning;
  final bool isTimerPaused;
  final int aeMin;
  final VoidCallback onTap;
  final VoidCallback? onTimerStart;
  final VoidCallback? onTimerPause;
  final VoidCallback? onTimerResume;
  final VoidCallback? onTimerStop;

  const _TaskRow({
    required this.task,
    required this.isTimerRunning,
    this.isTimerPaused = false,
    required this.aeMin,
    required this.onTap,
    this.onTimerStart,
    this.onTimerPause,
    this.onTimerResume,
    this.onTimerStop,
  });

  @override
  Widget build(BuildContext context) {
    final ae = task.aeCount(aeMin);
    final cs = Theme.of(context).colorScheme;
    final isActive = isTimerRunning || isTimerPaused;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: isTimerRunning
            ? Icon(Icons.timer, color: cs.primary)
            : Icon(Icons.radio_button_unchecked, color: cs.outline),
        title: Text(task.task.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: task.customer != null ? Text(task.customer!.name) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$ae AE', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(width: 8),
            // Play/Pause
            GestureDetector(
              onTap: isTimerRunning
                  ? onTimerPause
                  : isTimerPaused
                      ? onTimerResume
                      : onTimerStart,
              child: Icon(
                isTimerRunning
                    ? Icons.pause_circle
                    : isTimerPaused
                        ? Icons.play_circle
                        : Icons.play_circle_outline,
                color: isActive ? cs.primary : cs.outline,
                size: 28,
              ),
            ),
            // Stop (only when active)
            if (isActive) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onTimerStop,
                child: Icon(Icons.stop_circle_outlined,
                    color: cs.error, size: 26),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


// ─── Quick-Note Card ──────────────────────────────────────────────────────────

class _QuickNoteCard extends ConsumerStatefulWidget {
  const _QuickNoteCard();

  @override
  ConsumerState<_QuickNoteCard> createState() => _QuickNoteCardState();
}

class _QuickNoteCardState extends ConsumerState<_QuickNoteCard> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    await db.into(db.generalNotes).insert(
          GeneralNotesCompanion.insert(content: text),
        );
    ref.invalidate(generalNotesProvider);
    ref.invalidate(allTagsProvider);
    _ctrl.clear();
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Notiz gespeichert'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Notizen öffnen',
            onPressed: () => context.go('/notes'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: const Icon(Icons.edit_note_outlined),
        title: const Text('Schnellnotiz'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextField(
                  controller: _ctrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Notiz, Gedanke, Info...',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Speichern'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick-Start ──────────────────────────────────────────────────────────────

Future<void> _quickStart(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final now = DateTime.now();
  final defaultTitle =
      'Schnellstart ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Schnellstart'),
      content: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: 'Titel (optional)',
          hintText: defaultTitle,
        ),
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Starten ▶')),
      ],
    ),
  );
  final title =
      ctrl.text.trim().isEmpty ? defaultTitle : ctrl.text.trim();
  ctrl.dispose();
  if (confirmed != true || !context.mounted) return;

  final db = ref.read(databaseProvider);
  final taskId = _genUuid();
  await db.into(db.tasks).insert(
        TasksCompanion.insert(
          id: drift.Value(taskId),
          title: title,
        ),
      );
  await ref.read(timerProvider.notifier).start(taskId);
  ref.invalidate(tasksProvider);
  if (context.mounted) context.push('/tasks/$taskId');
}

String _genUuid() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
}
