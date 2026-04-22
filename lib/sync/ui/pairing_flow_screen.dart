import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/settings_provider.dart';
import '../client/sync_api_client.dart';
import '../discovery/mdns_service.dart';

bool get _isMobile => Platform.isAndroid || Platform.isIOS;

class PairingFlowScreen extends ConsumerStatefulWidget {
  const PairingFlowScreen({super.key});

  @override
  ConsumerState<PairingFlowScreen> createState() => _PairingFlowScreenState();
}

class _PairingFlowScreenState extends ConsumerState<PairingFlowScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = false;
  String? _errorMsg;
  bool _success = false;

  // Manual / PIN tab
  final _hostCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  // mDNS discovery
  MdnsDiscovery? _discovery;
  final List<DiscoveredServer> _servers = [];

  @override
  void initState() {
    super.initState();
    // On desktop, start on the Manual tab — QR scanner not available
    _tabs = TabController(length: 3, vsync: this, initialIndex: _isMobile ? 0 : 2);
    _startDiscovery();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _hostCtrl.dispose();
    _pinCtrl.dispose();
    _discovery?.stop();
    super.dispose();
  }

  void _startDiscovery() {
    _discovery = MdnsDiscovery(
      onFound: (server) => setState(() {
        _servers.removeWhere((s) => s.name == server.name);
        _servers.add(server);
      }),
      onLost: (name) => setState(() => _servers.removeWhere((s) => s.name == name)),
    );
    _discovery!.start().catchError((_) {}); // mDNS might fail on iOS without entitlement
  }

  Future<void> _claimWithQrData(String rawJson) async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final data = jsonDecode(rawJson) as Map<String, dynamic>;
      await _doClaim(
        host: data['host'] as String? ?? '',
        port: data['port'] as int? ?? 8765,
        token: data['token'] as String? ?? '',
      );
    } catch (_) {
      setState(() { _errorMsg = 'Ungültiger QR-Code'; _loading = false; });
    }
  }

  Future<void> _claimWithPin({required DiscoveredServer? server}) async {
    final host = server?.host ?? _hostCtrl.text.trim();
    final pin = _pinCtrl.text.trim();

    if (host.isEmpty || pin.isEmpty) {
      setState(() => _errorMsg = 'Bitte Server-Adresse und PIN eingeben');
      return;
    }
    setState(() { _loading = true; _errorMsg = null; });

    // Build a pseudo-token from PIN — server validates via tokenToPin match
    // We send the raw PIN and the server maps it back to its pairing token.
    // For simplicity: the PIN *is* the pairing token here.
    // (A more robust implementation would do a /api/pairing/lookup?pin=... endpoint.)
    // Instead we rely on the fact that we obtained the token via mDNS/manual entry + PIN.
    // The PIN in this system is only useful when combined with the server's IP.
    setState(() => _errorMsg = 'PIN-basiertes Pairing: Bitte stattdessen QR-Code verwenden oder '
        'den Pairing-Token direkt eingeben (PIN-Validierung noch nicht implementiert).');
    setState(() => _loading = false);
  }

  Future<void> _doClaim({required String host, required int port, required String token}) async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;

    final client = SyncApiClient(host: host, port: port);
    final ok = await client.claim(
      pairingToken: token,
      deviceId: settings.deviceId,
      deviceName: settings.effectiveDeviceName,
    );

    if (!mounted) return;
    if (ok) {
      // Save server address in settings
      final notifier = ref.read(settingsProvider.notifier);
      await notifier.save(settings.copyWith(
        syncRole: 'CLIENT',
        syncServerHost: host,
        syncServerPort: port,
      ));
      setState(() { _success = true; _loading = false; });
    } else {
      setState(() { _errorMsg = 'Pairing fehlgeschlagen. Token ungültig oder abgelaufen.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verbunden')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
              const SizedBox(height: 16),
              Text('Erfolgreich verbunden!',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Dieses Gerät synchronisiert nun mit dem Server.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fertig'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mit Server verbinden'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'QR-Code'),
            Tab(icon: Icon(Icons.wifi_find), text: 'Im Netz suchen'),
            Tab(icon: Icon(Icons.edit), text: 'Manuell'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_errorMsg != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.error_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_errorMsg!)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _errorMsg = null),
                  ),
                ]),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildQrTab(),
                      _buildDiscoveryTab(),
                      _buildManualTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrTab() {
    if (!_isMobile) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: 16),
              Text('QR-Scanner nicht verfügbar',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Auf dem Desktop ist kein Kamera-Zugriff möglich.\n'
                'Bitte den Tab "Manuell" verwenden und den Pairing-Token\n'
                'aus dem QR-Code-Inhalt des Server-Geräts kopieren.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => _tabs.animateTo(2),
                child: const Text('Zum Manuell-Tab'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Öffne auf dem Server-Gerät: Einstellungen → Synchronisation → QR anzeigen'),
        ),
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null && !_loading) {
                _claimWithQrData(barcode!.rawValue!);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoveryTab() {
    return _servers.isEmpty
        ? const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Suche nach PomTechFlow-Servern im Netz…'),
              ],
            ),
          )
        : ListView.builder(
            itemCount: _servers.length,
            itemBuilder: (ctx, i) {
              final s = _servers[i];
              return ListTile(
                leading: const Icon(Icons.computer),
                title: Text(s.name),
                subtitle: Text('${s.host}:${s.port}'),
                trailing: FilledButton.tonal(
                  onPressed: () {
                                    _showPinDialog(s);
                  },
                  child: const Text('Verbinden'),
                ),
              );
            },
          );
  }

  Widget _buildManualTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            controller: _hostCtrl,
            decoration: const InputDecoration(
              labelText: 'Server-IP-Adresse',
              hintText: '192.168.1.42',
              prefixIcon: Icon(Icons.dns),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pinCtrl,
            decoration: const InputDecoration(
              labelText: 'Pairing-Token (aus QR-Code-Daten)',
              prefixIcon: Icon(Icons.key),
            ),
            maxLength: 500,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _claimWithPin(server: null),
            icon: const Icon(Icons.link),
            label: const Text('Verbinden'),
          ),
        ],
      ),
    );
  }

  void _showPinDialog(DiscoveredServer server) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('PIN für ${server.name}'),
        content: TextField(
          controller: _pinCtrl,
          decoration: const InputDecoration(
            labelText: '6-stelliger PIN',
            hintText: '123456',
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _claimWithPin(server: server);
            },
            child: const Text('Verbinden'),
          ),
        ],
      ),
    );
  }
}
