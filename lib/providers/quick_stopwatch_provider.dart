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

  @override
  StopwatchState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const StopwatchState();
  }

  void start() {
    if (state.isRunning) return;
    _ticker?.cancel();
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
    state = state.copyWith(status: StopwatchStatus.paused);
  }

  void resume() {
    if (!state.isPaused) return;
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
      pendingSave: true,
    );
  }

  /// Called by the card after it has handled the save dialog.
  void clearPendingSave({bool reset = true}) {
    state = reset
        ? const StopwatchState()
        : state.copyWith(pendingSave: false);
  }

  void _tick() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(seconds: state.seconds + 1);
    });
  }
}

final quickStopwatchProvider =
    NotifierProvider<QuickStopwatchNotifier, StopwatchState>(
  QuickStopwatchNotifier.new,
);
