import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../providers/settings_provider.dart' hide AppSettings;
import '../../providers/settings_provider.dart' as sp;
import '../../providers/database_provider.dart';
import '../../services/backup_service.dart';
import '../../services/webdav_service.dart';
import '../../services/app_lock_service.dart';
import 'webdav_settings_screen.dart';
import 'hardware_bundle_screen.dart' show HardwareBundleScreen;
import 'device_library_screen.dart';
import 'device_history_screen.dart';
import 'task_templates_screen.dart';
import 'data_exchange_screen.dart';
import 'maintenance_screen.dart';
import '../notes/note_templates_screen.dart';
import '../handbuch_screen.dart';
import '../tools/network_tools_screen.dart';
import '../knowledge/knowledge_screen.dart';

bool get _isIOS => !kIsWeb && Platform.isIOS;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => _SettingsForm(settings: settings),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  final sp.AppSettings settings;
  const _SettingsForm({required this.settings});

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final TextEditingController _companyCtrl;
  late final TextEditingController _techCtrl;
  late final TextEditingController _billingEmailCtrl;
  late int _aeMinutes;
  String? _logoPath;
  late int _pomodoroMinutes;
  late int _shortBreakMinutes;
  late int _longBreakMinutes;
  late String _themeMode;
  late String _storageBasePath;
  late bool _autoBackupEnabled;
  late String _autoBackupPath;
  bool _backupLoading = false;
  bool _lockSetup = false;

  @override
  void initState() {
    super.initState();
    _companyCtrl = TextEditingController(text: widget.settings.companyName);
    _techCtrl = TextEditingController(text: widget.settings.technicianName);
    _billingEmailCtrl = TextEditingController(text: widget.settings.billingEmail);
    _aeMinutes = widget.settings.aeMinutes;
    _logoPath = widget.settings.logoPath;
    _pomodoroMinutes = widget.settings.pomodoroMinutes;
    _shortBreakMinutes = widget.settings.shortBreakMinutes;
    _longBreakMinutes = widget.settings.longBreakMinutes;
    _themeMode = widget.settings.themeMode;
    _storageBasePath = widget.settings.storageBasePath;
    _autoBackupEnabled = widget.settings.autoBackupEnabled;
    _autoBackupPath = widget.settings.autoBackupPath;
    AppLockService.isSetup().then((v) {
      if (mounted) setState(() => _lockSetup = v);
    });
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _techCtrl.dispose();
    _billingEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStorageDir() async {
    // iOS: directory picking not supported — use Documents directory
    if (_isIOS) return;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Speicherort wählen',
    );
    if (path != null) setState(() => _storageBasePath = path);
  }

  Future<void> _pickAutoBackupDir() async {
    if (_isIOS) return;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Auto-Backup Ordner wählen',
    );
    if (path != null) setState(() => _autoBackupPath = path);
  }

  static const _kMaxLogoBytes = 2 * 1024 * 1024; // 2 MB

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      // withData: true gets bytes directly — required on iOS where path is temp
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;

    // Guard against oversized logos (DoS / storage exhaustion)
    final fileSize = picked.bytes?.length ??
        (picked.path != null ? await File(picked.path!).length() : 0);
    if (fileSize > _kMaxLogoBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logo zu groß – maximal 2 MB erlaubt.'),
          ),
        );
      }
      return;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final ext = picked.name.split('.').last.toLowerCase();
    final destPath = '${docsDir.path}/company_logo.$ext';

    if (picked.bytes != null) {
      // iOS / web: write bytes to persistent location
      await File(destPath).writeAsBytes(picked.bytes!);
    } else if (picked.path != null) {
      // Desktop / Android: copy from temp/picked path
      await File(picked.path!).copy(destPath);
    } else {
      return;
    }
    if (mounted) setState(() => _logoPath = destPath);
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).save(
          widget.settings.copyWith(
            companyName: _companyCtrl.text.trim(),
            technicianName: _techCtrl.text.trim(),
            aeMinutes: _aeMinutes,
            pomodoroMinutes: _pomodoroMinutes,
            shortBreakMinutes: _shortBreakMinutes,
            longBreakMinutes: _longBreakMinutes,
            themeMode: _themeMode,
            logoPath: _logoPath,
            clearLogo: _logoPath == null,
            billingEmail: _billingEmailCtrl.text.trim(),
            storageBasePath: _storageBasePath,
            autoBackupEnabled: _autoBackupEnabled,
            autoBackupPath: _autoBackupPath,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einstellungen gespeichert')),
      );
    }
  }

  Future<void> _exportBackup() async {
    // Ask for optional password
    final password = await showDialog<String?>(
      context: context,
      builder: (_) => const _ExportPasswordDialog(),
    );
    if (password == null) return; // user cancelled dialog

    setState(() => _backupLoading = true);
    try {
      final db = ref.read(databaseProvider);
      await BackupService.exportBackup(db,
          password: password.isEmpty ? null : password);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _backupLoading = false);
    }
  }

  Future<void> _importBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Backup importieren?'),
        content: const Text(
            'Alle aktuellen Daten werden überschrieben. Fortfahren?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Importieren')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _backupLoading = true);
    try {
      final db = ref.read(databaseProvider);
      String result = await BackupService.importBackup(db);

      // If encrypted: ask for password and retry once
      if (result == kNeedsPassword && mounted) {
        final pw = await showDialog<String>(
          context: context,
          builder: (_) => const _ImportPasswordDialog(),
        );
        if (pw == null || !mounted) {
          setState(() => _backupLoading = false);
          return;
        }
        result = await BackupService.importBackup(db, password: pw);
      }

      if (!mounted) return;
      if (result == 'OK') {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup erfolgreich importiert')));
        ref.invalidate(settingsProvider);
      } else if (result == kWrongPassword) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Falsches Passwort.')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $result')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _backupLoading = false);
    }
  }

  // ── WebDAV ───────────────────────────────────────────────────────────────

  Future<void> _webDavUploadBackup() async {
    final config = await WebDavService.loadConfig();
    if (!mounted) return;
    if (!config.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zuerst WebDAV in den Einstellungen konfigurieren.')),
      );
      return;
    }
    setState(() => _backupLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final json = await BackupService.buildJsonString(db);
      final dateStr = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-');
      final filename = 'pomtechflow_backup_$dateStr.json';
      await WebDavService.uploadJson(config, json, filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup hochgeladen: $filename')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('WebDAV Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _backupLoading = false);
    }
  }

  Future<void> _webDavDownloadBackup() async {
    final config = await WebDavService.loadConfig();
    if (!mounted) return;
    if (!config.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zuerst WebDAV in den Einstellungen konfigurieren.')),
      );
      return;
    }
    setState(() => _backupLoading = true);
    List<WebDavFile> files;
    try {
      files = await WebDavService.listJsonFiles(config);
    } catch (e) {
      if (mounted) {
        setState(() => _backupLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('WebDAV Fehler: $e')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _backupLoading = false);

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Backup-Dateien auf dem WebDAV-Server gefunden.')),
      );
      return;
    }

    final chosen = await showDialog<WebDavFile>(
      context: context,
      builder: (_) => _WebDavPickerDialog(files: files),
    );
    if (chosen == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup importieren?'),
        content: Text('${chosen.name}\n\nAlle aktuellen Daten werden überschrieben. Fortfahren?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Importieren')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _backupLoading = true);
    try {
      final json = await WebDavService.downloadJson(config, chosen.name);
      final db = ref.read(databaseProvider);
      final result = await BackupService.importFromString(db, json);
      if (!mounted) return;
      if (result == 'OK') {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup erfolgreich importiert')));
        ref.invalidate(settingsProvider);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $result')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _backupLoading = false);
    }
  }

  // ── App-Lock ─────────────────────────────────────────────────────────────

  Future<void> _toggleAppLock(bool enable) async {
    if (enable) {
      final recovery = await showDialog<String>(
        context: context,
        builder: (_) => const _PinSetupDialog(),
      );
      if (recovery == null || !mounted) return;
      setState(() => _lockSetup = true);
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RecoveryCodeDialog(code: recovery),
      );
    } else {
      // Verify current PIN before disabling
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => const _PinVerifyDialog(
          title: 'PIN zur Bestätigung eingeben',
          confirmLabel: 'Sperre deaktivieren',
        ),
      );
      if (ok != true || !mounted) return;
      await AppLockService.disable();
      if (!mounted) return;
      setState(() => _lockSetup = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App-Sperre deaktiviert')));
    }
  }

  Future<void> _changePIN() async {
    // Verify old PIN first
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _PinVerifyDialog(
        title: 'Aktuellen PIN eingeben',
        confirmLabel: 'Weiter',
      ),
    );
    if (ok != true || !mounted) return;
    final recovery = await showDialog<String>(
      context: context,
      builder: (_) => const _PinSetupDialog(isChange: true),
    );
    if (recovery == null || !mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecoveryCodeDialog(code: recovery),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PIN geändert')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Stammdaten ──────────────────────────────────────────────
        _SectionHeader('Firma'),
        TextField(
          controller: _companyCtrl,
          decoration: const InputDecoration(labelText: 'Firmenname'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _techCtrl,
          decoration: const InputDecoration(labelText: 'Techniker Name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _billingEmailCtrl,
          decoration: const InputDecoration(
            labelText: 'Abrechnungs-E-Mail (intern)',
            hintText: 'z.B. buchhaltung@firma.de',
            helperText: 'Wird für interne Abrechnungsentwürfe verwendet',
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        // Logo für PDF-Berichte
        Row(
          children: [
            if (_logoPath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(_logoPath!),
                  height: 48,
                  width: 80,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
              const SizedBox(width: 12),
            ] else
              Container(
                height: 48,
                width: 80,
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.image_outlined,
                    color: Theme.of(context).colorScheme.outline),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Firmen-Logo (PDF-Berichte)',
                      style: Theme.of(context).textTheme.bodyMedium),
                  Text('PNG oder JPG, erscheint oben links',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
            TextButton(
              onPressed: _pickLogo,
              child: const Text('Auswählen'),
            ),
            if (_logoPath != null)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() => _logoPath = null),
              ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Speicherort ──────────────────────────────────────────────
        _SectionHeader('Dateispeicherort'),
        Text(
          'Standardverzeichnis für gespeicherte PDFs und Fotos. Leer = App-internes Verzeichnis.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _storageBasePath.isEmpty
                      ? 'App-Standard'
                      : _storageBasePath,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _storageBasePath.isEmpty
                            ? Theme.of(context).colorScheme.outline
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _pickStorageDir,
              child: const Text('Ändern'),
            ),
            if (_storageBasePath.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Zurücksetzen',
                onPressed: () => setState(() => _storageBasePath = ''),
              ),
          ],
        ),
        const SizedBox(height: 24),

        // ── AE ──────────────────────────────────────────────────────
        _SectionHeader('Arbeitseinheiten (AE)'),
        _StepperField(
          label: 'Minuten pro AE',
          value: _aeMinutes,
          min: 1,
          max: 60,
          onChanged: (v) => setState(() => _aeMinutes = v),
        ),
        const SizedBox(height: 24),

        // ── Timer ────────────────────────────────────────────────────
        _SectionHeader('Timer'),
        _StepperField(
          label: 'Fokuszeit (Minuten)',
          value: _pomodoroMinutes,
          min: 1,
          max: 120,
          onChanged: (v) => setState(() => _pomodoroMinutes = v),
        ),
        const SizedBox(height: 12),
        _StepperField(
          label: 'Kurze Pause (Minuten)',
          value: _shortBreakMinutes,
          min: 1,
          max: 30,
          onChanged: (v) => setState(() => _shortBreakMinutes = v),
        ),
        const SizedBox(height: 12),
        _StepperField(
          label: 'Lange Pause (Minuten)',
          value: _longBreakMinutes,
          min: 1,
          max: 60,
          onChanged: (v) => setState(() => _longBreakMinutes = v),
        ),
        const SizedBox(height: 24),

        // ── Darstellung ──────────────────────────────────────────────
        _SectionHeader('Darstellung'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'system',
                label: Text('System'),
                icon: Icon(Icons.brightness_auto)),
            ButtonSegment(
                value: 'light',
                label: Text('Hell'),
                icon: Icon(Icons.light_mode)),
            ButtonSegment(
                value: 'dark',
                label: Text('Dunkel'),
                icon: Icon(Icons.dark_mode)),
          ],
          selected: {_themeMode},
          onSelectionChanged: (s) {
            setState(() => _themeMode = s.first);
            // Sofort speichern damit das Theme direkt angewandt wird
            ref.read(settingsProvider.notifier).save(widget.settings.copyWith(
                  companyName: _companyCtrl.text.trim(),
                  technicianName: _techCtrl.text.trim(),
                  aeMinutes: _aeMinutes,
                  pomodoroMinutes: _pomodoroMinutes,
                  shortBreakMinutes: _shortBreakMinutes,
                  longBreakMinutes: _longBreakMinutes,
                  themeMode: s.first,
                  logoPath: _logoPath,
                  clearLogo: _logoPath == null,
                  billingEmail: _billingEmailCtrl.text.trim(),
                  storageBasePath: _storageBasePath,
                  autoBackupEnabled: _autoBackupEnabled,
                  autoBackupPath: _autoBackupPath,
                ));
          },
        ),
        const SizedBox(height: 32),

        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('Einstellungen speichern'),
        ),
        const SizedBox(height: 32),

        // ── Stammdaten ───────────────────────────────────────────────
        _SectionHeader('Stammdaten'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.business),
                title: const Text('Kunden'),
                subtitle: const Text('Kunden verwalten'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/customers'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.folder_copy_outlined),
                title: const Text('Workflows'),
                subtitle: const Text('Checklisten-Vorlagen'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/workflows'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Task-Vorlagen'),
                subtitle: const Text('Komplette Tasks als Vorlage'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TaskTemplatesScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('Geräte-Bibliothek'),
                subtitle: const Text('Vordefinierte Einzelgeräte'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DeviceLibraryScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('Geräteverlauf'),
                subtitle: const Text('Alle Geräte über alle Tasks'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DeviceHistoryScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Hardware Bundles'),
                subtitle: const Text('Geräte-Vorlagen für Tasks'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const HardwareBundleScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.swap_horiz_outlined),
                title: const Text('Datenaustausch'),
                subtitle: const Text('Kunden, Workflows, Bundles teilen'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DataExchangeScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Tools ────────────────────────────────────────────────────
        _SectionHeader('Tools'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.lan_outlined),
                title: const Text('Netzwerk-Tools'),
                subtitle: const Text('DNS, Port-Check, HTTP-Check'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NetworkToolsScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Wissensdatenbank'),
                subtitle: const Text('Problem-Lösungs-Einträge'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const KnowledgeScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Handbuch ─────────────────────────────────────────────────
        _SectionHeader('Hilfe'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Handbuch'),
            subtitle: const Text('Erklärungen zu allen Funktionen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const HandbuchScreen()),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Backup ───────────────────────────────────────────────────
        _SectionHeader('Backup & Wiederherstellung'),
        Text(
          'Sichere alle Daten als JSON-Datei. Beim App-Update oder Neuinstall bleiben die Daten erhalten wenn du vorher ein Backup erstellst.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 12),
        if (_backupLoading)
          const Center(child: CircularProgressIndicator())
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportBackup,
                  icon: const Icon(Icons.upload),
                  label: const Text('Backup erstellen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importBackup,
                  icon: const Icon(Icons.download),
                  label: const Text('Backup laden'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),

        // ── Auto-Backup ───────────────────────────────────────────────
        _SectionHeader('Automatisches Backup'),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Täglich automatisch sichern'),
          subtitle: Text(
            widget.settings.lastAutoBackupDate.isEmpty
                ? 'Noch kein Auto-Backup erstellt'
                : 'Letztes Backup: ${widget.settings.lastAutoBackupDate}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          value: _autoBackupEnabled,
          onChanged: (v) => setState(() => _autoBackupEnabled = v),
        ),
        if (_autoBackupEnabled) ...[
          const SizedBox(height: 8),
          if (_isIOS)
            _InfoRow(
              icon: Icons.info_outline,
              text: 'Backups werden im App-Dokumente-Ordner gespeichert '
                  '(über Dateien-App zugänglich).',
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _autoBackupPath.isEmpty
                          ? 'App-Dokumente/backups (Standard)'
                          : _autoBackupPath,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _autoBackupPath.isEmpty
                                ? Theme.of(context).colorScheme.outline
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _pickAutoBackupDir,
                  child: const Text('Ändern'),
                ),
                if (_autoBackupPath.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Zurücksetzen',
                    onPressed: () =>
                        setState(() => _autoBackupPath = ''),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Backups älter als 7 Tage werden automatisch gelöscht.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ],
        const SizedBox(height: 20),

        // ── WebDAV ────────────────────────────────────────────────────
        _SectionHeader('WebDAV / Cloud-Backup'),
        Text(
          'Backups direkt auf einen WebDAV-Server (z.B. Nextcloud, Synology) hochladen und laden.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('WebDAV konfigurieren'),
            subtitle: const Text('URL, Benutzername, Passwort'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const WebDavSettingsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_backupLoading)
          const Center(child: CircularProgressIndicator())
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _webDavUploadBackup,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Backup hochladen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _webDavDownloadBackup,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Backup laden'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),

        // ── Datenpflege ───────────────────────────────────────────────
        _SectionHeader('Datenpflege'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: const Text('Datenbankpflege'),
                subtitle: const Text('Archiv, Foto-Komprimierung, VACUUM'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const MaintenanceScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Notiz-Vorlagen'),
                subtitle: const Text('Eigene Vorlagen erstellen & verwalten'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NoteTemplatesScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Sicherheit ────────────────────────────────────────────────
        _SectionHeader('Sicherheit'),
        Card(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.lock_outline),
                title: const Text('App-Sperre (PIN)'),
                subtitle: Text(_lockSetup
                    ? 'App wird beim Starten gesperrt'
                    : 'Kein PIN gesetzt'),
                value: _lockSetup,
                onChanged: _toggleAppLock,
              ),
              if (_lockSetup) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('PIN ändern'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changePIN,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: Icons.info_outline,
          text: 'Der PIN schützt die App vor unbefugtem Zugriff. '
              'Beim Einrichten erhältst du einen Recovery-Code – '
              'bewahre ihn sicher auf.',
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.outline)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _StepperField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _StepperField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toString(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

// ── Export password dialog ─────────────────────────────────────────────────

/// Shown before every manual export. Returns:
/// - `null`  when the user cancels
/// - `''`    when the user chooses no password
/// - `<pw>`  when the user enters a password
class _ExportPasswordDialog extends StatefulWidget {
  const _ExportPasswordDialog();
  @override
  State<_ExportPasswordDialog> createState() => _ExportPasswordDialogState();
}

class _ExportPasswordDialogState extends State<_ExportPasswordDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _confirmNoEncryption = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Backup exportieren'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Backup mit Passwort verschlüsseln (empfohlen). '
            'Das Passwort wird beim Import benötigt.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Passwort (empfohlen)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_confirmNoEncryption) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: colorScheme.onErrorContainer, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Das Backup enthält sensible Daten und wird unverschlüsselt gespeichert!',
                      style: TextStyle(
                          color: colorScheme.onErrorContainer, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // cancel → null
          child: const Text('Abbrechen'),
        ),
        if (_confirmNoEncryption)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Trotzdem exportieren'),
          )
        else
          OutlinedButton(
            onPressed: () => setState(() => _confirmNoEncryption = true),
            child: const Text('Ohne Passwort'),
          ),
        FilledButton(
          onPressed: _ctrl.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Verschlüsselt exportieren'),
        ),
      ],
    );
  }
}

// ── Import password dialog ─────────────────────────────────────────────────

class _ImportPasswordDialog extends StatefulWidget {
  const _ImportPasswordDialog();
  @override
  State<_ImportPasswordDialog> createState() => _ImportPasswordDialogState();
}

class _ImportPasswordDialogState extends State<_ImportPasswordDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backup verschlüsselt'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Dieses Backup ist verschlüsselt. Bitte Passwort eingeben:'),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Passwort',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => Navigator.pop(context, _ctrl.text.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // cancel
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Entschlüsseln'),
        ),
      ],
    );
  }
}

// ── App-Lock dialogs ───────────────────────────────────────────────────────

/// PIN setup: enter new PIN twice. Returns the recovery code on success.
class _PinSetupDialog extends StatefulWidget {
  final bool isChange;
  const _PinSetupDialog({this.isChange = false});
  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final _ctrl1 = TextEditingController();
  final _ctrl2 = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl1.dispose();
    _ctrl2.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final pin = _ctrl1.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'Mindestens 4 Stellen.');
      return;
    }
    if (pin != _ctrl2.text.trim()) {
      setState(() => _error = 'PINs stimmen nicht überein.');
      return;
    }
    setState(() => _loading = true);
    final recovery = await AppLockService.setup(pin);
    if (mounted) Navigator.pop(context, recovery);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isChange ? 'Neuen PIN setzen' : 'App-Sperre einrichten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl1,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'PIN (4–6 Stellen)',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl2,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'PIN bestätigen',
              border: const OutlineInputBorder(),
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _loading ? null : _confirm,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('PIN setzen'),
        ),
      ],
    );
  }
}

