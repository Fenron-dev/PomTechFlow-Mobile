import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/database_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/workflows_provider.dart';
import '../../providers/hardware_bundle_provider.dart';
import '../../providers/general_notes_provider.dart';
import '../../providers/note_templates_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../services/data_exchange_service.dart';
import '../../services/webdav_service.dart';

class DataExchangeScreen extends ConsumerStatefulWidget {
  const DataExchangeScreen({super.key});

  @override
  ConsumerState<DataExchangeScreen> createState() => _DataExchangeScreenState();
}

class _DataExchangeScreenState extends ConsumerState<DataExchangeScreen> {
  bool _exportTasks = false;
  bool _exportCustomers = true;
  bool _exportWorkflows = true;
  bool _exportBundles = true;
  bool _exportNotes = false;
  bool _exportTemplates = false;
  bool _loading = false;

  Future<void> _export() async {
    if (!_exportTasks && !_exportCustomers && !_exportWorkflows && !_exportBundles && !_exportNotes && !_exportTemplates) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens eine Kategorie auswählen.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      await DataExchangeService.exportData(
        db,
        tasks: _exportTasks,
        customers: _exportCustomers,
        workflows: _exportWorkflows,
        hardwareBundles: _exportBundles,
        generalNotes: _exportNotes,
        noteTemplates: _exportTemplates,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _import() async {
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final result = await DataExchangeService.importData(db);
      if (!mounted) return;

      if (result.cancelled) return;

      if (result.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.error!)));
        return;
      }

      // Provider invalidieren
      ref.invalidate(tasksProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(workflowsProvider);
      ref.invalidate(hardwareBundlesProvider);
      ref.invalidate(generalNotesProvider);
      ref.invalidate(noteTemplatesProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Importiert: ${result.summary}')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Datenaustausch')),
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
              children: [
                Icon(Icons.info_outline, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Teile Stammdaten mit Kollegen. Bestehende Einträge werden beim Import nicht überschrieben.',
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

          // Export
          Text('Exportieren',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.primary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                CheckboxListTile(
                  title: const Text('Tasks'),
                  subtitle: const Text('Aufgaben inkl. Checkliste, Hardware, Notizen'),
                  secondary: const Icon(Icons.task_outlined),
                  value: _exportTasks,
                  onChanged: (v) => setState(() => _exportTasks = v!),
                ),
                CheckboxListTile(
                  title: const Text('Kunden'),
                  subtitle: const Text('Alle Kundendaten'),
                  secondary: const Icon(Icons.business_outlined),
                  value: _exportCustomers,
                  onChanged: (v) => setState(() => _exportCustomers = v!),
                ),
                CheckboxListTile(
                  title: const Text('Workflows'),
                  subtitle: const Text('Checklisten-Vorlagen mit Punkten'),
                  secondary: const Icon(Icons.folder_copy_outlined),
                  value: _exportWorkflows,
                  onChanged: (v) => setState(() => _exportWorkflows = v!),
                ),
                CheckboxListTile(
                  title: const Text('Hardware Bundles'),
                  subtitle: const Text('Geräte-Vorlagen'),
                  secondary: const Icon(Icons.inventory_2_outlined),
                  value: _exportBundles,
                  onChanged: (v) => setState(() => _exportBundles = v!),
                ),
                CheckboxListTile(
                  title: const Text('Allgemeine Notizen'),
                  subtitle: const Text('Notizen inkl. Tags'),
                  secondary: const Icon(Icons.notes_outlined),
                  value: _exportNotes,
                  onChanged: (v) => setState(() => _exportNotes = v!),
                ),
                CheckboxListTile(
                  title: const Text('Notiz-Vorlagen'),
                  subtitle: const Text('Eigene Notizvorlagen'),
                  secondary: const Icon(Icons.description_outlined),
                  value: _exportTemplates,
                  onChanged: (v) => setState(() => _exportTemplates = v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.upload),
              label: const Text('Exportieren & Teilen'),
            ),

          const SizedBox(height: 32),

          // Import
          Text('Importieren',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.primary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Importiert eine von einem Kollegen geteilte Datei. Duplikate werden automatisch übersprungen.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.outline),
          ),
          const SizedBox(height: 12),
          if (!_loading)
            OutlinedButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.download),
              label: const Text('Datei importieren'),
            ),

