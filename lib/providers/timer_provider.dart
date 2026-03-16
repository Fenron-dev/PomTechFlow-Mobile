import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'database_provider.dart';
import '../db/database.dart';

enum TimerStatus { idle, running, paused }

/// Visual reference cycle for the ring animation (25 min, configurable)
const int _ringCycleSecs = 25 * 60;

class TimerState {
  final TimerStatus status;
  final int elapsedSeconds;
  final String? activeTaskId;
  final String? activeSessionId;

  const TimerState({
    this.status = TimerStatus.idle,
    this.elapsedSeconds = 0,
    this.activeTaskId,
    this.activeSessionId,
  });

  /// Ring fills over a configurable cycle (default 25 min) then resets.
  double get progress =>
      (elapsedSeconds % _ringCycleSecs) / _ringCycleSecs;

  String get timeString {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    final s = elapsedSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  TimerState copyWith({
    TimerStatus? status,
    int? elapsedSeconds,
    String? activeTaskId,
    String? activeSessionId,
  }) =>
      TimerState(
        status: status ?? this.status,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        activeTaskId: activeTaskId ?? this.activeTaskId,
        activeSessionId: activeSessionId ?? this.activeSessionId,
      );
}

class TimerNotifier extends Notifier<TimerState> {
  Timer? _timer;
  DateTime? _sessionStart;

  @override
  TimerState build() {
    ref.onDispose(() => _timer?.cancel());
    return const TimerState();
  }

  Future<void> start(String taskId) async {
    if (state.status == TimerStatus.running) return;

    final db = ref.read(databaseProvider);
    _sessionStart = DateTime.now();

    final sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';
    await db.into(db.sessions).insert(SessionsCompanion.insert(
          id: drift.Value(sessionId),
          taskId: taskId,
          startTime: _sessionStart!,
          type: const drift.Value('WORK'),
        ));

    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        status: const drift.Value('ACTIVE'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    state = state.copyWith(
      status: TimerStatus.running,
      elapsedSeconds: 0,
      activeTaskId: taskId,
      activeSessionId: sessionId,
    );

    _startTick();
  }

  void pause() {
    if (state.status != TimerStatus.running) return;
    _timer?.cancel();
    state = state.copyWith(status: TimerStatus.paused);
  }

  void resume() {
    if (state.status != TimerStatus.paused) return;
    state = state.copyWith(status: TimerStatus.running);
    _startTick();
  }

  Future<void> stop() async {
    _timer?.cancel();
    await _finalizeSession();
    state = const TimerState();
  }

  void _startTick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
  }

  Future<void> _finalizeSession() async {
    if (state.activeSessionId == null || _sessionStart == null) return;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final duration = now.difference(_sessionStart!).inMinutes;

    await (db.update(db.sessions)
          ..where((s) => s.id.equals(state.activeSessionId!)))
        .write(SessionsCompanion(
      endTime: drift.Value(now),
      duration: drift.Value(duration),
    ));

    if (state.activeTaskId != null) {
      final task = await (db.select(db.tasks)
            ..where((t) => t.id.equals(state.activeTaskId!)))
          .getSingle();
      await (db.update(db.tasks)
            ..where((t) => t.id.equals(state.activeTaskId!)))
          .write(TasksCompanion(
        totalMinutes: drift.Value(task.totalMinutes + duration),
        updatedAt: drift.Value(now),
      ));
    }
    _sessionStart = null;
  }
}

final timerProvider = NotifierProvider<TimerNotifier, TimerState>(
  TimerNotifier.new,
);
