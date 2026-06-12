import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum StopwatchStatus { idle, running, paused }

class StopwatchState {
  final StopwatchStatus status;
  final int seconds;
  final DateTime? startTime;
  /// Set to true when stopped via keyboard shortcut → card shows save dialog.
  final bool pendingSave;

  const StopwatchState({
    this.status = StopwatchStatus.idle,
    this.seconds = 0,
    this.startTime,
    this.pendingSave = false,
  });

  StopwatchState copyWith({
    StopwatchStatus? status,
    int? seconds,
    DateTime? startTime,
    bool? pendingSave,
  }) =>
      StopwatchState(
        status: status ?? this.status,
        seconds: seconds ?? this.seconds,
        startTime: startTime ?? this.startTime,
        pendingSave: pendingSave ?? this.pendingSave,
      );

  bool get isIdle => status == StopwatchStatus.idle;
  bool get isRunning => status == StopwatchStatus.running;
  bool get isPaused => status == StopwatchStatus.paused;
  bool get isActive => !isIdle;
}

class QuickStopwatchNotifier extends Notifier<StopwatchState> {
  Timer? _ticker;
  // Timestamp when the current run segment started (after start or resume).
  DateTime? _resumeTime;
  // Accumulated seconds from all previous run segments (before current one).
  int _baseSeconds = 0;

  @override
  StopwatchState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const StopwatchState();
  }

  void start() {
    if (state.isRunning) return;
    _ticker?.cancel();
    _baseSeconds = 0;
    _resumeTime = DateTime.now();
    state = StopwatchState(
      status: StopwatchStatus.running,
      seconds: 0,
      startTime: DateTime.now(),
    );
    _tick();
  }

  void pause() {
    if (!state.isRunning) return;
    _ticker?.cancel();
    _ticker = null;
    // Freeze the accumulated seconds so resume continues from here.
    _baseSeconds = _currentSeconds();
    _resumeTime = null;
    state = state.copyWith(
      status: StopwatchStatus.paused,
      seconds: _baseSeconds,
    );
  }

  void resume() {
    if (!state.isPaused) return;
    _resumeTime = DateTime.now();
    state = state.copyWith(status: StopwatchStatus.running);
    _tick();
  }

  /// Toggle: idle→start, running→pause, paused→resume.
  void toggle() {
    if (state.isIdle) {
      start();
    } else if (state.isRunning) {
      pause();
    } else {
      resume();
    }
  }

  /// Stop and signal the card to show the save dialog.
  void stopAndRequestSave() {
    if (!state.isActive) return;
    _ticker?.cancel();
    _ticker = null;
    state = state.copyWith(
      status: StopwatchStatus.idle,
      seconds: _currentSeconds(),
      pendingSave: true,
    );
    _resumeTime = null;
  }

  /// Called by the card after it has handled the save dialog.
  void clearPendingSave({bool reset = true}) {
    state = reset
        ? const StopwatchState()
        : state.copyWith(pendingSave: false);
  }

  int _currentSeconds() {
    final resume = _resumeTime;
    if (resume == null) return _baseSeconds;
    return _baseSeconds + DateTime.now().difference(resume).inSeconds;
  }

  void _tick() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(seconds: _currentSeconds());
    });
  }
}

final quickStopwatchProvider =
    NotifierProvider<QuickStopwatchNotifier, StopwatchState>(
  QuickStopwatchNotifier.new,
);