          const SizedBox(height: 32),

          // ── WebDAV ──────────────────────────────────────────────────────
          Text('WebDAV Sync',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.primary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Exportiere direkt auf einen WebDAV-Server oder importiere eine dort gespeicherte Datei.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.outline),
          ),
          const SizedBox(height: 12),
          _WebDavSection(
            exportFlags: (
              tasks: _exportTasks,
              customers: _exportCustomers,
              workflows: _exportWorkflows,
              bundles: _exportBundles,
              notes: _exportNotes,
              templates: _exportTemplates,
            ),
            onImportDone: () {
              ref.invalidate(tasksProvider);
              ref.invalidate(customersProvider);
              ref.invalidate(workflowsProvider);
              ref.invalidate(hardwareBundlesProvider);
              ref.invalidate(generalNotesProvider);
              ref.invalidate(noteTemplatesProvider);
            },
          ),
        ],
      ),
    );
  }
}

// ─── WebDAV section widget ────────────────────────────────────────────────────

typedef _ExportFlags = ({
  bool tasks,
  bool customers,
  bool workflows,
  bool bundles,
  bool notes,
  bool templates,
});

class _WebDavSection extends ConsumerStatefulWidget {
  final _ExportFlags exportFlags;
  final VoidCallback onImportDone;
  const _WebDavSection({required this.exportFlags, required this.onImportDone});

  @override
  ConsumerState<_WebDavSection> createState() => _WebDavSectionState();
}

class _WebDavSectionState extends ConsumerState<_WebDavSection> {
  bool _busy = false;

  Future<WebDavConfig?> _loadConfig() => WebDavService.loadConfig();

  Future<void> _exportViaWebDav() async {
    final config = await _loadConfig();
    if (config == null || !config.isConfigured) {
      if (mounted) _showNotConfigured();
      return;
    }
    final flags = widget.exportFlags;
    if (!flags.tasks && !flags.customers && !flags.workflows &&
        !flags.bundles && !flags.notes && !flags.templates) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens eine Kategorie auswählen.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      final json = await DataExchangeService.buildExportJson(
        db,
        tasks: flags.tasks,
        customers: flags.customers,
        workflows: flags.workflows,
        hardwareBundles: flags.bundles,
        generalNotes: flags.notes,
        noteTemplates: flags.templates,
      );
      final ts = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
      final filename = 'ptf_data_$ts.json';
      await WebDavService.uploadJson(config, json, filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hochgeladen: $filename')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importViaWebDav() async {
    final config = await _loadConfig();
    if (config == null || !config.isConfigured) {
      if (mounted) _showNotConfigured();
      return;
    }
    setState(() => _busy = true);
    List<WebDavFile> files = [];
    try {
      files = await WebDavService.listJsonFiles(config);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
        setState(() => _busy = false);
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine JSON-Dateien auf dem Server gefunden.')),
      );
      return;
    }

    final selected = await showDialog<WebDavFile>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Datei auswählen'),
        content: SizedBox(
          width: 320,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: files.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(files[i].name,
                  style: Theme.of(ctx).textTheme.bodyMedium),
              onTap: () => Navigator.pop(ctx, files[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final content = await WebDavService.downloadJson(config, selected.name);
      final db = ref.read(databaseProvider);
      final result = await DataExchangeService.importFromJsonString(db, content);
      if (!mounted) return;
      if (result.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.error!)));
      } else {
        widget.onImportDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Importiert: ${result.summary}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showNotConfigured() {
    final router = GoRouter.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('WebDAV nicht konfiguriert.'),
        action: SnackBarAction(
          label: 'Einrichten',
          onPressed: () => router.push('/settings/webdav'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) return const Center(child: CircularProgressIndicator());
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _exportViaWebDav,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('WebDAV Export'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _importViaWebDav,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('WebDAV Import'),
          ),
        ),
      ],
    );
  }
}
