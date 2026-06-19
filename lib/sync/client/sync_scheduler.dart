import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../db/database.dart' hide AppSettings;
import '../../providers/settings_provider.dart';
import '../discovery/mdns_service.dart';
import 'sync_service.dart';

/// Handles automatic sync scheduling based on AppSettings.
/// Register as a WidgetsBindingObserver in main.dart and call [onSettingsChanged]
/// whenever settings update.
class SyncScheduler with WidgetsBindingObserver {
  final AppDatabase db;
  AppSettings _settings;
  Timer? _timer;
  Timer? _nudgeTimer;
  int _lastNudgeCounter = -1;

  /// Called after each sync completes (success or error).
  final void Function(SyncResult)? onResult;

  /// Called when mDNS discovers the server at a different IP, so the
  /// caller can persist the updated host in settings.
  final void Function(String newHost)? onHostRefreshed;

  SyncScheduler({
    required this.db,
    required AppSettings settings,
    this.onResult,
    this.onHostRefreshed,
  }) : _settings = settings;

  void onSettingsChanged(AppSettings newSettings) {
    final wasClient = _settings.syncRole == 'CLIENT' && _settings.syncServerHost.isNotEmpty;
    final nowClient = newSettings.syncRole == 'CLIENT' && newSettings.syncServerHost.isNotEmpty;
    _settings = newSettings;
    _reschedule();
    // Trigger immediate sync when first connecting as client
    if (!wasClient && nowClient) {
      _runSync();
    }
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
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
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
    _nudgeTimer?.cancel();
    _nudgeTimer = null;

    if (_settings.syncRole != 'CLIENT') return;

    if (_settings.syncAutoEnabled) {
      final interval = Duration(
          minutes: _settings.syncAutoIntervalMinutes.clamp(1, 60));
      _timer = Timer.periodic(interval, (_) => _runSync());
    }

    // Nudge polling: every 30 seconds check if server wants us to sync
    if (_settings.syncServerHost.isNotEmpty) {
      _nudgeTimer =
          Timer.periodic(const Duration(seconds: 30), (_) => _checkNudge());
    }
  }

  void _runSync() {
    _runSyncAsync();
  }

  Future<void> _runSyncAsync() async {
    // Try mDNS refresh if we have a server name stored
    if (_settings.syncServerName.isNotEmpty) {
      final newHost = await _refreshHostViaMdns(
        _settings.syncServerHost,
        _settings.syncServerName,
      );
      if (newHost != null && newHost != _settings.syncServerHost) {
        _settings = _settings.copyWith(syncServerHost: newHost);
        onHostRefreshed?.call(newHost);
      }
    }
    final service = SyncService(db: db, settings: _settings);
    final result = await service.sync();
    onResult?.call(result);
  }

  /// Attempts to find the server by name via mDNS and returns its host
  /// if discovered, otherwise returns null.
  Future<String?> _refreshHostViaMdns(
      String currentHost, String serverName) async {
    if (serverName.isEmpty) return null;
    String? found;
    try {
      final completer = Completer<String?>();
      late MdnsDiscovery discovery;
      discovery = MdnsDiscovery(
        onFound: (server) {
          if (server.name == serverName && !completer.isCompleted) {
            completer.complete(server.host);
          }
        },
        onLost: (_) {},
      );
      await discovery.start();
      // Wait up to 1 second for a response
      found = await completer.future
          .timeout(const Duration(milliseconds: 1000))
          .catchError((_) => null);
      await discovery.stop();
    } catch (_) {
      // mDNS may not be available — ignore
    }
    return found;
  }

  Future<void> _checkNudge() async {
    if (_settings.syncRole != 'CLIENT' || _settings.syncServerHost.isEmpty) {
      return;
    }
    try {
      final uri = Uri.parse(
          'http://${_settings.syncServerHost}:${_settings.syncServerPort}/api/v1/nudge');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final nudge = (body['nudge'] as int?) ?? 0;
        if (_lastNudgeCounter < 0) {
          // First check — just record the counter, don't trigger sync
          _lastNudgeCounter = nudge;
        } else if (nudge > _lastNudgeCounter) {
          _lastNudgeCounter = nudge;
          _runSync();
        }
      }
    } catch (_) {
      // Ignore network errors — nudge is best-effort
    }
  }
}
