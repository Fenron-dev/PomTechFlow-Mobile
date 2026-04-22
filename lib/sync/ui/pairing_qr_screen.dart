import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/settings_provider.dart';
import '../server/sync_auth.dart';
import '../server/sync_server.dart';

class PairingQrScreen extends ConsumerStatefulWidget {
  const PairingQrScreen({super.key});

  @override
  ConsumerState<PairingQrScreen> createState() => _PairingQrScreenState();
}

class _PairingQrScreenState extends ConsumerState<PairingQrScreen> {
  String? _pin;
  String? _qrData;
  bool _loading = true;
  List<_IpEntry> _allIps = [];
  int _selectedIpIndex = 0;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;

    final token = await SyncAuth.generatePairingToken(settings.deviceId);
    final pin = SyncAuth.tokenToPin(token);

    // Collect all non-loopback, non-link-local IPv4 addresses with interface names.
    final ips = <_IpEntry>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          ips.add(_IpEntry(iface.name, addr.address));
        }
      }
    } catch (_) {}

    // Prefer LAN addresses (192.168.x.x, 10.x.x.x, 172.16-31.x.x).
    final lanIndex = ips.indexWhere((e) => _isLan(e.address));
    final selected = lanIndex >= 0 ? lanIndex : 0;

    final localIp = ips.isNotEmpty ? ips[selected].address : '';
    final qrData = jsonEncode({
      'host': localIp,
      'port': kSyncPort,
      'token': token,
      'serverDeviceId': settings.deviceId,
      'serverName': settings.effectiveDeviceName,
    });

    setState(() {
      _pin = pin;
      _qrData = qrData;
      _allIps = ips;
      _selectedIpIndex = selected;
      _loading = false;
    });
  }

  void _selectIp(int index) {
    if (index < 0 || index >= _allIps.length) return;
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;
    // Rebuild QR with same token but different host.
    if (_qrData == null) return;
    final decoded = jsonDecode(_qrData!) as Map<String, dynamic>;
    final newData = jsonEncode({...decoded, 'host': _allIps[index].address});
    setState(() {
      _selectedIpIndex = index;
      _qrData = newData;
    });
  }

  static bool _isLan(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    final parts = ip.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]) ?? 0;
      if (second >= 16 && second <= 31) return true;
    }
    return false;
  }

  String get _currentIp =>
      _allIps.isNotEmpty ? _allIps[_selectedIpIndex].address : '';

  @override
  Widget build(BuildContext context) {
    final isWindows = Platform.isWindows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerät verbinden'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _generate),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Scanne diesen QR-Code mit dem Client-Gerät',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Gültig für 5 Minuten',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 20),

                  // ── IP selector ────────────────────────────────────────
                  if (_allIps.length > 1) ...[
                    Text('Server-IP-Adresse:',
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var i = 0; i < _allIps.length; i++)
                          ChoiceChip(
                            label: Text(
                                '${_allIps[i].address}\n(${_allIps[i].interfaceName})',
                                style: const TextStyle(fontSize: 12)),
                            selected: _selectedIpIndex == i,
                            onSelected: (_) => _selectIp(i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ] else if (_allIps.length == 1) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Server-IP: ',
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(_currentIp,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () =>
                              Clipboard.setData(ClipboardData(text: _currentIp)),
                          child:
                              const Icon(Icons.copy_outlined, size: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── QR Code ────────────────────────────────────────────
                  if (_qrData != null)
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: QrImageView(
                          data: _qrData!,
                          version: QrVersions.auto,
                          size: 240,
                        ),
                      ),
                    ),

                  // ── Windows Firewall hint ──────────────────────────────
                  if (isWindows) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_outlined,
                              size: 18, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Windows Firewall: Falls die Verbindung fehlschlägt, '
                              'Port 8765 (TCP) in der Windows-Firewall freigeben:\n'
                              'Windows-Sicherheit → Firewall → Erweiterte Einstellungen '
                              '→ Eingehende Regeln → Neue Regel → Port 8765.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text('Alternativ: PIN eingeben',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (_pin != null)
                    Text(
                      _pin!,
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            letterSpacing: 12,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Client: Einstellungen → Synchronisation → Pairing',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _IpEntry {
  final String interfaceName;
  final String address;
  const _IpEntry(this.interfaceName, this.address);
}