/// Displays the one-time recovery code. User must tap "Notiert" to dismiss.
class _RecoveryCodeDialog extends StatelessWidget {
  final String code;
  const _RecoveryCodeDialog({required this.code});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Recovery-Code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Notiere diesen Code sicher! Er wird nur einmal angezeigt und '
            'ist der einzige Weg, die App zu entsperren, falls du deinen PIN vergisst.',
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              code,
              style: TextStyle(
                fontSize: 24,
                fontFamily: 'monospace',
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Notiert – Weiter'),
        ),
      ],
    );
  }
}

/// Asks the user to enter the current PIN for verification.
/// Returns true on correct PIN, false/null otherwise.
class _PinVerifyDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  const _PinVerifyDialog({required this.title, required this.confirmLabel});
  @override
  State<_PinVerifyDialog> createState() => _PinVerifyDialogState();
}

class _PinVerifyDialogState extends State<_PinVerifyDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() => _loading = true);
    final ok = await AppLockService.verifyPIN(_ctrl.text.trim());
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _error = 'Falscher PIN.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'PIN',
          border: const OutlineInputBorder(),
          counterText: '',
          errorText: _error,
        ),
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _verify(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _loading ? null : _verify,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ─── WebDAV File Picker Dialog ────────────────────────────────────────────────

class _WebDavPickerDialog extends StatelessWidget {
  final List<WebDavFile> files;
  const _WebDavPickerDialog({required this.files});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.cloud_download_outlined),
        SizedBox(width: 10),
        Text('Backup wählen'),
      ]),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: files.length,
          itemBuilder: (_, i) => ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(files[i].name,
                style: Theme.of(context).textTheme.bodyMedium),
            onTap: () => Navigator.pop(context, files[i]),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}
