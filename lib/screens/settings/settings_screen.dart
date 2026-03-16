import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/settings_provider.dart' hide AppSettings;
import '../../providers/settings_provider.dart' as sp;
import '../../providers/database_provider.dart';
import '../../services/backup_service.dart';
import 'hardware_bundle_screen.dart' show HardwareBundleScreen;
import 'device_library_screen.dart';
import 'task_templates_screen.dart';
import 'data_exchange_screen.dart';

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
  late int _aeMinutes;
  late int _pomodoroMinutes;
  late int _shortBreakMinutes;
  late int _longBreakMinutes;
  late String _themeMode;
  bool _backupLoading = false;

  @override
  void initState() {
    super.initState();
    _companyCtrl = TextEditingController(text: widget.settings.companyName);
    _techCtrl = TextEditingController(text: widget.settings.technicianName);
    _aeMinutes = widget.settings.aeMinutes;
    _pomodoroMinutes = widget.settings.pomodoroMinutes;
    _shortBreakMinutes = widget.settings.shortBreakMinutes;
    _longBreakMinutes = widget.settings.longBreakMinutes;
    _themeMode = widget.settings.themeMode;
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _techCtrl.dispose();
    super.dispose();
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
      builder: (_) => AlertDialog(
        title: const Text('Backup importieren?'),
        content: const Text(
            'Alle aktuellen Daten werden überschrieben. Fortfahren?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
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
          onSelectionChanged: (s) => setState(() => _themeMode = s.first),
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
        const SizedBox(height: 32),
      ],
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
