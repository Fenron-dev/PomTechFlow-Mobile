import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/tasks_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/timer_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/general_notes_provider.dart';
import '../../providers/task_templates_provider.dart';
import '../../providers/quick_stopwatch_provider.dart';
import '../../db/database.dart';
import '../../sync/sync_provider.dart';
import '../../widgets/timer_session_dialogs.dart';
import '../../widgets/quick_assign_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final timer = ref.watch(timerProvider);
    final ownOnly = ref.watch(ownTasksOnlyProvider);
    final techName = settings?.technicianName ?? '';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(settings?.companyName ?? 'PomTechFlow'),
        actions: [
          IconButton(
            icon: Icon(ownOnly ? Icons.person : Icons.people_outline),
            tooltip: ownOnly ? 'Meine Tasks (Alle anzeigen)' : 'Alle Tasks (Filtern)',
            onPressed: () => ref.read(ownTasksOnlyProvider.notifier).state = !ownOnly,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Neuer Task',
            onPressed: () => _showNewTaskOptions(context, ref),
          ),
          PopupMenuButton<_DashMenuAction>(
            icon: const Icon(Icons.menu),
            tooltip: 'Menü',
            onSelected: (action) {
              switch (action) {
                case _DashMenuAction.customers:
                  context.push('/settings/customers');
                case _DashMenuAction.settings:
                  context.push('/settings');
                case _DashMenuAction.statistics:
                  context.push('/statistics');
                case _DashMenuAction.reports:
                  context.push('/reports');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _DashMenuAction.customers,
                child: ListTile(
                  leading: Icon(Icons.business_outlined),
                  title: Text('Kunden'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _DashMenuAction.settings,
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Einstellungen'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _DashMenuAction.statistics,
                child: ListTile(
                  leading: Icon(Icons.bar_chart_outlined),
                  title: Text('Statistiken'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _DashMenuAction.reports,
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Alle Berichte'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tasks) {
          int pRank(String p) => switch (p) {
            'CRITICAL' => 3,
            'HIGH' => 2,
            'NORMAL' => 1,
            _ => 0,
          };
          int sortByPriorityThenDate(TaskWithDetails a, TaskWithDetails b) {
            final p = pRank(b.task.priority).compareTo(pRank(a.task.priority));
            if (p != 0) return p;
            final aDate = a.task.plannedDate ?? a.task.createdAt;
            final bDate = b.task.plannedDate ?? b.task.createdAt;
            return aDate.compareTo(bDate); // oldest first
          }
          final tech = techName.isEmpty ? null : techName;
          final visibleTasks = filterByTechnician(tasks, tech, ownOnly: ownOnly);
          final otherTasks = ownOnly ? otherTechnicianTasks(tasks, tech) : <TaskWithDetails>[];

          final today = DateTime.now();
          final active = visibleTasks.where((t) => t.task.status == 'ACTIVE').toList();
          final completed = visibleTasks.where((t) => t.task.status == 'COMPLETED').length;

          // „Im Blick": laufende/pausierte Timer + gepinnte + heute geplante Tasks.
          bool hasTimer(String id) => timer[id] != null;
          int focusRank(TaskWithDetails t) {
            final st = timer[t.task.id]?.status;
            if (st == TimerStatus.running) return 0;
            if (st == TimerStatus.paused) return 1;
            return 2;
          }
          final focusTasks = visibleTasks
              .where((t) => isFocusTask(t.task,
                  hasActiveTimer: hasTimer(t.task.id), now: today))
              .toList()
            ..sort((a, b) {
              final r = focusRank(a).compareTo(focusRank(b));
              if (r != 0) return r;
              return sortByPriorityThenDate(a, b);
            });
          final focusIds = focusTasks.map((t) => t.task.id).toSet();

          // Geplant: zukünftige/undatierte PLANNED-Tasks, die nicht schon „Im Blick" sind.
          final plannedTasks = visibleTasks
              .where((t) =>
                  t.task.status == 'PLANNED' && !focusIds.contains(t.task.id))
              .toList()
            ..sort(sortByPriorityThenDate);
          final planned = plannedTasks.length;
          final todayStart = DateTime(today.year, today.month, today.day);
          final todayDone = visibleTasks
              .where((t) =>
                  t.task.status == 'COMPLETED' &&
                  t.task.updatedAt.isAfter(
                      todayStart.subtract(const Duration(seconds: 1))))
              .toList()
            ..sort((a, b) => b.task.updatedAt.compareTo(a.task.updatedAt));
          final totalMinutes = visibleTasks.fold<int>(0, (s, t) => s + t.task.totalMinutes);
          final aeMin = settings?.aeMinutes ?? 10;
          // Summe der aufgerundeten AE pro Task
          final totalAE = visibleTasks.fold<int>(0, (s, t) => s + t.aeCount(aeMin));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tasksProvider),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Globale Suche (prominent)
                GestureDetector(
                  onTap: () => context.push('/search'),
                  child: AbsorbPointer(
                    child: SearchBar(
                      hintText: 'Tasks & Kunden suchen…',
                      leading: const Icon(Icons.search_outlined),
                      padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 16)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Schnellstoppuhr
                const _QuickStopwatchCard(),
                const SizedBox(height: 12),
                // Schnellnotiz
                const _QuickNoteCard(),
                const SizedBox(height: 12),
                // Stats
                LayoutBuilder(builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 500 ? 4 : 2;
                  final ratio = cols == 4 ? 2.6 : 1.4;
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
                    ),
                  ],
                );
                }),
                const SizedBox(height: 24),

                // ── Im Blick (laufend / heute / gepinnt) ────────────────
                _CollapsibleSection(
                  header: Row(children: [
                    _SectionHeader(
                        title: 'Im Blick',
                        icon: Icons.visibility_outlined,
                        count: focusTasks.length),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _startTimerOptions(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Timer'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ]),
                  child: Column(children: [
                    const SizedBox(height: 8),
                    if (focusTasks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        child: Text(
                          'Nichts im Blick. Starte einen Timer oder plane einen Task für heute.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.outline),
                        ),
                      )
                    else
                      ...focusTasks.map((t) {
                        final entry = timer[t.task.id];
                        final isRunning = entry?.status == TimerStatus.running;
                        final isPaused = entry?.status == TimerStatus.paused;
                        return _FocusTaskRow(
                          task: t,
                          aeMin: aeMin,
                          elapsed: entry?.timeString,
                          isTimerRunning: isRunning,
                          isTimerPaused: isPaused,
                          today: today,
                          onTap: () => context.push('/tasks/${t.task.id}'),
                          onTimerStart: entry == null
                              ? () async {
                                  await ref
                                      .read(timerProvider.notifier)
                                      .start(t.task.id);
                                  ref.invalidate(tasksProvider);
                                }
                              : null,
                          onTimerPause: isRunning
                              ? () => ref
                                  .read(timerProvider.notifier)
                                  .pause(t.task.id)
                              : null,
                          onTimerResume: isPaused
                              ? () => ref
                                  .read(timerProvider.notifier)
                                  .resume(t.task.id)
                              : null,
                          onTimerStop: (isRunning || isPaused)
                              ? () => handleTimerStop(context, ref, t.task.id)
                              : null,
                          onHide: entry == null
                              ? () async {
                                  await hideFromDashboard(
                                      ref.read(databaseProvider), t.task.id);
                                  ref.invalidate(tasksProvider);
                                }
                              : null,
                          onComplete: entry == null
                              ? () async {
                                  await markTaskDone(
                                      ref.read(databaseProvider), t.task.id);
                                  ref.invalidate(tasksProvider);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '„${t.task.title}" erledigt'),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                }
                              : null,
                          onAssign: () =>
                              showQuickAssignSheet(context, ref, t.task.id),
                        );
                      }),
                  ]),
                ),
                const SizedBox(height: 16),

                // Geplante Tasks
                if (planned > 0) ...[
                  _CollapsibleSection(
                    header: Row(children: [
                      _SectionHeader(
                          title: 'Geplant',
                          icon: Icons.checklist_outlined,
                          count: planned),
                      const Spacer(),
                      TextButton(
                          onPressed: () => context.go('/tasks'),
                          child: const Text('Alle')),
                    ]),
                    child: Column(children: [
                      const SizedBox(height: 8),
                      ...plannedTasks
                          .take(3)
                          .map((t) => _TaskRow(
                                task: t,
                                isTimerRunning:
                                    timer[t.task.id]?.status ==
                                        TimerStatus.running,
                                isTimerPaused:
                                    timer[t.task.id]?.status ==
                                        TimerStatus.paused,
                                aeMin: aeMin,
                                onTap: () =>
                                    context.push('/tasks/${t.task.id}'),
                                onTimerStart: !timer.containsKey(t.task.id)
                                    ? () async {
                                        await ref
                                            .read(timerProvider.notifier)
                                            .start(t.task.id);
                                        ref.invalidate(tasksProvider);
                                      }
                                    : null,
                                onTimerPause:
                                    timer[t.task.id]?.status ==
                                            TimerStatus.running
                                        ? () => ref
                                            .read(timerProvider.notifier)
                                            .pause(t.task.id)
                                        : null,
                                onTimerResume:
                                    timer[t.task.id]?.status ==
                                            TimerStatus.paused
                                        ? () => ref
                                            .read(timerProvider.notifier)
                                            .resume(t.task.id)
                                        : null,
                                onTimerStop: (timer[t.task.id] != null)
                                    ? () => handleTimerStop(
                                        context, ref, t.task.id)
                                    : null,
                              )),
                    ]),
                  ),
                ],

                // ── Heute erledigt ─────────────────────────────────────
                if (todayDone.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _CollapsibleSection(
                    initiallyExpanded: false,
                    header: _SectionHeader(
                      title: 'Heute erledigt',
                      icon: Icons.check_circle_outline,
                      count: todayDone.length,
                    ),
                    child: Column(children: [
                      const SizedBox(height: 8),
                      ...todayDone.map((t) {
                        final ae = t.aeCount(aeMin);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.check_circle,
                                color: Colors.green.shade600, size: 20),
                            title: Text(t.task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    decoration: TextDecoration.lineThrough)),
                            subtitle: t.customer != null
                                ? Text(t.customer!.name)
                                : null,
                            trailing: Text('$ae AE',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(color: cs.outline)),
                            onTap: () =>
                                context.push('/tasks/${t.task.id}'),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ]),
                  ),
                ],

                // ── Andere Techniker ───────────────────────────────────
                if (otherTasks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _CollapsibleSection(
                    initiallyExpanded: false,
                    header: _SectionHeader(
                      title: 'Andere Techniker',
                      icon: Icons.people_outline,
                      count: otherTasks.length,
                    ),
                    child: Column(children: [
                      const SizedBox(height: 8),
                      ...otherTasks.map((t) => Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.person_outline,
                                  size: 18, color: cs.outline),
                              title: Text(t.task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text([
                                if (t.task.assignedTo != null &&
                                    t.task.assignedTo!.isNotEmpty)
                                  t.task.assignedTo!,
                                if (t.customer != null) t.customer!.name,
                              ].join(' · ')),
                              trailing: _StatusDot(status: t.task.status),
                              onTap: () =>
                                  context.push('/tasks/${t.task.id}'),
                            ),
                          )),
                      const SizedBox(height: 8),
                    ]),
                  ),
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

// ─── Collapsible Section ──────────────────────────────────────────────────────

class _CollapsibleSection extends StatefulWidget {
  final Widget header;
  final Widget child;
  final bool initiallyExpanded;
  const _CollapsibleSection({
    required this.header,
    required this.child,
    this.initiallyExpanded = true,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(child: widget.header),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) widget.child,
      ],
    );
  }
}

/// Zeile in der „Im Blick"-Sektion: großzügige Timer-Steuerung plus
/// Ausblenden-Aktion (nur wenn kein Timer aktiv ist).
class _FocusTaskRow extends StatelessWidget {
  final TaskWithDetails task;
  final int aeMin;
  final String? elapsed; // formatierte Laufzeit, falls Timer aktiv
  final bool isTimerRunning;
  final bool isTimerPaused;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback? onTimerStart;
  final VoidCallback? onTimerPause;
  final VoidCallback? onTimerResume;
  final VoidCallback? onTimerStop;
  final VoidCallback? onHide;
  final VoidCallback? onComplete;
  final VoidCallback? onAssign;

  const _FocusTaskRow({
    required this.task,
    required this.aeMin,
    required this.elapsed,
    required this.isTimerRunning,
    required this.isTimerPaused,
    required this.today,
    required this.onTap,
    this.onTimerStart,
    this.onTimerPause,
    this.onTimerResume,
    this.onTimerStop,
    this.onHide,
    this.onComplete,
    this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = isTimerRunning || isTimerPaused;
    final priorityColor = switch (task.task.priority) {
      'CRITICAL' => Colors.red,
      'HIGH' => Colors.orange,
      'LOW' => Colors.blueGrey.shade300,
      _ => Colors.transparent,
    };

    final pd = task.task.plannedDate;
    final plannedToday = pd != null &&
        pd.year == today.year &&
        pd.month == today.month &&
        pd.day == today.day;

    // Zeit (Laufzeit bzw. heutige Plan-Uhrzeit) und Kundenname getrennt halten,
    // damit ein langer Kundenname die Zeit nicht abschneidet.
    final timeText = elapsed ??
        (plannedToday
            ? 'Heute ${pd.hour.toString().padLeft(2, '0')}:${pd.minute.toString().padLeft(2, '0')}'
            : null);
    final customerName = task.customer?.name;

    final leadingIcon = isTimerRunning
        ? Icon(Icons.timer, color: cs.primary)
        : isTimerPaused
            ? Icon(Icons.pause_circle_outline, color: cs.primary)
            : Icon(Icons.radio_button_unchecked, color: cs.outline);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (task.task.priority != 'NORMAL')
              Container(width: 4, color: priorityColor),
            Expanded(
              child: ListTile(
                onTap: onTap,
                leading: leadingIcon,
                title: Text(task.task.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: (timeText == null && customerName == null)
                    ? null
                    : Row(
                        children: [
                          if (timeText != null)
                            Text(
                              timeText,
                              style: TextStyle(
                                color:
                                    isTimerRunning ? cs.primary : cs.outline,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (timeText != null && customerName != null)
                            Text('  ·  ',
                                style: TextStyle(color: cs.outline)),
                          if (customerName != null)
                            Expanded(
                              child: Text(
                                customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.outline),
                              ),
                            ),
                        ],
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onAssign != null) ...[
                      GestureDetector(
                        onTap: onAssign,
                        child: Tooltip(
                          message: 'Kunde / Titel zuordnen',
                          child: Icon(Icons.sell_outlined,
                              color: cs.outline, size: 22),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
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
                        size: 30,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onTimerStop,
                        child: Icon(Icons.stop_circle_outlined,
                            color: cs.error, size: 28),
                      ),
                    ] else ...[
                      if (onComplete != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: onComplete,
                          child: Tooltip(
                            message: 'Als erledigt markieren',
                            child: Icon(Icons.check_circle_outline,
                                color: Colors.green.shade600, size: 26),
                          ),
                        ),
                      ],
                      if (onHide != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: onHide,
                          child: Tooltip(
                            message: 'Aus „Im Blick" ausblenden',
                            child: Icon(Icons.visibility_off_outlined,
                                color: cs.outline, size: 24),
                          ),
                        ),
                      ],
                    ],
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

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
    final priorityColor = switch (task.task.priority) {
      'CRITICAL' => Colors.red,
      'HIGH' => Colors.orange,
      'LOW' => Colors.blueGrey.shade300,
      _ => Colors.transparent,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (task.task.priority != 'NORMAL')
              Container(width: 4, color: priorityColor),
            Expanded(
              child: ListTile(
                onTap: onTap,
                leading: isTimerRunning
                    ? Icon(Icons.timer, color: cs.primary)
                    : Icon(Icons.radio_button_unchecked, color: cs.outline),
                title: Text(task.task.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle:
                    task.customer != null ? Text(task.customer!.name) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$ae AE',
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(width: 8),
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
            ),
          ],
        ),
      ),
    );
  }
}


// ─── Quick-Stopwatch Card ─────────────────────────────────────────────────────

class _QuickStopwatchCard extends ConsumerStatefulWidget {
  const _QuickStopwatchCard();

  @override
  ConsumerState<_QuickStopwatchCard> createState() =>
      _QuickStopwatchCardState();
}

class _QuickStopwatchCardState extends ConsumerState<_QuickStopwatchCard> {
  // State lives in quickStopwatchProvider — this widget only reacts to it.

  String _fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _showSaveDialog(int seconds, DateTime startTime) async {
    final customers = await ref
        .read(customersProvider.future)
        .catchError((_) => <Customer>[]);
    if (!mounted) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SaveStopwatchSheet(
        durationSeconds: seconds,
        startTime: startTime,
        customers: customers,
      ),
    );

    ref.read(quickStopwatchProvider.notifier).clearPendingSave();

    if (saved == true && mounted) {
      ref.invalidate(tasksProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task gespeichert')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for pendingSave → show dialog
    ref.listen<StopwatchState>(quickStopwatchProvider, (prev, next) {
      if (next.pendingSave && !(prev?.pendingSave ?? false)) {
        _showSaveDialog(next.seconds, next.startTime ?? DateTime.now());
      }
    });

    final sw = ref.watch(quickStopwatchProvider);
    final notifier = ref.read(quickStopwatchProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.timer_outlined,
                color: sw.isRunning ? cs.primary : cs.outline, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Schnell-Stoppuhr',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: cs.outline)),
                  Text(
                    sw.isActive ? _fmt(sw.seconds) : '--:--',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: sw.isRunning ? cs.primary : cs.onSurface),
                  ),
                ],
              ),
            ),
            // Play / Pause button
            if (!sw.isIdle)
              IconButton(
                tooltip: sw.isRunning ? 'Pausieren' : 'Fortsetzen',
                icon: Icon(
                    sw.isRunning ? Icons.pause_circle : Icons.play_circle),
                color: cs.primary,
                iconSize: 30,
                onPressed: sw.isRunning ? notifier.pause : notifier.resume,
              ),
            // Start / Stop button
            if (sw.isIdle)
              FilledButton.tonalIcon(
                onPressed: notifier.start,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Start'),
              )
            else
              FilledButton.tonalIcon(
                onPressed: notifier.stopAndRequestSave,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Stopp'),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.errorContainer,
                  foregroundColor: cs.onErrorContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Save-Stopwatch Dialog ────────────────────────────────────────────────────

class _SaveStopwatchSheet extends ConsumerStatefulWidget {
  final int durationSeconds;
  final DateTime startTime;
  final List<Customer> customers;

  const _SaveStopwatchSheet({
    required this.durationSeconds,
    required this.startTime,
    required this.customers,
  });

  @override
  ConsumerState<_SaveStopwatchSheet> createState() =>
      _SaveStopwatchSheetState();
}

class _SaveStopwatchSheetState extends ConsumerState<_SaveStopwatchSheet> {
  late final TextEditingController _titleCtrl;
  String? _customerId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _titleCtrl = TextEditingController(
      text:
          'Schnellerfassung ${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}. ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  String get _durationStr {
    final h = widget.durationSeconds ~/ 3600;
    final m = (widget.durationSeconds % 3600) ~/ 60;
    final s = widget.durationSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    final db = ref.read(databaseProvider);
    final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}';
    final durationMins = max(1, (widget.durationSeconds / 60).ceil());

    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: drift.Value(taskId),
          title: title,
          status: const drift.Value('COMPLETED'),
          customerId: drift.Value(_customerId),
          totalMinutes: drift.Value(durationMins),
        ));

    final sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}_$taskId';
    await db.into(db.sessions).insert(SessionsCompanion.insert(
          id: drift.Value(sessionId),
          taskId: taskId,
          startTime: widget.startTime,
          endTime: drift.Value(DateTime.now()),
          duration: drift.Value(durationMins),
          type: const drift.Value('WORK'),
        ));

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              const Icon(Icons.save_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Zeit als Task speichern?',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _durationStr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Bezeichnung *',
              hintText: 'z.B. Telefonat Kunde X',
            ),
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          if (widget.customers.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _customerId,
              decoration: const InputDecoration(labelText: 'Kunde (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Kein Kunde')),
                ...widget.customers.map((c) =>
                    DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() => _customerId = v),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Verwerfen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Speichern'),
                ),
              ),
            ],
          ),
        ],
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

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _DashMenuAction { customers, settings, statistics, reports }

// ─── Neuer Task – Optionen ────────────────────────────────────────────────────

Future<void> _showNewTaskOptions(BuildContext context, WidgetRef ref) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Neuer Task',
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          ListTile(
            leading: Icon(Icons.add_task_outlined, color: cs.primary),
            title: const Text('Standard Task'),
            subtitle: const Text('Leeren Task anlegen'),
            onTap: () async {
              Navigator.pop(ctx);
              await context.push('/tasks/new');
              ref.invalidate(tasksProvider);
            },
          ),
          ListTile(
            leading: Icon(Icons.copy_outlined, color: cs.primary),
            title: const Text('Aus Vorlage'),
            subtitle: const Text('Task aus gespeicherter Vorlage'),
            onTap: () {
              Navigator.pop(ctx);
              _createFromTemplate(context, ref);
            },
          ),
          ListTile(
            leading: Icon(Icons.bolt, color: cs.primary),
            title: const Text('Schnellstart'),
            subtitle: const Text('Timer sofort starten, Details später'),
            onTap: () {
              Navigator.pop(ctx);
              _quickStart(context, ref);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ─── Aus Vorlage erstellen ────────────────────────────────────────────────────

Future<void> _createFromTemplate(BuildContext context, WidgetRef ref) async {
  final templates = ref.read(taskTemplatesProvider).valueOrNull ?? [];
  if (templates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Keine Vorlagen. Erst in Einstellungen anlegen.')),
    );
    return;
  }
  final selected = await showModalBottomSheet<TemplateWithDetails>(
    context: context,
    builder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Vorlage wählen',
              style: Theme.of(context).textTheme.titleLarge),
        ),
        const Divider(height: 1),
        ...templates.map((twd) => ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(twd.template.title),
              subtitle: [
                if (twd.customer != null) twd.customer!.name,
                if (twd.workflow != null) twd.workflow!.name,
              ].join(' · ').isEmpty
                  ? null
                  : Text([
                      if (twd.customer != null) twd.customer!.name,
                      if (twd.workflow != null) twd.workflow!.name,
                    ].join(' · ')),
              onTap: () => Navigator.pop(context, twd),
            )),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;

  final db = ref.read(databaseProvider);
  final now = DateTime.now();
  final newTaskId = 'task_${now.millisecondsSinceEpoch}';
  await db.into(db.tasks).insert(TasksCompanion.insert(
        id: drift.Value(newTaskId),
        title: selected.template.title,
        description: drift.Value(selected.template.description),
        customerId: drift.Value(selected.template.customerId),
        updatedAt: drift.Value(now),
      ));

  int sortIdx = 0;
  for (final wf in selected.workflows) {
    final items = await (db.select(db.workflowItems)
          ..where((i) => i.workflowId.equals(wf.id))
          ..orderBy([(i) => drift.OrderingTerm.asc(i.sortOrder)]))
        .get();
    for (final item in items) {
      await db.into(db.todos).insert(TodosCompanion.insert(
            taskId: newTaskId,
            content: item.itemText,
            sortOrder: drift.Value(sortIdx++),
            workflowId: drift.Value(wf.id),
            workflowName: drift.Value(wf.name),
          ));
    }
  }
  for (final todo in selected.customTodos) {
    await db.into(db.todos).insert(TodosCompanion.insert(
          taskId: newTaskId,
          content: todo.content,
          sortOrder: drift.Value(sortIdx++),
        ));
  }
  if (selected.template.hardwareBundleId != null) {
    final bundleItems = await (db.select(db.hardwareBundleItems)
          ..where((i) =>
              i.bundleId.equals(selected.template.hardwareBundleId!))
          ..orderBy([(i) => drift.OrderingTerm.asc(i.sortOrder)]))
        .get();
    for (var i = 0; i < bundleItems.length; i++) {
      await db.into(db.hardware).insert(HardwareCompanion.insert(
            taskId: newTaskId,
            type: bundleItems[i].type,
            name: drift.Value(bundleItems[i].name),
            serial: drift.Value(bundleItems[i].serial),
            notes: drift.Value(bundleItems[i].notes),
            sortOrder: drift.Value(i),
          ));
    }
  }

  ref.invalidate(tasksProvider);
  _dashTriggerSync(ref);
  if (!context.mounted) return;
  await context.push('/tasks/$newTaskId');
  ref.invalidate(tasksProvider);
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
  final tech = ref.read(settingsProvider).valueOrNull?.technicianName ?? '';
  await db.into(db.tasks).insert(
        TasksCompanion.insert(
          id: drift.Value(taskId),
          title: title,
          assignedTo: drift.Value(tech.isEmpty ? null : tech),
        ),
      );
  await ref.read(timerProvider.notifier).start(taskId);
  ref.invalidate(tasksProvider);
  _dashTriggerSync(ref);
  if (context.mounted) context.push('/tasks/$taskId');
}

