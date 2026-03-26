import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'database_provider.dart';
import '../db/database.dart';

enum TimerStatus { running, paused }

/// Ring fills over this many seconds (visual only, no auto-stop).
const int _ringCycleSecs = 25 * 60;

class TimerEntry {
  final TimerStatus status;
  final int elapsedSeconds;
  final String sessionId;

  const TimerEntry({
    required this.status,
    required this.elapsedSeconds,
    required this.sessionId,
  });

  double get progress => (elapsedSeconds % _ringCycleSecs) / _ringCycleSecs;

  String get timeString {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    final s = elapsedSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  TimerEntry copyWith({TimerStatus? status, int? elapsedSeconds}) => TimerEntry(
        status: status ?? this.status,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        sessionId: sessionId,
      );
}

class MultiTimerNotifier extends Notifier<Map<String, TimerEntry>> {
  final Map<String, Timer> _tickers = {};
  final Map<String, DateTime> _sessionStarts = {};
  // Timestamp, ab dem das aktuelle Lauf-Intervall begann (null = pausiert)
  final Map<String, DateTime> _resumeTimestamps = {};
  // Sekunden, die vor dem aktuellen Lauf-Intervall bereits aufgelaufen sind
  final Map<String, int> _baseElapsed = {};

  @override
  Map<String, TimerEntry> build() {
    ref.onDispose(() {
      for (final t in _tickers.values) {
        t.cancel();
      }
    });
    return {};
  }

  bool isRunning(String taskId) =>
      state[taskId]?.status == TimerStatus.running;

  bool isActive(String taskId) => state.containsKey(taskId);

  int _currentElapsed(String taskId) {
    final base = _baseElapsed[taskId] ?? 0;
    final resumeTs = _resumeTimestamps[taskId];
    if (resumeTs == null) return base;
    return base + DateTime.now().difference(resumeTs).inSeconds;
  }

  Future<void> start(String taskId) async {
    if (state.containsKey(taskId)) return; // already running

    final db = ref.read(databaseProvider);
    final sessionStart = DateTime.now();
    final sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}_$taskId';

    await db.into(db.sessions).insert(SessionsCompanion.insert(
          id: drift.Value(sessionId),
          taskId: taskId,
          startTime: sessionStart,
          type: const drift.Value('WORK'),
        ));

    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        status: const drift.Value('ACTIVE'),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    _sessionStarts[taskId] = sessionStart;
    _resumeTimestamps[taskId] = sessionStart;
    _baseElapsed[taskId] = 0;

    final newState = Map<String, TimerEntry>.from(state);
    newState[taskId] = TimerEntry(
      status: TimerStatus.running,
      elapsedSeconds: 0,
      sessionId: sessionId,
    );
    state = newState;

    _startTick(taskId);
  }

  void pause(String taskId) {
    if (state[taskId]?.status != TimerStatus.running) return;
    _tickers[taskId]?.cancel();
    _tickers.remove(taskId);
    // Elapsed bis jetzt einfrieren, Resume-Timestamp entfernen
    _baseElapsed[taskId] = _currentElapsed(taskId);
    _resumeTimestamps.remove(taskId);
    final newState = Map<String, TimerEntry>.from(state);
    newState[taskId] = state[taskId]!.copyWith(
      status: TimerStatus.paused,
      elapsedSeconds: _baseElapsed[taskId]!,
    );
    state = newState;
  }

  void resume(String taskId) {
    if (state[taskId]?.status != TimerStatus.paused) return;
    _resumeTimestamps[taskId] = DateTime.now();
    final newState = Map<String, TimerEntry>.from(state);
    newState[taskId] = state[taskId]!.copyWith(status: TimerStatus.running);
    state = newState;
    _startTick(taskId);
  }

  Future<void> stop(String taskId) async {
    _tickers[taskId]?.cancel();
    _tickers.remove(taskId);
    await _finalizeSession(taskId);
    final newState = Map<String, TimerEntry>.from(state);
    newState.remove(taskId);
    state = newState;
    _sessionStarts.remove(taskId);
    _resumeTimestamps.remove(taskId);
    _baseElapsed.remove(taskId);
  }

  void _startTick(String taskId) {
    _tickers[taskId]?.cancel();
    _tickers[taskId] = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.containsKey(taskId)) return;
      final newState = Map<String, TimerEntry>.from(state);
      newState[taskId] = state[taskId]!.copyWith(
        elapsedSeconds: _currentElapsed(taskId),
      );
      state = newState;
    });
  }

  Future<void> _finalizeSession(String taskId) async {
    final entry = state[taskId];
    final sessionStart = _sessionStarts[taskId];
    if (entry == null || sessionStart == null) return;

    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    // Ceiling: angefangene Minute zählt voll (z.B. 90s → 2 Min, 30s → 1 Min)
    final durationSecs = now.difference(sessionStart).inSeconds;
    final duration = (durationSecs / 60).ceil().toInt();

    await (db.update(db.sessions)
          ..where((s) => s.id.equals(entry.sessionId)))
        .write(SessionsCompanion(
      endTime: drift.Value(now),
      duration: drift.Value(duration),
    ));

    final task = await (db.select(db.tasks)
          ..where((t) => t.id.equals(taskId)))
        .getSingle();
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        totalMinutes: drift.Value(task.totalMinutes + duration),
        updatedAt: drift.Value(now),
      ),
    );
  }
}

final timerProvider =
    NotifierProvider<MultiTimerNotifier, Map<String, TimerEntry>>(
  MultiTimerNotifier.new,
);
