import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NetworkToolsScreen extends StatefulWidget {
  const NetworkToolsScreen({super.key});

  @override
  State<NetworkToolsScreen> createState() => _NetworkToolsScreenState();
}

class _NetworkToolsScreenState extends State<NetworkToolsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Netzwerk-Tools'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.dns_outlined), text: 'DNS'),
            Tab(icon: Icon(Icons.lan_outlined), text: 'Port-Check'),
            Tab(icon: Icon(Icons.http_outlined), text: 'HTTP'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _DnsTab(),
          _PortTab(),
          _HttpTab(),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _ResultCard({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        title: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: cs.outline)),
        subtitle: SelectableText(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            color: color ?? cs.onSurface,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy_outlined, size: 18),
          tooltip: 'Kopieren',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Kopiert'), duration: Duration(seconds: 1)),
            );
          },
        ),
      ),
    );
  }
}

Widget _inputField(TextEditingController ctrl, String label,
        {String? hint, TextInputType? keyboard}) =>
    TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: keyboard ?? TextInputType.text,
      autocorrect: false,
      enableSuggestions: false,
    );

// ─── DNS Tab ──────────────────────────────────────────────────────────────────

class _DnsTab extends StatefulWidget {
  const _DnsTab();

  @override
  State<_DnsTab> createState() => _DnsTabState();
}

class _DnsTabState extends State<_DnsTab> {
  final _hostCtrl = TextEditingController();
  bool _loading = false;
  List<String> _results = [];
  String? _error;

  @override
  void dispose() {
    _hostCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) return;
    setState(() { _loading = true; _error = null; _results = []; });
    try {
      final addresses = await InternetAddress.lookup(host);
      setState(() {
        _results = addresses.map((a) => a.address).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _inputField(_hostCtrl, 'Hostname', hint: 'z.B. google.com',
            keyboard: TextInputType.url),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _lookup,
          icon: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.search),
          label: const Text('Auflösen'),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          _ResultCard(
              label: 'Fehler',
              value: _error!,
              color: Theme.of(context).colorScheme.error),
        ..._results.asMap().entries.map(
              (e) => _ResultCard(label: 'IP ${e.key + 1}', value: e.value),
            ),
        if (!_loading && _error == null && _results.isEmpty && _hostCtrl.text.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('Keine Ergebnisse',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline)),
            ),
          ),
      ],
    );
  }
}

// ─── Port-Check Tab ───────────────────────────────────────────────────────────

class _PortTab extends StatefulWidget {
  const _PortTab();

  @override
  State<_PortTab> createState() => _PortTabState();
}

class _PortTabState extends State<_PortTab> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '80');
  bool _loading = false;
  String? _result;
  Color? _resultColor;

  static const _commonPorts = [
    ('HTTP', 80), ('HTTPS', 443), ('SSH', 22), ('RDP', 3389),
    ('SMB', 445), ('FTP', 21), ('DNS', 53), ('SMTP', 25),
  ];

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    if (host.isEmpty || port == null) return;
    setState(() { _loading = true; _result = null; });
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host, port,
        timeout: const Duration(seconds: 5),
      );
      sw.stop();
      socket.destroy();
      setState(() {
        _result = 'Offen  ·  ${sw.elapsedMilliseconds} ms';
        _resultColor = Colors.green;
        _loading = false;
      });
    } on SocketException catch (e) {
      sw.stop();
      setState(() {
        _result = 'Geschlossen / Timeout\n${e.message}';
        _resultColor = Theme.of(context).colorScheme.error;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _result = 'Fehler: $e';
        _resultColor = Theme.of(context).colorScheme.error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _inputField(_hostCtrl, 'Host / IP', hint: '192.168.1.1',
            keyboard: TextInputType.url),
        const SizedBox(height: 12),
        _inputField(_portCtrl, 'Port', hint: '80',
            keyboard: TextInputType.number),
        const SizedBox(height: 8),
        // Schnell-Ports
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _commonPorts
              .map((p) => ActionChip(
                    label: Text('${p.$1} ${p.$2}'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _portCtrl.text = '${p.$2}'),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _check,
          icon: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.cable_outlined),
          label: const Text('Prüfen'),
        ),
        const SizedBox(height: 16),
        if (_result != null)
          Card(
            color: _resultColor?.withAlpha(30),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _resultColor == Colors.green
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    color: _resultColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_result!,
                        style: TextStyle(
                            color: _resultColor,
                            fontFamily: 'monospace')),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─── HTTP Tab ─────────────────────────────────────────────────────────────────

class _HttpTab extends StatefulWidget {
  const _HttpTab();

  @override
  State<_HttpTab> createState() => _HttpTabState();
}

class _HttpTabState extends State<_HttpTab> {
  final _urlCtrl = TextEditingController(text: 'https://');
  bool _loading = false;
  Map<String, String>? _result;
  bool _ok = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() { _loading = true; _result = null; });
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8)
        ..badCertificateCallback = (_, _, _) => true; // self-signed ok for internal use
      final req = await client.headUrl(Uri.parse(url));
      final res = await req.close();
      sw.stop();
      await res.drain<void>();
      client.close();
      setState(() {
        _ok = res.statusCode < 400;
        _result = {
          'Status': '${res.statusCode} ${res.reasonPhrase}',
          'Antwortzeit': '${sw.elapsedMilliseconds} ms',
          'Server': res.headers.value('server') ?? '–',
          'Content-Type': res.headers.value('content-type') ?? '–',
        };
        _loading = false;
      });
    } catch (e) {
      sw.stop();
      setState(() {
        _ok = false;
        _result = {'Fehler': e.toString(), 'Zeit': '${sw.elapsedMilliseconds} ms'};
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _inputField(_urlCtrl, 'URL', hint: 'https://server.local',
            keyboard: TextInputType.url),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _check,
          icon: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.http_outlined),
          label: const Text('Prüfen'),
        ),
        const SizedBox(height: 16),
        if (_result != null) ...[
          Row(
            children: [
              Icon(
                _ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                color: _ok ? Colors.green : cs.error,
              ),
              const SizedBox(width: 8),
              Text(
                _ok ? 'Erreichbar' : 'Fehler',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _ok ? Colors.green : cs.error),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._result!.entries.map(
            (e) => _ResultCard(label: e.key, value: e.value),
          ),
        ],
      ],
    );
  }
}
