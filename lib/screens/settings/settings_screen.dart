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
import 'hardware_bundle_screen.dart' show HardwareBundleScreen;
import 'device_library_screen.dart';
import 'task_templates_screen.dart';
import 'data_exchange_screen.dart';
import '../handbuch_screen.dart';

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

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      // withData: true gets bytes directly — required on iOS where path is temp
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
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
    setState(() => _logoPath = destPath);
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
    setState(() => _backupLoading = true);
    try {
      final db = ref.read(databaseProvider);
      await BackupService.exportBackup(db);
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
      final result = await BackupService.importBackup(db);
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
            .showSnackBar(SnackBar(content: Text('Import Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _backupLoading = false);
    }
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
                  errorBuilder: (_, __, ___) =>
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
