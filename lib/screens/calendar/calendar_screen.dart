import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/tasks_provider.dart';
import '../../db/database.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _focusedMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalender'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Heute',
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                _focusedMonth = DateTime(now.year, now.month);
                _selectedDay = DateTime(now.year, now.month, now.day);
              });
            },
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tasks) => _buildBody(context, tasks),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<TaskWithDetails> tasks) {
    final tasksByDay = _buildTasksByDay(tasks);
    final selectedTasks =
        _selectedDay != null ? (tasksByDay[_dayKey(_selectedDay!)] ?? []) : <TaskWithDetails>[];

    return Column(
      children: [
        _MonthHeader(
          month: _focusedMonth,
          onPrev: () => setState(
              () => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1)),
          onNext: () => setState(
              () => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1)),
        ),
        const _WeekdayRow(),
        _CalendarGrid(
          focusedMonth: _focusedMonth,
          tasksByDay: tasksByDay,
          selectedDay: _selectedDay,
          onDaySelected: (day) => setState(() => _selectedDay = day),
        ),
        const Divider(height: 1),
        Expanded(
          child: _DayTaskList(
            day: _selectedDay,
            tasks: selectedTasks,
          ),
        ),
      ],
    );
  }

  // ─── Task-Berechnungen ────────────────────────────────────────────────────

  Map<String, List<TaskWithDetails>> _buildTasksByDay(List<TaskWithDetails> tasks) {
    final map = <String, List<TaskWithDetails>>{};

    // Buffer: vorherigen und nächsten Monat mit einbeziehen (für Scroll-Übergänge)
    final windowStart = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    final windowEnd = DateTime(_focusedMonth.year, _focusedMonth.month + 2, 0);

    for (final twd in tasks) {
      final task = twd.task;

      if (!task.recurring) {
        // Einmalige Tasks: nur nach plannedDate
        final planned = task.plannedDate;
        if (planned == null) continue;
        final key = _dayKey(planned);
        map.putIfAbsent(key, () => []).add(twd);
      } else {
        // Wiederkehrende Tasks: Vorkommen im Fenster berechnen
        for (final occ in _recurringOccurrences(task, windowStart, windowEnd)) {
          final key = _dayKey(occ);
          map.putIfAbsent(key, () => []).add(twd);
        }
      }
    }
    return map;
  }

  List<DateTime> _recurringOccurrences(Task task, DateTime from, DateTime to) {
    final type = task.recurrenceType;
    if (type == null) return [];
    final interval = task.recurrenceInterval > 0 ? task.recurrenceInterval : 1;
    // Ankerdate: plannedDate falls vorhanden, sonst createdAt
    final anchor = task.plannedDate ?? task.createdAt;
    final results = <DateTime>[];

    switch (type) {
      case 'DAILY':
        var d = _dateOnly(anchor);
        // Springe zum ersten Tag ab "from"
        if (d.isBefore(from)) {
          final daysLeft = from.difference(d).inDays;
          final steps = (daysLeft / interval).ceil();
          d = d.add(Duration(days: steps * interval));
        }
        while (!d.isAfter(to)) {
          results.add(d);
          d = d.add(Duration(days: interval));
        }

      case 'WEEKLY':
        final weekday = task.recurrenceWeekday ?? anchor.weekday;
        var d = _dateOnly(anchor);
        // Adjust to the correct weekday on or after anchor
        final wdDiff = (weekday - d.weekday) % 7;
        d = d.add(Duration(days: wdDiff));
        // Advance to window
        if (d.isBefore(from)) {
          final weeksLeft = (from.difference(d).inDays / (interval * 7)).ceil();
          d = d.add(Duration(days: weeksLeft * interval * 7));
        }
        while (!d.isAfter(to)) {
          results.add(d);
          d = d.add(Duration(days: interval * 7));
        }

      case 'MONTHLY':
        final day = task.recurrenceMonthDay ?? anchor.day;
        var m = DateTime(anchor.year, anchor.month);
        // Advance to window
        while (_monthEnd(m).isBefore(from)) {
          m = DateTime(m.year, m.month + interval);
        }
        // Collect occurrences in window
        for (var i = 0; i < 24; i++) {
          final daysInMonth = DateTime(m.year, m.month + 1, 0).day;
          final occ = DateTime(m.year, m.month, day.clamp(1, daysInMonth));
          if (occ.isAfter(to)) break;
          if (!occ.isBefore(from)) results.add(occ);
          m = DateTime(m.year, m.month + interval);
        }

      case 'QUARTERLY':
        final day = task.recurrenceMonthDay ?? anchor.day;
        var m = DateTime(anchor.year, anchor.month);
        while (_monthEnd(m).isBefore(from)) {
          m = DateTime(m.year, m.month + 3);
        }
        for (var i = 0; i < 12; i++) {
          final daysInMonth = DateTime(m.year, m.month + 1, 0).day;
          final occ = DateTime(m.year, m.month, day.clamp(1, daysInMonth));
          if (occ.isAfter(to)) break;
          if (!occ.isBefore(from)) results.add(occ);
          m = DateTime(m.year, m.month + 3);
        }
    }

    return results;
  }

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  static DateTime _monthEnd(DateTime m) => DateTime(m.year, m.month + 1, 0);
  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ─── Monats-Header ────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthHeader({required this.month, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMMM yyyy', 'de_DE').format(month);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }
}

// ─── Wochentag-Zeile ─────────────────────────────────────────────────────────

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  static const _labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: _labels
            .map((l) => Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.outline,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ─── Kalender-Grid ────────────────────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final Map<String, List<TaskWithDetails>> tasksByDay;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  const _CalendarGrid({
    required this.focusedMonth,
    required this.tasksByDay,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final days = _gridDays();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 0.85,
      ),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final dayTasks = tasksByDay[key] ?? [];
        final isCurrentMonth = day.month == focusedMonth.month;
        final today = DateTime.now();
        final isToday = day.year == today.year &&
            day.month == today.month &&
            day.day == today.day;
        final isSelected = selectedDay != null &&
            day.year == selectedDay!.year &&
            day.month == selectedDay!.month &&
            day.day == selectedDay!.day;

        return _DayCell(
          day: day,
          tasks: dayTasks,
          isCurrentMonth: isCurrentMonth,
          isToday: isToday,
          isSelected: isSelected,
          onTap: () => onDaySelected(day),
        );
      },
    );
  }

  List<DateTime> _gridDays() {
    final firstOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    // Woche beginnt Montag (weekday 1=Mo..7=So)
    final offset = firstOfMonth.weekday - 1;
    final start = firstOfMonth.subtract(Duration(days: offset));
    return List.generate(42, (i) => start.add(Duration(days: i)));
  }
}

