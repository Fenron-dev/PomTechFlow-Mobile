import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/timer_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/quick_stopwatch_provider.dart';

// ─── Intents ──────────────────────────────────────────────────────────────────

class NewTaskIntent extends Intent {
  const NewTaskIntent();
}

class ToggleTimerIntent extends Intent {
  const ToggleTimerIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class NavIntent extends Intent {
  final String route;
  const NavIntent(this.route);
}

class SettingsIntent extends Intent {
  const SettingsIntent();
}

class StopwatchToggleIntent extends Intent {
  const StopwatchToggleIntent();
}

class StopwatchStopIntent extends Intent {
  const StopwatchStopIntent();
}

// ─── Platform helper ──────────────────────────────────────────────────────────

/// On macOS use Meta (⌘), everywhere else use Control.
bool get _useMeta => !kIsWeb && Platform.isMacOS;

SingleActivator sc(LogicalKeyboardKey key) =>
    SingleActivator(key, control: !_useMeta, meta: _useMeta);

/// Ctrl shortcuts that stay as Ctrl even on macOS (e.g. number keys).
SingleActivator scCtrl(LogicalKeyboardKey key) =>
    SingleActivator(key, control: true);

// ─── Shortcuts map (used both here and in MenuBar for display) ────────────────

Map<ShortcutActivator, Intent> get appShortcuts => {
      sc(LogicalKeyboardKey.keyN): const NewTaskIntent(),
      sc(LogicalKeyboardKey.keyT): const ToggleTimerIntent(),
      sc(LogicalKeyboardKey.keyF): const SearchIntent(),
      sc(LogicalKeyboardKey.comma): const SettingsIntent(),
      scCtrl(LogicalKeyboardKey.digit1): const NavIntent('/dashboard'),
      scCtrl(LogicalKeyboardKey.digit2): const NavIntent('/focus'),
      scCtrl(LogicalKeyboardKey.digit3): const NavIntent('/tasks'),
      scCtrl(LogicalKeyboardKey.digit4): const NavIntent('/notes'),
      scCtrl(LogicalKeyboardKey.digit5): const NavIntent('/calendar'),
      // Schnell-Stoppuhr
      SingleActivator(LogicalKeyboardKey.space, control: true, shift: true):
          const StopwatchToggleIntent(),
      SingleActivator(LogicalKeyboardKey.enter, control: true, shift: true):
          const StopwatchStopIntent(),
    };

// ─── Wrapper widget ───────────────────────────────────────────────────────────

class KeyboardShortcutsWrapper extends ConsumerWidget {
  final Widget child;
  const KeyboardShortcutsWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: appShortcuts,
      child: Actions(
        actions: {
          NewTaskIntent: CallbackAction<NewTaskIntent>(
            onInvoke: (_) {
              GoRouter.of(context).push('/tasks/new');
              return null;
            },
          ),
          ToggleTimerIntent: CallbackAction<ToggleTimerIntent>(
            onInvoke: (_) {
              _toggleTimer(ref);
              return null;
            },
          ),
          SearchIntent: CallbackAction<SearchIntent>(
            onInvoke: (_) {
              GoRouter.of(context).push('/search');
              return null;
            },
          ),
          NavIntent: CallbackAction<NavIntent>(
            onInvoke: (intent) {
              GoRouter.of(context).go(intent.route);
              return null;
            },
          ),
          SettingsIntent: CallbackAction<SettingsIntent>(
            onInvoke: (_) {
              GoRouter.of(context).push('/settings');
              return null;
            },
          ),
          StopwatchToggleIntent: CallbackAction<StopwatchToggleIntent>(
            onInvoke: (_) {
              ref.read(quickStopwatchProvider.notifier).toggle();
              return null;
            },
          ),
          StopwatchStopIntent: CallbackAction<StopwatchStopIntent>(
            onInvoke: (_) {
              ref.read(quickStopwatchProvider.notifier).stopAndRequestSave();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          canRequestFocus: true,
          child: child,
        ),
      ),
    );
  }

  Future<void> _toggleTimer(WidgetRef ref) async {
    final timer = ref.read(timerProvider);
    final notifier = ref.read(timerProvider.notifier);

    // Running → pause
    final running = timer.entries
        .where((e) => e.value.status == TimerStatus.running)
        .toList();
    if (running.isNotEmpty) {
      notifier.pause(running.first.key);
      return;
    }

    // Paused → resume
    final paused = timer.entries
        .where((e) => e.value.status == TimerStatus.paused)
        .toList();
    if (paused.isNotEmpty) {
      notifier.resume(paused.first.key);
      return;
    }

    // Nothing active → start timer for first ACTIVE task
    final tasks = ref.read(tasksProvider).valueOrNull ?? [];
    final firstActive =
        tasks.where((t) => t.task.status == 'ACTIVE').firstOrNull;
    if (firstActive != null) {
      await notifier.start(firstActive.task.id);
    }
  }
}
