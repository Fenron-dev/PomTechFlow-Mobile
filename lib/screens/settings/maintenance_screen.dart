import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart' as sp;
import '../../providers/tasks_provider.dart';
import '../../db/database.dart';
import '../../services/maintenance_service.dart';

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  MaintenanceStats? _stats;
  bool _loadingStats = true;

  // Archive controls
  int _archiveDays = 30;
  int _archivePreview = 0;
  bool _archiving = false;

  // Compress controls
  int _compressQuality = 70;
  bool _compressing = false;
  int _compressDone = 0;
  int _compressTotal = 0;

  // Cleanup / vacuum
  bool _cleaning = false;
  bool _vacuuming = false;

  // Archive list
  List<Task> _archivedTasks = [];
  bool _archiveExpanded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  String _storagePath() =>
      ref.read(sp.settingsProvider).valueOrNull?.storageBasePath ?? '';

  Future<void> _reload() async {
    setState(() => _loadingStats = true);
    final db = ref.read(databaseProvider);
    final stats = await MaintenanceService.getStats(db, _storagePath());
    final preview = await MaintenanceService.archivePreviewCount(
        db, olderThanDays: _archiveDays);
    final archived = await MaintenanceService.getArchivedTasks(db);
    if (mounted) {
      setState(() {
        _stats = stats;
        _archivePreview = preview;
        _archivedTasks = archived;
        _loadingStats = false;
      });
    }
  }

  Future<void> _updatePreview() async {
    final preview = await MaintenanceService.archivePreviewCount(
        ref.read(databaseProvider),
        olderThanDays: _archiveDays);
    if (mounted) setState(() => _archivePreview = preview);
  }

  // ── Archive ────────────────────────────────────────────────────────────

  Future<void> _runArchive() async {
    if (_archivePreview == 0) return;
    final confirmed = await _confirm(
      title: 'Tasks archivieren',
      body:
          '$_archivePreview abgeschlossene Tasks werden aus der Hauptliste entfernt und archiviert. '
          'Die Daten bleiben vollständig erhalten.',
      action: 'Archivieren',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _archiving = true);
    final result = await MaintenanceService.archiveTasks(
        ref.read(databaseProvider),
        olderThanDays: _archiveDays);
    ref.invalidate(tasksProvider);
    await _reload();
    if (mounted) {
      setState(() => _archiving = false);
      _snack('${result.archivedCount} Tasks archiviert');
    }
  }

  Future<void> _unarchive(Task task) async {
    await MaintenanceService.unarchiveTask(ref.read(databaseProvider), task.id);
    ref.invalidate(tasksProvider);
    await _reload();
    if (mounted) _snack('Task reaktiviert');
  }

  Future<void> _clearArchive() async {
    final confirmed = await _confirm(
      title: 'Archiv leeren',
      body:
          '${_archivedTasks.length} archivierte Tasks werden dauerhaft gelöscht '
          '(inkl. aller Fotos, Notizen und Zeiteinträge). Dieser Vorgang kann nicht rückgängig gemacht werden.',
      action: 'Dauerhaft löschen',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    await MaintenanceService.deleteArchivedTasks(ref.read(databaseProvider));
    ref.invalidate(tasksProvider);
    await _reload();
    if (mounted) _snack('Archiv geleert');
  }

  // ── Compress ───────────────────────────────────────────────────────────

  Future<void> _runCompress() async {
    final photoCount = _stats?.photoCount ?? 0;
    if (photoCount == 0) {
      _snack('Keine Fotos vorhanden');
      return;
    }
    final confirmed = await _confirm(
      title: 'Fotos komprimieren',
      body:
          '$photoCount Fotos werden auf Qualität $_compressQuality% komprimiert. '
          'Originale werden ersetzt (kein Rückgängig möglich).',
      action: 'Komprimieren',
    );
    if (confirmed != true || !mounted) return;

    setState(() { _compressing = true; _compressDone = 0; _compressTotal = photoCount; });
    final result = await MaintenanceService.compressPhotos(
      ref.read(databaseProvider),
      quality: _compressQuality,
      onProgress: (done, total) {
        if (mounted) setState(() { _compressDone = done; _compressTotal = total; });
      },
    );
    await _reload();
    if (mounted) {
      setState(() => _compressing = false);
      _snack(
        '${result.processedPhotos} Fotos komprimiert · '
        '${MaintenanceService.formatBytes(result.savedBytes)} gespart',
      );
    }
  }

  // ── Cleanup / Vacuum ──────────────────────────────────────────────────

  Future<void> _runCleanup() async {
    final orphaned = _stats?.orphanedFileCount ?? 0;
    if (orphaned == 0) {
      _snack('Keine verwaisten Dateien gefunden');
      return;
    }
    final confirmed = await _confirm(
      title: 'Verwaiste Dateien löschen',
      body:
          '$orphaned Dateien (${MaintenanceService.formatBytes(_stats!.orphanedBytes)}) '
          'wurden ohne Datenbankeinträge gefunden und werden gelöscht.',
      action: 'Löschen',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cleaning = true);
    final result = await MaintenanceService.cleanOrphanedFiles(
        ref.read(databaseProvider), _storagePath());
    await _reload();
    if (mounted) {
      setState(() => _cleaning = false);
      _snack(
        '${result.deletedFiles} Dateien gelöscht · '
        '${MaintenanceService.formatBytes(result.freedBytes)} freigegeben',
      );
    }
  }

  Future<void> _runVacuum() async {
    setState(() => _vacuuming = true);
    final db = ref.read(databaseProvider);
    final before = _stats?.dbBytes ?? 0;
    await MaintenanceService.vacuumDatabase(db);
    await _reload();
    final after = _stats?.dbBytes ?? 0;
    if (mounted) {
      setState(() => _vacuuming = false);
      _snack('VACUUM abgeschlossen · ${MaintenanceService.formatBytes(before - after)} freigegeben');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen')),
            FilledButton(
                    style: destructive
                        ? FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.error)
                        : null,
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(action),
                  ),
          ],
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Datenbankpflege'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: _reload,
          ),
        ],
      ),
      body: _loadingStats
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _statsSection(cs),
                  const SizedBox(height: 20),
                  _archiveSection(cs),
                  const SizedBox(height: 20),
                  if (_archivedTasks.isNotEmpty) ...[
                    _archivedListSection(cs),
                    const SizedBox(height: 20),
                  ],
                  _compressSection(cs),
                  const SizedBox(height: 20),
                  _cleanupSection(cs),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ── Section builders ──────────────────────────────────────────────────

  Widget _statsSection(ColorScheme cs) {
    final s = _stats!;
    return _Card(
      icon: Icons.storage_outlined,
      title: 'Speichernutzung',
      child: Column(
        children: [
          _StatRow('Datenbank', MaintenanceService.formatBytes(s.dbBytes)),
          _StatRow('Fotos', '${s.photoCount} Dateien · ${MaintenanceService.formatBytes(s.photoBytes)}'),
          _StatRow('Gesamt', MaintenanceService.formatBytes(s.totalBytes), bold: true),
          const Divider(),
          _StatRow('Aktive Tasks', '${s.activeTasks}'),
          _StatRow('Abgeschlossene Tasks', '${s.completedTasks}'),
          _StatRow('Archivierte Tasks', '${s.archivedTasks}'),
          if (s.orphanedFileCount > 0)
            _StatRow(
              'Verwaiste Dateien',
              '${s.orphanedFileCount} · ${MaintenanceService.formatBytes(s.orphanedBytes)}',
              color: cs.error,
            ),
        ],
      ),
    );
  }

  Widget _archiveSection(ColorScheme cs) {
    return _Card(
      icon: Icons.archive_outlined,
      title: 'Tasks archivieren',
      subtitle: 'Abgeschlossene Tasks aus der Hauptliste entfernen. Daten bleiben erhalten.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Älter als $_archiveDays Tage archivieren:',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final days in [14, 30, 60, 90, 180])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(days >= 30
                        ? '${days ~/ 30} Mon.'
                        : '$days T.'),
                    selected: _archiveDays == days,
                    onSelected: (_) async {
                      setState(() => _archiveDays = days);
                      await _updatePreview();
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _archivePreview == 0
                      ? 'Keine passenden Tasks'
                      : '$_archivePreview Tasks werden archiviert',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _archivePreview > 0 ? cs.primary : cs.outline,
                      ),
                ),
              ),
              _archiving
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : FilledButton.icon(
                      onPressed: _archivePreview > 0 ? _runArchive : null,
                      icon: const Icon(Icons.archive, size: 18),
                      label: const Text('Archivieren'),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _archivedListSection(ColorScheme cs) {
    return _Card(
      icon: Icons.inventory_2_outlined,
      title: 'Archiv (${_archivedTasks.length})',
      subtitle: 'Archivierte Tasks ansehen, reaktivieren oder dauerhaft löschen.',
      child: Column(
        children: [
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              _archiveExpanded ? 'Liste ausblenden' : 'Archivierte Tasks anzeigen',
              style: const TextStyle(fontSize: 13),
            ),
            initiallyExpanded: _archiveExpanded,
            onExpansionChanged: (v) => setState(() => _archiveExpanded = v),
            children: _archivedTasks
                .map((t) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: t.archivedAt != null
                          ? Text(
                              'Archiviert ${_formatDate(t.archivedAt!)}',
                              style: const TextStyle(fontSize: 11),
                            )
                          : null,
                      trailing: TextButton(
                        onPressed: () => _unarchive(t),
                        child: const Text('Reaktivieren'),
                      ),
                    ))
                .toList(),
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _clearArchive,
                style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                icon: const Icon(Icons.delete_forever_outlined, size: 18),
                label: const Text('Archiv leeren'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compressSection(ColorScheme cs) {
    return _Card(
      icon: Icons.compress_outlined,
      title: 'Fotos komprimieren',
      subtitle: 'Reduziert die Dateigröße. Originale werden in-place ersetzt.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Qualität: $_compressQuality%',
              style: Theme.of(context).textTheme.bodySmall),
          Slider(
            value: _compressQuality.toDouble(),
            min: 30,
            max: 90,
            divisions: 6,
            label: '$_compressQuality%',
            onChanged: _compressing
                ? null
                : (v) => setState(() => _compressQuality = v.round()),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_stats?.photoCount ?? 0} Fotos · ${MaintenanceService.formatBytes(_stats?.photoBytes ?? 0)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline),
                ),
              ),
              if (_compressing)
                Row(children: [
                  const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('$_compressDone / $_compressTotal',
                      style: const TextStyle(fontSize: 12)),
                ])
              else
                FilledButton.icon(
                  onPressed: (_stats?.photoCount ?? 0) > 0
                      ? _runCompress
                      : null,
                  icon: const Icon(Icons.compress, size: 18),
                  label: const Text('Komprimieren'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cleanupSection(ColorScheme cs) {
    final orphaned = _stats?.orphanedFileCount ?? 0;
    return _Card(
      icon: Icons.cleaning_services_outlined,
      title: 'Aufräumen',
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Verwaiste Dateien löschen'),
            subtitle: Text(orphaned == 0
                ? 'Keine verwaisten Dateien gefunden'
                : '$orphaned Dateien · ${MaintenanceService.formatBytes(_stats!.orphanedBytes)}'),
            trailing: _cleaning
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton(
                    onPressed: orphaned > 0 ? _runCleanup : null,
                    child: const Text('Löschen'),
                  ),
          ),
          const Divider(),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Datenbank komprimieren (VACUUM)'),
            subtitle: Text(
                'Gibt ungenutzten Speicher in der SQLite-Datei frei.\n'
                'Aktuelle DB-Größe: ${MaintenanceService.formatBytes(_stats?.dbBytes ?? 0)}'),
            trailing: _vacuuming
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton(
                    onPressed: _runVacuum,
                    child: const Text('VACUUM'),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _Card({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.bold)),
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline)),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  const _StatRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: bold ? FontWeight.bold : null,
          color: color,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