// ─── Tages-Zelle ─────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final DateTime day;
  final List<TaskWithDetails> tasks;
  final bool isCurrentMonth;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.tasks,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color? bg;
    Color textColor;
    if (isSelected) {
      bg = cs.primary;
      textColor = cs.onPrimary;
    } else if (isToday) {
      bg = cs.primaryContainer;
      textColor = cs.onPrimaryContainer;
    } else {
      bg = null;
      textColor = isCurrentMonth ? cs.onSurface : cs.outlineVariant;
    }

    // Dots: bis zu 3 verschiedene Priorität-Farben
    final dots = _buildDots(cs);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontWeight: isToday || isSelected ? FontWeight.bold : null,
                  ),
            ),
            if (dots.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: dots,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDots(ColorScheme cs) {
    if (tasks.isEmpty) return [];
    // Priorität → Farbe
    Color prioColor(String p) => switch (p) {
          'CRITICAL' => Colors.red,
          'HIGH' => Colors.orange,
          'NORMAL' => cs.primary,
          _ => cs.outline,
        };

    final seen = <String>{};
    final dots = <Widget>[];
    for (final t in tasks) {
      final p = t.task.priority;
      if (seen.contains(p)) continue;
      seen.add(p);
      dots.add(Container(
        width: 5,
        height: 5,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white70 : prioColor(p),
          shape: BoxShape.circle,
        ),
      ));
      if (dots.length >= 3) break;
    }
    return dots;
  }
}

// ─── Tages-Task-Liste ────────────────────────────────────────────────────────

class _DayTaskList extends StatelessWidget {
  final DateTime? day;
  final List<TaskWithDetails> tasks;

  const _DayTaskList({required this.day, required this.tasks});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (day == null) {
      return const SizedBox.shrink();
    }

    final dayLabel = DateFormat('EEEE, d. MMMM', 'de_DE').format(day!);

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dayLabel,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 8),
            Text('Keine Tasks', style: TextStyle(color: cs.outlineVariant)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '$dayLabel  ·  ${tasks.length} Task${tasks.length != 1 ? 's' : ''}',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: cs.primary, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: tasks.length,
            itemBuilder: (context, i) => _TaskTile(task: tasks[i]),
          ),
        ),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  final TaskWithDetails task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = task.task;

    Color prioColor = switch (t.priority) {
      'CRITICAL' => Colors.red,
      'HIGH' => Colors.orange,
      'NORMAL' => cs.primary,
      _ => cs.outline,
    };

    Color statusColor = switch (t.status) {
      'ACTIVE' => Colors.green,
      'COMPLETED' => cs.outline,
      'PAUSED' => Colors.orange,
      _ => cs.primary,
    };

    String statusLabel = switch (t.status) {
      'ACTIVE' => 'Aktiv',
      'COMPLETED' => 'Erledigt',
      'PAUSED' => 'Pausiert',
      _ => 'Geplant',
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.circle, size: 10, color: prioColor),
        title: Text(
          t.title,
          style: TextStyle(
            decoration: t.status == 'COMPLETED' ? TextDecoration.lineThrough : null,
            color: t.status == 'COMPLETED' ? cs.outline : null,
          ),
        ),
        subtitle: task.customer != null ? Text(task.customer!.name) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t.recurring)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.repeat, size: 14, color: cs.outline),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        onTap: () => context.push('/tasks/${t.id}'),
      ),
    );
  }
}
