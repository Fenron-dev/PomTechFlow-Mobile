import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/settings_provider.dart';
import '../../providers/database_provider.dart';
import '../../sync/sync_provider.dart';
import '../../sync/server/sync_server.dart';
import '../../sync/client/sync_service.dart';
import '../../sync/ui/pairing_qr_screen.dart';
import '../../sync/ui/pairing_flow_screen.dart';
import '../../sync/discovery/mdns_service.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  bool _advancedOpen = false;
  MdnsAdvertiser? _advertiser;

  @override
  void dispose() {
    _advertiser?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final server = ref.watch(syncServerProvider);

    return settingsAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (settings) => Scaffold(
        appBar: AppBar(title: const Text('Lokale Synchronisation')),
        body: ListView(
          children: [
            // ── Sync-Rolle ────────────────────────────────────────────────
            _SectionHeader('Rolle dieses Geräts'),
            _RoleSelector(
              current: settings.syncRole,
              onChanged: (role) => _changeRole(settings, role, server),
            ),
            const Divider(),

            // ── Server-Status ─────────────────────────────────────────────
            if (settings.syncRole == 'SERVER') ...[
              _SectionHeader('Server-Status'),
              _ServerStatusCard(settings: settings, server: server),
              const Divider(),
            ],

            // ── Client-Status ─────────────────────────────────────────────
            if (settings.syncRole == 'CLIENT') ...[
              _SectionHeader('Verbindung'),
              _ClientStatusCard(settings: settings, syncStatus: syncStatus),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_off),
                      label: const Text('Verbindung trennen'),
                      onPressed: () => _unpair(settings),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.sync),
                      label: const Text('Jetzt synchronisieren'),
                      onPressed: syncStatus.status == SyncStatus.syncing
                          ? null
                          : () => triggerManualSync(ref),
                    ),
                  ),
                ]),
              ),
              const Divider(),
            ],

            // ── Automatischer Sync ────────────────────────────────────────
            if (settings.syncRole == 'CLIENT') ...[
              _SectionHeader('Automatischer Sync'),
              SwitchListTile(
                title: const Text('Auto-Sync aktiviert'),
                value: settings.syncAutoEnabled,
                onChanged: (v) => _save(settings.copyWith(syncAutoEnabled: v)),
              ),
              if (settings.syncAutoEnabled) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Intervall: '),
                      Expanded(
                        child: Slider(
                          value: settings.syncAutoIntervalMinutes.toDouble().clamp(1, 60),
                          min: 1,
                          max: 60,
                          divisions: 59,
                          label: '${settings.syncAutoIntervalMinutes} Min.',
                          onChanged: (v) =>
                              _save(settings.copyWith(syncAutoIntervalMinutes: v.round())),
                        ),
                      ),
                      Text('${settings.syncAutoIntervalMinutes} Min.',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
              SwitchListTile(
                title: const Text('Sync beim App-Start'),
                value: settings.syncOnAppStart,
                onChanged: (v) => _save(settings.copyWith(syncOnAppStart: v)),
              ),
              SwitchListTile(
                title: const Text('Sync nach App-Resume'),
                value: settings.syncOnResume,
                onChanged: (v) => _save(settings.copyWith(syncOnResume: v)),
              ),
              const Divider(),
            ],

            // ── Gerätename ────────────────────────────────────────────────
            _SectionHeader('Gerät'),
            ListTile(
              title: const Text('Gerätename'),
              subtitle: Text(settings.effectiveDeviceName),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editDeviceName(settings),
            ),
            ListTile(
              title: const Text('Geräte-ID'),
              subtitle: Text(settings.deviceId, style: const TextStyle(fontSize: 11)),
            ),
            const Divider(),

            // ── Sync-Historie ─────────────────────────────────────────────
            _SectionHeader('Sync-Protokoll'),
            const _SyncHistorySection(),
            const Divider(),

            // ── Erweitert ─────────────────────────────────────────────────
            ListTile(
              title: const Text('Erweiterte Einstellungen'),
              trailing: Icon(_advancedOpen ? Icons.expand_less : Icons.expand_more),
              onTap: () => setState(() => _advancedOpen = !_advancedOpen),
            ),
            if (_advancedOpen) ...[
              SwitchListTile(
                title: const Text('App-Einstellungen synchronisieren'),
                subtitle: const Text(
                  'Achtung: Gerätespezifische Einstellungen (Speicherpfade, WebDAV, Sync-Rolle) werden nie überschrieben.',
                  style: TextStyle(fontSize: 12),
                ),
                value: settings.syncAppSettings,
                onChanged: (v) => _save(settings.copyWith(syncAppSettings: v)),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _changeRole(AppSettings settings, String role, SyncServer server) async {
    if (role == settings.syncRole) return;

    // Stop server if running
    if (server.isRunning) await server.stop();
    _advertiser?.stop();
    _advertiser = null;

    final updated = settings.copyWith(syncRole: role);
    await ref.read(settingsProvider.notifier).save(updated);

    if (role == 'SERVER' && mounted) {
      _startServer(updated, server);
    }
  }

  Future<void> _startServer(AppSettings settings, SyncServer server) async {
    final db = ref.read(databaseProvider);
    try {
      await server.start(
        db: db,
        serverDeviceId: settings.deviceId,
        serverName: settings.effectiveDeviceName,
        syncAppSettings: settings.syncAppSettings,
      );
      // Start mDNS advertising
      _advertiser = MdnsAdvertiser();
      await _advertiser!.start(kSyncPort, settings.effectiveDeviceName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server läuft auf Port $kSyncPort')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server-Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _save(AppSettings updated) async {
    await ref.read(settingsProvider.notifier).save(updated);
  }

  Future<void> _unpair(AppSettings settings) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verbindung trennen?'),
        content: const Text('Sync-Tokens werden gelöscht. Du kannst dich jederzeit neu verbinden.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trennen')),
        ],
      ),
    );
    if (confirm != true) return;

    final db = ref.read(databaseProvider);
    final service = SyncService(db: db, settings: settings);
    await service.unpair();
    await _save(settings.copyWith(syncRole: 'STANDALONE', syncServerHost: ''));
  }

  Future<void> _editDeviceName(AppSettings settings) async {
    final ctrl = TextEditingController(text: settings.deviceName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gerätename'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: settings.effectiveDeviceName,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (result != null) await _save(settings.copyWith(deviceName: result));
  }
}

