import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../db/database.dart' hide AppSettings;
import '../../providers/settings_provider.dart';
import 'sync_service.dart';

/// Handles automatic sync scheduling based on AppSettings.
/// Register as a WidgetsBindingObserver in main.dart and call [onSettingsChanged]
/// whenever settings update.
class SyncScheduler with WidgetsBindingObserver {
  final AppDatabase db;
  AppSettings _settings;
  Timer? _timer;

  /// Called after each sync completes (success or error).
  final void Function(SyncResult)? onResult;

  SyncScheduler({
    required this.db,
    required AppSettings settings,
    this.onResult,
  }) : _settings = settings;

  void onSettingsChanged(AppSettings newSettings) {
    _settings = newSettings;
    _reschedule();
  }

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _reschedule();
    if (_settings.syncRole == 'CLIENT' && _settings.syncOnAppStart) {
      _runSync();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _settings.syncRole == 'CLIENT' &&
        _settings.syncOnResume) {
      _runSync();
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _reschedule() {
    _timer?.cancel();
    _timer = null;

    if (_settings.syncRole != 'CLIENT' || !_settings.syncAutoEnabled) return;
    final interval = Duration(minutes: _settings.syncAutoIntervalMinutes.clamp(1, 60));
    _timer = Timer.periodic(interval, (_) => _runSync());
  }

  void _runSync() {
    final service = SyncService(db: db, settings: _settings);
    service.sync().then((result) => onResult?.call(result));
  }
}
