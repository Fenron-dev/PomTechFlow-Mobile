import 'package:flutter/material.dart';
import '../../services/webdav_service.dart';

class WebDavSettingsScreen extends StatefulWidget {
  const WebDavSettingsScreen({super.key});

  @override
  State<WebDavSettingsScreen> createState() => _WebDavSettingsScreenState();
}

class _WebDavSettingsScreenState extends State<WebDavSettingsScreen> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _loading = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await WebDavService.loadConfig();
    setState(() {
      _urlCtrl.text = config.url;
      _userCtrl.text = config.username;
      _passCtrl.text = config.password;
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  WebDavConfig get _currentConfig => WebDavConfig(
        url: _urlCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );

  Future<void> _testConnection() async {
    setState(() {
      _loading = true;
      _testResult = null;
    });
    final error = await WebDavService.testConnection(_currentConfig);
    setState(() {
      _loading = false;
      _testSuccess = error == null;
      _testResult = error ?? 'Verbindung erfolgreich!';
    });
  }

  Future<void> _save() async {
    await WebDavService.saveConfig(_currentConfig);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV-Einstellungen gespeichert')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV-Einstellungen'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Speichern')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_outlined, color: cs.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Verbinde einen WebDAV-Server (z.B. Nextcloud, Synology, ownCloud) '
                    'um Backups direkt hochzuladen und zu laden.\n\n'
                    'URL-Beispiel:\nhttps://mein-server.de/remote.php/dav/files/nutzer/PomTechFlow',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          TextFormField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'Server-URL *',
              hintText: 'https://nextcloud.example.com/remote.php/dav/files/user/PomTechFlow',
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              labelText: 'Benutzername',
              prefixIcon: Icon(Icons.person_outline),
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscurePass,
            decoration: InputDecoration(
              labelText: 'Passwort / App-Token',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscurePass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 24),

          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            OutlinedButton.icon(
              onPressed: _currentConfig.isConfigured ? _testConnection : null,
              icon: const Icon(Icons.wifi_tethering_outlined),
              label: const Text('Verbindung testen'),
            ),

          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _testSuccess
                    ? cs.secondaryContainer
                    : cs.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _testSuccess ? Icons.check_circle_outline : Icons.error_outline,
                    color: _testSuccess ? cs.secondary : cs.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _testSuccess
                                ? cs.onSecondaryContainer
                                : cs.onErrorContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}
