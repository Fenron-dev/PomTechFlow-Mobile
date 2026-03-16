import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database.dart';
import '../providers/tasks_provider.dart';

class CsvService {
  /// Exportiert alle Tasks mit Zeitdaten als CSV
  static Future<void> exportTasks({
    required AppDatabase db,
    required List<TaskWithDetails> tasks,
    required int aeMinutes,
    DateTime? from,
    DateTime? to,
  }) async {
    final fmt = DateFormat('dd.MM.yyyy');
    final fmtFull = DateFormat('dd.MM.yyyy HH:mm');

    // Optional filtern
    var filtered = tasks;
    if (from != null) {
      filtered = filtered.where((t) => t.task.createdAt.isAfter(from)).toList();
    }
    if (to != null) {
      filtered = filtered
          .where((t) => t.task.createdAt
              .isBefore(to.add(const Duration(days: 1))))
          .toList();
    }

    final lines = <String>[];
    // Kopfzeile
    lines.add(_csvRow([
      'Datum',
      'Kunde',
      'Titel',
      'Status',
      'Minuten',
      'AE',
      'Sessions',
      'Erstellt',
      'Abgeschlossen',
    ]));

    for (final t in filtered) {
      final ae = t.aeCount(aeMinutes);
      final status = switch (t.task.status) {
        'COMPLETED' => 'Abgeschlossen',
        'ACTIVE' => 'Aktiv',
        'PAUSED' => 'Pausiert',
        _ => 'Geplant',
      };
      final abgeschlossen = t.task.status == 'COMPLETED'
          ? fmtFull.format(t.task.updatedAt.toLocal())
          : '';

      lines.add(_csvRow([
        fmt.format(t.task.createdAt.toLocal()),
        t.customer?.name ?? '',
        t.task.title,
        status,
        t.task.totalMinutes.toString(),
        ae.toString(),
        t.sessionCount.toString(),
        fmtFull.format(t.task.createdAt.toLocal()),
        abgeschlossen,
      ]));
    }

    // Datei schreiben
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/zeiterfassung_$ts.csv');
    // UTF-8 BOM für Excel-Kompatibilität
    await file.writeAsBytes([0xEF, 0xBB, 0xBF]);
    await file.writeAsString(lines.join('\n'), mode: FileMode.append);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Zeiterfassung Export',
      text:
          'Zeiterfassung – ${filtered.length} Tasks, ${DateFormat('MM/yyyy').format(DateTime.now())}',
    );
  }

  static String _csvRow(List<String> fields) {
    return fields.map((f) {
      // Semikolon-getrennt, Felder mit Anführungszeichen wenn nötig
      final escaped = f.replaceAll('"', '""');
      return '"$escaped"';
    }).join(';');
  }
}
