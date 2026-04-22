import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/database_provider.dart';
import '../providers/settings_provider.dart';
import 'client/sync_service.dart';
import 'server/sync_server.dart';

// ── Sync Status ───────────────────────────────────────────────────────────────

class SyncStatusState {
  final SyncStatus status;
  final String? message;
  final DateTime? lastSyncAt;
  final List<Map<String, dynamic>> pendingConflicts;

  const SyncStatusState({
    this.status = SyncStatus.idle,
    this.message,
    this.lastSyncAt,
    this.pendingConflicts = const [],
  });

  SyncStatusState copyWith({
    SyncStatus? status,
    String? message,
    DateTime? lastSyncAt,
    List<Map<String, dynamic>>? pendingConflicts,
  }) =>
      SyncStatusState(
        status: status ?? this.status,
        message: message ?? this.message,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        pendingConflicts: pendingConflicts ?? this.pendingConflicts,
      );
}

class SyncStatusNotifier extends Notifier<SyncStatusState> {
  @override
  SyncStatusState build() => const SyncStatusState();

  void setStatus(SyncStatus status, {String? message}) {
    state = state.copyWith(status: status, message: message);
  }

  void onResult(SyncResult result) {
    state = SyncStatusState(
      status: result.status,
      message: result.message,
      lastSyncAt: result.completedAt ?? state.lastSyncAt,
      pendingConflicts: result.conflicts,
    );
  }

  void clearConflicts() => state = state.copyWith(pendingConflicts: []);
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatusState>(SyncStatusNotifier.new);

// ── Manual Sync Trigger ───────────────────────────────────────────────────────

final syncServiceProvider = Provider<SyncService?>((ref) {
  final settingsAsync = ref.watch(settingsProvider);
  final settings = settingsAsync.valueOrNull;
  if (settings == null || settings.syncRole != 'CLIENT') return null;
  final db = ref.watch(databaseProvider);
  return SyncService(db: db, settings: settings);
});

/// Call this to trigger a manual sync from anywhere in the app.
Future<void> triggerManualSync(WidgetRef ref) async {
  final service = ref.read(syncServiceProvider);
  if (service == null) return;

  ref.read(syncStatusProvider.notifier).setStatus(SyncStatus.syncing);
  final result = await service.sync();
  ref.read(syncStatusProvider.notifier).onResult(result);
}

// ── Server Instance ───────────────────────────────────────────────────────────

final syncServerProvider = Provider<SyncServer>((ref) => SyncServer());