void _dashTriggerSync(WidgetRef ref) {
  final s = ref.read(settingsProvider).valueOrNull;
  if (s == null) return;
  if (s.syncRole == 'SERVER') {
    ref.read(syncServerProvider).nudge();
  } else if (s.syncRole == 'CLIENT' && s.syncServerHost.isNotEmpty) {
    triggerManualSync(ref);
  }
}

// ─── Timer starten: neu oder bestehender Task ─────────────────────────────────

Future<void> _startTimerOptions(BuildContext context, WidgetRef ref) async {
  final cs = Theme.of(context).colorScheme;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Timer starten',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
          ),
          ListTile(
            leading: Icon(Icons.bolt, color: cs.primary),
            title: const Text('Neuer Task (Schnellstart)'),
            subtitle: const Text('Sofort starten, Details später'),
            onTap: () => Navigator.pop(ctx, 'new'),
          ),
          ListTile(
            leading: Icon(Icons.playlist_play, color: cs.primary),
            title: const Text('Bestehender Task…'),
            subtitle: const Text('Timer für einen vorhandenen Task starten'),
            onTap: () => Navigator.pop(ctx, 'existing'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'new') {
    await _quickStart(context, ref);
  } else if (choice == 'existing') {
    await _startExistingTask(context, ref);
  }
}

