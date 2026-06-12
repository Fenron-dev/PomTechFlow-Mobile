import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show Printing;
import '../db/database.dart';
import '../providers/tasks_provider.dart';

const _hwLabels = {
  'PC': 'PC', 'LAPTOP': 'Laptop', 'MAC': 'Mac', 'MACBOOK': 'MacBook',
  'MONITOR': 'Monitor', 'PRINTER': 'Drucker', 'ROUTER': 'Router',
  'SWITCH': 'Switch', 'SERVER': 'Server', 'PHONE': 'Telefon',
  'TABLET': 'Tablet', 'OTHER': 'Sonstiges',
};

class PdfReportData {
  final TaskWithDetails taskDetail;
  final List<Todo> todos;
  final List<HardwareData> hardware;
  final List<Note> notes;
  final String companyName;
  final String technicianName;
  final double aeMinutes;
  /// Raw bytes of the company logo (PNG/JPG). Null = no logo.
  final Uint8List? logoBytes;

  const PdfReportData({
    required this.taskDetail,
    required this.todos,
    required this.hardware,
    required this.notes,
    required this.companyName,
    required this.technicianName,
    required this.aeMinutes,
    this.logoBytes,
  });
}

// ─── Isolate-sendable input types ─────────────────────────────────────────────

typedef _TodoIn = ({String content, bool completed, String? workflowName});
typedef _HwIn   = ({String type, String? name, String? serial});
typedef _NoteIn = ({String content, String createdAtStr});
typedef _TaskIn = ({
  String title,
  String? description,
  String status,
  String? customerName,
  int totalMinutes,
  double ae,
});

class _PdfReportInput {
  final _TaskIn task;
  final List<_TodoIn> todos;
  final List<_HwIn> hardware;
  final List<_NoteIn> notes;
  final String companyName;
  final String technicianName;
  final Uint8List? logoBytes;
  final Uint8List fontBytes;
  final Uint8List fontBoldBytes;
  final String dateStr;

  const _PdfReportInput({
    required this.task,
    required this.todos,
    required this.hardware,
    required this.notes,
    required this.companyName,
    required this.technicianName,
    required this.logoBytes,
    required this.fontBytes,
    required this.fontBoldBytes,
    required this.dateStr,
  });
}

typedef _MonthlyTaskIn = ({
  String title,
  String? customerName,
  String status,
  int totalMinutes,
  double ae,
});

class _PdfMonthlyInput {
  final List<_MonthlyTaskIn> tasks;
  final int totalMinutes;
  final double totalAe;
  final String? customerName;
  final String monthLabel;
  final String companyName;
  final String technicianName;
  final Uint8List? logoBytes;
  final Uint8List fontBytes;
  final Uint8List fontBoldBytes;
  final String dateStr;

  const _PdfMonthlyInput({
    required this.tasks,
    required this.totalMinutes,
    required this.totalAe,
    required this.customerName,
    required this.monthLabel,
    required this.companyName,
    required this.technicianName,
    required this.logoBytes,
    required this.fontBytes,
    required this.fontBoldBytes,
    required this.dateStr,
  });
}

// ─── PDF Service ──────────────────────────────────────────────────────────────

class PdfService {
  static Future<File> generateReport(PdfReportData data,
      {String storageBasePath = ''}) async {
    final task = data.taskDetail.task;
    final ae = task.totalMinutes == 0
        ? 0.0
        : (task.totalMinutes / data.aeMinutes).ceilToDouble();

    // Fonts auf Main-Thread laden (rootBundle nicht in Isolates verfügbar)
    final fontBytes = await _loadFontBytes('packages/printing/fonts/Nunito-Regular.ttf');
    final fontBoldBytes = await _loadFontBytes('packages/printing/fonts/Nunito-Bold.ttf');

    final input = _PdfReportInput(
      task: (
        title: task.title,
        description: task.description,
        status: task.status,
        customerName: data.taskDetail.customer?.name,
        totalMinutes: task.totalMinutes,
        ae: ae,
      ),
      todos: data.todos
          .map((t) => (content: t.content, completed: t.completed, workflowName: t.workflowName))
          .toList(),
      hardware: data.hardware
          .map((h) => (type: h.type, name: h.name, serial: h.serial))
          .toList(),
      notes: data.notes
          .map((n) => (
                content: n.content,
                createdAtStr: DateFormat('dd.MM.yyyy HH:mm').format(n.createdAt.toLocal()),
              ))
          .toList(),
      companyName: data.companyName,
      technicianName: data.technicianName,
      logoBytes: data.logoBytes,
      fontBytes: fontBytes,
      fontBoldBytes: fontBoldBytes,
      dateStr: DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now().toLocal()),
    );