// ── Sub-Widgets ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _RoleSelector extends StatelessWidget {
  final String current;
  final void Function(String) onChanged;
  const _RoleSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const roles = [
      ('STANDALONE', 'Eigenständig', 'Keine Synchronisation', Icons.phone_android),
      ('SERVER', 'Server', 'Andere Geräte verbinden sich mit diesem Gerät', Icons.hub),
      ('CLIENT', 'Client', 'Dieses Gerät verbindet sich mit einem Server', Icons.sync_alt),
    ];
    return Column(
      children: [
        for (final role in roles)
          ListTile(
            leading: Icon(
              current == role.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: current == role.$1 ? null : Colors.grey,
            ),
            title: Row(children: [
              Icon(role.$4, size: 20),
              const SizedBox(width: 8),
              Text(role.$2),
            ]),
            subtitle: Text(role.$3),
            onTap: () => onChanged(role.$1),
          ),
      ],
    );
  }
}

class _ServerStatusCard extends ConsumerStatefulWidget {
  final AppSettings settings;
  final SyncServer server;
  const _ServerStatusCard({required this.settings, required this.server});

  @override
  ConsumerState<_ServerStatusCard> createState() => _ServerStatusCardState();
}

class _ServerStatusCardState extends ConsumerState<_ServerStatusCard> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _formatLastSeen(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    return 'vor ${diff.inHours} Std.';
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final settings = widget.settings;
    final isRunning = server.isRunning;
    final clientCount = server.onlineClientCount;
    final clientNames = server.clientNames;
    final clientLastSeen = server.clientLastSeen;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(isRunning ? Icons.circle : Icons.circle_outlined,
                  color: isRunning ? Colors.green : Colors.grey, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isRunning
                      ? 'Server läuft · $clientCount Client${clientCount != 1 ? 's' : ''} verbunden'
                      : 'Server gestoppt',
                ),
              ),
              if (isRunning)
                TextButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('Stoppen'),
                  onPressed: () => server.stop(),
                )
              else
                TextButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Starten'),
                  onPressed: () {
                    final db = ref.read(databaseProvider);
                    server.start(
                      db: db,
                      serverDeviceId: settings.deviceId,
                      serverName: settings.effectiveDeviceName,
                      syncAppSettings: settings.syncAppSettings,
                    );
                  },
                ),
            ]),
            if (isRunning) ...[
              const SizedBox(height: 8),
              Text('Port: $kSyncPort',
                  style: Theme.of(context).textTheme.bodySmall),
              Text('Gerätename: ${settings.effectiveDeviceName}',
                  style: Theme.of(context).textTheme.bodySmall),

              if (clientLastSeen.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 6),
                Text('Verbundene Clients:',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
                const SizedBox(height: 4),
                ...clientLastSeen.entries.map((e) {
                  final deviceId = e.key;
                  final lastSeen = e.value;
                  final name = clientNames[deviceId] ?? deviceId;
                  final isOnline =
                      DateTime.now().difference(lastSeen).inMinutes < 5;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          isOnline ? Icons.circle : Icons.circle_outlined,
                          size: 8,
                          color: isOnline ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(name,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                        Text(
                          _formatLastSeen(lastSeen),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline),
                        ),
                      ],
                    ),
                  );
                }),
              ],

              const SizedBox(height: 12),
              const Text(
                'Hinweis: Der Server läuft nur solange die App geöffnet ist.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const PairingQrScreen()),
                    ),
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Gerät pairen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: clientCount == 0
                        ? null
                        : () {
                            server.nudge();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Sync-Signal gesendet'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                    icon: const Icon(Icons.sync),
                    label: const Text('Jetzt sync.'),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncHistorySection extends ConsumerWidget {
  const _SyncHistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(syncLogsProvider);
    return logsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (logs) {
        if (logs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('Noch keine Sync-Vorgänge.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline)),
          );
        }
        final fmt = DateFormat('dd.MM.yy HH:mm');
        return Column(
          children: logs.map((log) {
            final isSuccess = log.status == 'success';
            final isOffline = log.status == 'offline';
            final color = isSuccess
                ? Colors.green
                : isOffline
                    ? Colors.orange
                    : Colors.red;
            final icon = isSuccess
                ? Icons.check_circle_outline
                : isOffline
                    ? Icons.wifi_off_outlined
                    : Icons.error_outline;
            return ListTile(
              dense: true,
              leading: Icon(icon, size: 18, color: color),
              title: Text(
                fmt.format(log.syncedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              subtitle: Text(
                [
                  if (log.peerName != null) log.peerName!,
                  if (isSuccess) '↓${log.pulledCount} ↑${log.pushedCount}',
                  if (!isSuccess && log.errorMessage != null) log.errorMessage!,
                ].join('  ·  '),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              trailing: Text(log.deviceName,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline)),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ClientStatusCard extends StatelessWidget {
  final AppSettings settings;
  final SyncStatusState syncStatus;
  const _ClientStatusCard({required this.settings, required this.syncStatus});

  @override
  Widget build(BuildContext context) {
    final isConnected = settings.syncServerHost.isNotEmpty;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                isConnected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: isConnected ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(isConnected
                  ? 'Verbunden mit ${settings.syncServerHost}'
                  : 'Nicht verbunden'),
            ]),
            if (isConnected && syncStatus.lastSyncAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Letzter Sync: ${DateFormat('dd.MM.yyyy HH:mm').format(syncStatus.lastSyncAt!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (syncStatus.status == SyncStatus.syncing) ...[
              const SizedBox(height: 8),
              const Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Synchronisiere…'),
              ]),
            ],
            if (syncStatus.status == SyncStatus.error) ...[
              const SizedBox(height: 4),
              Text(syncStatus.message ?? 'Fehler',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            if (!isConnected)
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const PairingFlowScreen()),
                ),
                icon: const Icon(Icons.link),
                label: const Text('Mit Server verbinden'),
              )
            else
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const PairingFlowScreen()),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Neu verbinden'),
              ),
          ],
        ),
      ),
    );
  }
}
