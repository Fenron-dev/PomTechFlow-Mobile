import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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

    // Get local IP (best effort — first non-loopback IPv4)
    String? localIp;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        if (iface.name.startsWith('lo')) continue;
        for (final addr in iface.addresses) {
          localIp = addr.address;
          break;
        }
        if (localIp != null) break;
      }
    } catch (_) {}

    final qrData = jsonEncode({
      'host': localIp ?? '',
      'port': kSyncPort,
      'token': token,
      'serverDeviceId': settings.deviceId,
      'serverName': settings.effectiveDeviceName,
    });

    setState(() {
      _pin = pin;
      _qrData = qrData;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                children: [
                  Text('Scanne diesen QR-Code mit dem Client-Gerät',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Gültig für 5 Minuten',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 24),
                  if (_qrData != null)
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: QrImageView(
                          data: _qrData!,
                          version: QrVersions.auto,
                          size: 260,
                        ),
                      ),
                    ),
                  const SizedBox(height: 32),
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
                ],
              ),
            ),
    );
  }
}
