import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database.dart' hide AppSettings;
import '../providers/tasks_provider.dart';
import '../providers/settings_provider.dart' show AppSettings;
import 'pdf_service.dart';

class ZipExportService {
  /// Erstellt ein ZIP-Archiv mit dem PDF-Bericht + allen Fotos des Tasks
  static Future<void> exportTaskPackage({
    required AppDatabase db,
    required TaskWithDetails detail,
    required AppSettings? settings,
  }) async {
    final taskId = detail.task.id;
    final aeMin = settings?.aeMinutes ?? 10;

    // Daten laden
    final todos =
        await (db.select(db.todos)..where((t) => t.taskId.equals(taskId))).get();
    final hardware =
        await (db.select(db.hardware)..where((h) => h.taskId.equals(taskId))).get();
    final notes =
        await (db.select(db.notes)..where((n) => n.taskId.equals(taskId))).get();
    final photos =
        await (db.select(db.photos)..where((p) => p.taskId.equals(taskId))).get();

    // Logo laden
    Uint8List? logoBytes;
    if (settings?.logoPath != null) {
      final logoFile = File(settings!.logoPath!);
      if (await logoFile.exists()) logoBytes = await logoFile.readAsBytes();
    }

    // PDF generieren
    final pdfFile = await PdfService.generateReport(PdfReportData(
      taskDetail: detail,
      todos: todos,
      hardware: hardware,
      notes: notes,
      companyName: settings?.companyName ?? 'IT-Firma',
      technicianName: settings?.technicianName ?? '',
      aeMinutes: aeMin.toDouble(),
      logoBytes: logoBytes,
    ));

    // ZIP erstellen
    final encoder = ZipFileEncoder();
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final shortId = taskId.replaceAll('-', '').substring(0, 8);
    final zipPath = '${dir.path}/paket_${shortId}_$ts.zip';

    encoder.create(zipPath);
    encoder.addFile(pdfFile, 'bericht.pdf');

    int photoIndex = 1;
    for (final photo in photos) {
      final file = File(photo.filePath);
      if (await file.exists()) {
        final ext = photo.filePath.split('.').last.toLowerCase();
        encoder.addFile(file, 'fotos/foto_${photoIndex.toString().padLeft(3, '0')}.$ext');
        photoIndex++;
      }
    }
    encoder.close();

    // Teilen
    final zipFile = File(zipPath);
    await Share.shareXFiles(
      [XFile(zipFile.path)],
      subject: 'Übergabepaket: ${detail.task.title}',
      text: 'Übergabepaket für Task: ${detail.task.title}',
    );
  }
}
