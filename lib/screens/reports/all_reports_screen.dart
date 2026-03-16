import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../../services/pdf_service.dart';

class AllReportsScreen extends StatefulWidget {
  const AllReportsScreen({super.key});

  @override
  State<AllReportsScreen> createState() => _AllReportsScreenState();
}

class _AllReportsScreenState extends State<AllReportsScreen> {
  List<File> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    final dir = await getApplicationDocumentsDirectory();
    final files = Directory(dir.path)
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.path.split('/').last;
          return name.endsWith('.pdf') &&
              (name.startsWith('bericht_') ||
               RegExp(r'^\d{4}-\d{2}-\d{2}_').hasMatch(name));
        })
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    if (mounted) setState(() { _reports = files; _loading = false; });
  }

  String _formatDate(File f) {
    final name = f.path.split('/').last.replaceAll('.pdf', '');
    // New format: YYYY-MM-DD_customer_title[_N]
    final newFmt = RegExp(r'^(\d{4}-\d{2}-\d{2})_');
    final match = newFmt.firstMatch(name);
    if (match != null) {
      final dt = DateTime.tryParse(match.group(1)!);
      if (dt != null) return DateFormat('dd.MM.yyyy').format(dt);
    }
    // Legacy format: bericht_<shortId>_<ts>
    final parts = name.split('_');
    if (parts.length >= 3) {
      final ts = int.tryParse(parts.last);
      if (ts != null) {
        return DateFormat('dd.MM.yyyy HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(ts).toLocal());
      }
    }
    return name;
  }

  Future<void> _preview(File file) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PdfPreviewScreen(file: file),
      ),
    );
  }

  Future<void> _delete(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Bericht löschen?'),
        content: const Text('Die PDF-Datei wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed != true) return;
    await file.delete();
    _loadReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alle Berichte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Monatsabschluss',
            onPressed: () => context.push('/reports/monthly'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReports,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.outlineVariant),
                      const SizedBox(height: 16),
                      Text('Noch keine Berichte erstellt',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final f = _reports[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: Text(_formatDate(f)),
                        subtitle: Text(
                          _fileName(f),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline),
                        ),
                        onTap: () => _preview(f),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.share_outlined),
                              tooltip: 'Teilen',
                              onPressed: () => PdfService.shareReport(f),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: Theme.of(context).colorScheme.error),
                              tooltip: 'Löschen',
                              onPressed: () => _delete(f),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _fileName(File f) {
    final name = f.path.split('/').last.replaceAll('.pdf', '');
    // New format: YYYY-MM-DD_customer_title[_N]
    if (RegExp(r'^\d{4}-\d{2}-\d{2}_').hasMatch(name)) {
      final parts = name.split('_');
      if (parts.length >= 3) {
        // parts[0]=date, parts[1]=customer, parts[2..]=title
        return parts.sublist(1).join(' · ');
      }
    }
    // Legacy format: bericht_<shortId>_<ts>.pdf
    final parts = name.split('_');
    if (parts.length >= 2) return 'Task: ${parts[1]}';
    return name;
  }
}

class _PdfPreviewScreen extends StatelessWidget {
  final File file;
  const _PdfPreviewScreen({required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vorschau'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => PdfService.shareReport(file),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => await file.readAsBytes(),
        allowPrinting: true,
        allowSharing: false, // We have our own share button
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }
}
