import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/workflows_provider.dart';
import '../../providers/hardware_bundle_provider.dart';
import '../../providers/general_notes_provider.dart';
import '../../providers/note_templates_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../services/data_exchange_service.dart';

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
        ],
      ),
    );
  }
}
