import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'database_provider.dart';
import 'settings_provider.dart';
import '../db/database.dart';

enum TimerPhase { work, shortBreak, longBreak }

enum TimerStatus { idle, running, paused }

class TimerState {
  final TimerStatus status;
  final TimerPhase phase;
  final int secondsLeft;
  final int totalSeconds;
  final String? activeTaskId;
  final String? activeSessionId;
  final int completedPomodoros;

  const TimerState({
    this.status = TimerStatus.idle,
    this.phase = TimerPhase.work,
    this.secondsLeft = 25 * 60,
    this.totalSeconds = 25 * 60,
    this.activeTaskId,
    this.activeSessionId,
    this.completedPomodoros = 0,
  });

  double get progress =>
      totalSeconds > 0 ? 1 - (secondsLeft / totalSeconds) : 0;

  String get timeString {
    final m = secondsLeft ~/ 60;
    final s = secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  TimerState copyWith({
    TimerStatus? status,
    TimerPhase? phase,
    int? secondsLeft,
    int? totalSeconds,
    String? activeTaskId,
    String? activeSessionId,
    int? completedPomodoros,
  }) =>
      TimerState(
        status: status ?? this.status,
        phase: phase ?? this.phase,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        totalSeconds: totalSeconds ?? this.totalSeconds,
        activeTaskId: activeTaskId ?? this.activeTaskId,
        activeSessionId: activeSessionId ?? this.activeSessionId,
        completedPomodoros: completedPomodoros ?? this.completedPomodoros,
      );
}

class TimerNotifier extends Notifier<TimerState> {
  Timer? _timer;
  DateTime? _sessionStart;

  @override
  TimerState build() {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final secs = (settings?.pomodoroMinutes ?? 25) * 60;
    ref.onDispose(() => _timer?.cancel());
    return TimerState(secondsLeft: secs, totalSeconds: secs);
  }

  int _secsForPhase(TimerPhase phase) {
    final s = ref.read(settingsProvider).valueOrNull;
    return switch (phase) {
      TimerPhase.work => (s?.pomodoroMinutes ?? 25) * 60,
      TimerPhase.shortBreak => (s?.shortBreakMinutes ?? 5) * 60,
      TimerPhase.longBreak => (s?.longBreakMinutes ?? 15) * 60,
    };
  }

  Future<void> start(String taskId) async {
    if (state.status == TimerStatus.running) return;

    final db = ref.read(databaseProvider);
    _sessionStart = DateTime.now();

    // Session in DB anlegen
    final sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';
    await db.into(db.sessions).insert(SessionsCompanion.insert(
          id: drift.Value(sessionId),
          taskId: taskId,
          startTime: _sessionStart!,
          type: const drift.Value('WORK'),
        ));

    // Task auf ACTIVE setzen
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        status: const drift.Value('ACTIVE'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    final secs = _secsForPhase(TimerPhase.work);
    state = state.copyWith(
      status: TimerStatus.running,
      phase: TimerPhase.work,
      secondsLeft: secs,
      totalSeconds: secs,
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
    final secs = _secsForPhase(TimerPhase.work);
    state = TimerState(secondsLeft: secs, totalSeconds: secs);
  }

  void _startTick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _tick() async {
    if (state.secondsLeft <= 1) {
      _timer?.cancel();
      await _finalizeSession();
      _onPhaseComplete();
    } else {
      state = state.copyWith(secondsLeft: state.secondsLeft - 1);
    }
  }

  Future<void> _finalizeSession() async {
    if (state.activeSessionId == null || _sessionStart == null) return;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final duration =
        now.difference(_sessionStart!).inMinutes;

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

  void _onPhaseComplete() {
    final completed = state.phase == TimerPhase.work
        ? state.completedPomodoros + 1
        : state.completedPomodoros;

    TimerPhase nextPhase;
    if (state.phase == TimerPhase.work) {
      nextPhase =
          completed % 4 == 0 ? TimerPhase.longBreak : TimerPhase.shortBreak;
    } else {
      nextPhase = TimerPhase.work;
    }

    final secs = _secsForPhase(nextPhase);
    state = state.copyWith(
      status: TimerStatus.idle,
      phase: nextPhase,
      secondsLeft: secs,
      totalSeconds: secs,
      completedPomodoros: completed,
      activeSessionId: null,
    );
  }
}

final timerProvider = NotifierProvider<TimerNotifier, TimerState>(
  TimerNotifier.new,
);