Future<void> _startExistingTask(BuildContext context, WidgetRef ref) async {
  final all = await ref.read(tasksProvider.future);
  final timer = ref.read(timerProvider);
  final candidates = all
      .where((t) =>
          t.task.status != 'COMPLETED' && !timer.containsKey(t.task.id))
      .toList()
    ..sort((a, b) => b.task.updatedAt.compareTo(a.task.updatedAt));
  if (!context.mounted) return;
  if (candidates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Keine startbaren Tasks vorhanden')),
    );
    return;
  }
  final selected = await showModalBottomSheet<TaskWithDetails>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExistingTaskPicker(tasks: candidates),
  );
  if (selected == null || !context.mounted) return;
  await ref.read(timerProvider.notifier).start(selected.task.id);
  ref.invalidate(tasksProvider);
  if (context.mounted) context.push('/tasks/${selected.task.id}');
}

class _ExistingTaskPicker extends StatefulWidget {
  final List<TaskWithDetails> tasks;
  const _ExistingTaskPicker({required this.tasks});

  @override
  State<_ExistingTaskPicker> createState() => _ExistingTaskPickerState();
}

class _ExistingTaskPickerState extends State<_ExistingTaskPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.tasks.where((t) {
      if (_q.isEmpty) return true;
      final s = '${t.task.title} ${t.customer?.name ?? ''}'.toLowerCase();
      return s.contains(_q);
    }).toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Task suchen…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final t = filtered[i];
                  return ListTile(
                    leading: const Icon(Icons.radio_button_unchecked),
                    title: Text(t.task.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle:
                        t.customer != null ? Text(t.customer!.name) : null,
                    onTap: () => Navigator.pop(context, t),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
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