    // Schwere PDF-Arbeit im Hintergrund-Isolate
    final pdfBytes = await Isolate.run(() => _buildReportBytes(input));

    final dir = storageBasePath.isNotEmpty
        ? Directory(storageBasePath)
        : await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    final fileDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final customerSlug = _slug(data.taskDetail.customer?.name ?? 'kein-kunde');
    final titleSlug = _slug(task.title);
    final baseName = '${fileDateStr}_${customerSlug}_$titleSlug';
    final fileName = await _uniqueFilename(dir.path, baseName, 'pdf');
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(pdfBytes);
    return file;
  }

  static Future<File> generateMonthlyReport({
    required List<TaskWithDetails> tasks,
    required Customer? customer,
    String storageBasePath = '',
    required DateTime month,
    required String companyName,
    required String technicianName,
    required double aeMinutes,
    Uint8List? logoBytes,
  }) async {
    final fontBytes = await _loadFontBytes('packages/printing/fonts/Nunito-Regular.ttf');
    final fontBoldBytes = await _loadFontBytes('packages/printing/fonts/Nunito-Bold.ttf');

    final totalMinutes = tasks.fold<int>(0, (s, t) => s + t.task.totalMinutes);
    final totalAe = tasks.fold<double>(
        0,
        (s, t) => s +
            (t.task.totalMinutes == 0
                ? 0
                : (t.task.totalMinutes / aeMinutes).ceilToDouble()));

    final input = _PdfMonthlyInput(
      tasks: tasks
          .map((t) => (
                title: t.task.title,
                customerName: t.customer?.name,
                status: t.task.status,
                totalMinutes: t.task.totalMinutes,
                ae: t.task.totalMinutes == 0
                    ? 0.0
                    : (t.task.totalMinutes / aeMinutes).ceilToDouble(),
              ))
          .toList(),
      totalMinutes: totalMinutes,
      totalAe: totalAe,
      customerName: customer?.name,
      monthLabel: DateFormat('MMMM yyyy', 'de_DE').format(month),
      companyName: companyName,
      technicianName: technicianName,
      logoBytes: logoBytes,
      fontBytes: fontBytes,
      fontBoldBytes: fontBoldBytes,
      dateStr: DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now().toLocal()),
    );

    final pdfBytes = await Isolate.run(() => _buildMonthlyBytes(input));

    final dir = storageBasePath.isNotEmpty
        ? Directory(storageBasePath)
        : await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    final monthStr = DateFormat('yyyy-MM').format(month);
    final customerSlug = _slug(customer?.name ?? 'alle-kunden');
    final baseName = '${monthStr}_monatsabschluss_$customerSlug';
    final fileName = await _uniqueFilename(dir.path, baseName, 'pdf');
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(pdfBytes);
    return file;
  }

  // ─── Isolate-Funktionen (kein rootBundle, kein Platform-Channel) ────────────

  static Future<Uint8List> _buildReportBytes(_PdfReportInput input) async {
    final font = pw.Font.ttf(ByteData.sublistView(input.fontBytes));
    final fontBold = pw.Font.ttf(ByteData.sublistView(input.fontBoldBytes));

    final doneTodos = input.todos.where((t) => t.completed).toList();
    final openTodos = input.todos.where((t) => !t.completed).toList();

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        ),
        header: (ctx) => _buildHeader(
          input.companyName,
          input.technicianName,
          input.dateStr,
          font,
          fontBold,
          logoBytes: input.logoBytes,
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(input.companyName,
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
        build: (ctx) => [
          _buildTaskSection(input.task, font, fontBold),
          pw.SizedBox(height: 16),
          _sectionTitle('Zeitübersicht', fontBold),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
            },
            children: [
              _tableHeaderRow(['Zeitaufwand', 'Minuten', 'AE'], fontBold),
              _tableRow(
                  ['Gesamt', '${input.task.totalMinutes} Min', input.task.ae.toStringAsFixed(2)],
                  font),
            ],
          ),
          pw.SizedBox(height: 16),
          if (input.todos.isNotEmpty) ...[
            _sectionTitle('Checkliste', fontBold),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Erledigt (${doneTodos.length})',
                          style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.green700)),
                      ...doneTodos.map((t) => _checkItem(t.content, true, font)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Offen (${openTodos.length})',
                          style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.orange700)),
                      ...openTodos.map((t) => _checkItem(t.content, false, font)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
          ],
          if (input.hardware.isNotEmpty) ...[
            _sectionTitle('Hardware', fontBold),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
              },
              children: [
                _tableHeaderRow(['Typ', 'Bezeichnung', 'Seriennummer'], fontBold),
                ...input.hardware.map((h) => _tableRow([
                      _hwLabels[h.type] ?? h.type,
                      h.name ?? '-',
                      h.serial ?? '-',
                    ], font)),
              ],
            ),
            pw.SizedBox(height: 16),
          ],
          if (input.notes.isNotEmpty) ...[
            _sectionTitle('Notizen', fontBold),
            ...input.notes.map((n) => pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 6),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(n.content,
                          style: pw.TextStyle(font: font, fontSize: 9)),
                      pw.SizedBox(height: 3),
                      pw.Text(n.createdAtStr,
                          style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600)),
                    ],
                  ),
                )),
          ],
          pw.SizedBox(height: 32),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureLine('Datum / Techniker', 180, font),
              _signatureLine('Datum / Kunde', 180, font),
            ],
          ),
        ],
      ),
    );
    return await pdf.save();
  }

  static Future<Uint8List> _buildMonthlyBytes(_PdfMonthlyInput input) async {
    final font = pw.Font.ttf(ByteData.sublistView(input.fontBytes));
    final fontBold = pw.Font.ttf(ByteData.sublistView(input.fontBoldBytes));

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        ),
        header: (ctx) {
          final headerWidget = _buildHeader(
            input.companyName, input.technicianName, input.dateStr, font, fontBold,
            logoBytes: input.logoBytes,
          );
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              headerWidget,
              pw.SizedBox(height: 8),
              pw.Text(
                'Monatsabschluss: ${input.monthLabel}'
                '${input.customerName != null ? ' – ${input.customerName}' : ' – Alle Kunden'}',
                style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.blue800),
              ),
            ],
          );
        },
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(input.companyName,
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
        build: (ctx) => [
          pw.SizedBox(height: 16),
          _sectionTitle('Aufgaben (${input.monthLabel})', fontBold),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1.2),
            },
            children: [
              _tableHeaderRow(['Titel', 'Kunde', 'Status', 'Min', 'AE'], fontBold),
              ...input.tasks.map((t) => _tableRow([
                    t.title,
                    t.customerName ?? '-',
                    _statusLabel(t.status),
                    '${t.totalMinutes}',
                    t.ae.toStringAsFixed(0),
                  ], font)),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('Gesamt', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('${input.tasks.length} Tasks',
                        style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('', style: pw.TextStyle(font: font, fontSize: 9)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('${input.totalMinutes}',
                        style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(input.totalAe.toStringAsFixed(0),
                        style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.blue800)),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 32),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureLine('Datum / Techniker', 180, font),
              _signatureLine('Datum / Bestätigung', 180, font),
            ],
          ),
        ],
      ),
    );
    return await pdf.save();
  }

  // ─── Widget-Helpers (laufen im Isolate, kein State) ───────────────────────

  static pw.Widget _buildHeader(
    String company,
    String technician,
    String date,
    pw.Font font,
    pw.Font fontBold, {
    Uint8List? logoBytes,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoBytes != null) ...[
                pw.Image(pw.MemoryImage(logoBytes), height: 36, fit: pw.BoxFit.contain),
                pw.SizedBox(width: 10),
              ],
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(company,
                      style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.blue800)),
                  pw.Text('IT-Support Bericht',
                      style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(date, style: pw.TextStyle(font: font, fontSize: 9)),
              if (technician.isNotEmpty)
                pw.Text(technician,
                    style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTaskSection(_TaskIn task, pw.Font font, pw.Font fontBold) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(task.title, style: pw.TextStyle(font: fontBold, fontSize: 14)),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              if (task.customerName != null) ...[
                pw.Text('Kunde: ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                pw.Text(task.customerName!, style: pw.TextStyle(font: font, fontSize: 10)),
                pw.SizedBox(width: 20),
              ],
              pw.Text('Status: ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
              pw.Text(_statusLabel(task.status), style: pw.TextStyle(font: font, fontSize: 10)),
            ],
          ),
          if (task.description != null && task.description!.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(task.description!,
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
          ],
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String title, pw.Font fontBold) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blue800, width: 1.5)),
      ),
      child: pw.Text(title,
          style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.blue800)),
    );
  }

  static pw.TableRow _tableHeaderRow(List<String> cells, pw.Font fontBold) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: cells
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(c, style: pw.TextStyle(font: fontBold, fontSize: 9)),
              ))
          .toList(),
    );
  }

  static pw.TableRow _tableRow(List<String> cells, pw.Font font) {
    return pw.TableRow(
      children: cells
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(c, style: pw.TextStyle(font: font, fontSize: 9)),
              ))
          .toList(),
    );
  }

  static pw.Widget _checkItem(String text, bool done, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(done ? '✓ ' : '○ ',
              style: pw.TextStyle(
                  font: font,
                  fontSize: 9,
                  color: done ? PdfColors.green700 : PdfColors.orange700)),
          pw.Expanded(
            child: pw.Text(text,
                style: pw.TextStyle(
                    font: font, fontSize: 9, color: done ? PdfColors.grey600 : PdfColors.black)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureLine(String label, double width, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(width: width, height: 1, color: PdfColors.grey400),
        pw.SizedBox(height: 4),
        pw.Text(label,
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
      ],
    );
  }

  // ─── Hilfsfunktionen ──────────────────────────────────────────────────────

  /// Lädt Font-Bytes via rootBundle (nur auf dem Main-Thread nutzbar).
  /// Fallback auf PdfGoogleFonts falls der Asset-Pfad nicht gefunden wird.
  static Future<Uint8List> _loadFontBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static String _slug(String input) {
    var s = input
        .toLowerCase()
        .replaceAll(RegExp(r'[äÄ]'), 'ae')
        .replaceAll(RegExp(r'[öÖ]'), 'oe')
        .replaceAll(RegExp(r'[üÜ]'), 'ue')
        .replaceAll(RegExp(r'[ß]'), 'ss')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (s.length > 30) s = s.substring(0, 30).replaceAll(RegExp(r'-$'), '');
    return s.isEmpty ? 'unbekannt' : s;
  }

  static Future<String> _uniqueFilename(String dirPath, String base, String ext) async {
    var name = '$base.$ext';
    if (!await File('$dirPath/$name').exists()) return name;
    for (var i = 2; i <= 99; i++) {
      name = '${base}_$i.$ext';
      if (!await File('$dirPath/$name').exists()) return name;
    }
    return '${base}_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  static String _statusLabel(String s) => switch (s) {
        'ACTIVE' => 'Aktiv',
        'COMPLETED' => 'Abgeschlossen',
        'PAUSED' => 'Pausiert',
        _ => 'Geplant',
      };

  // PDF drucken / teilen
  static Future<void> shareReport(File file) async {
    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: file.path.split('/').last,
    );
  }

  /// Lists all previously generated PDF reports (legacy + new naming scheme).
  static Future<List<File>> listReports(String taskId, {String? taskTitle}) async {
    final dir = await getApplicationDocumentsDirectory();
    final legacyPrefix = 'bericht_${taskId.substring(0, taskId.length.clamp(0, 8))}_';
    final titleSlug = taskTitle != null ? _slug(taskTitle) : null;
    final docDir = Directory(dir.path);
    if (!await docDir.exists()) return [];
    return docDir
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.uri.pathSegments.last;
          if (!name.endsWith('.pdf')) return false;
          if (name.startsWith(legacyPrefix)) return true;
          if (RegExp(r'^\d{4}-\d{2}-\d{2}_').hasMatch(name)) {
            if (name.contains('_monatsabschluss_')) return false;
            if (titleSlug != null && !name.contains('_$titleSlug')) return false;
            return true;
          }
          return false;
        })
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  }
}
