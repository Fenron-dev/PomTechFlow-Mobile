import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../db/database.dart';
import '../providers/tasks_provider.dart';

const _hwLabels = {
  'PC': 'PC', 'LAPTOP': 'Laptop', 'MONITOR': 'Monitor',
  'PRINTER': 'Drucker', 'ROUTER': 'Router', 'SWITCH': 'Switch',
  'SERVER': 'Server', 'PHONE': 'Telefon', 'TABLET': 'Tablet',
  'OTHER': 'Sonstiges',
};

class PdfReportData {
  final TaskWithDetails taskDetail;
  final List<Todo> todos;
  final List<HardwareData> hardware;
  final List<Note> notes;
  final String companyName;
  final String technicianName;
  final double aeMinutes;

  const PdfReportData({
    required this.taskDetail,
    required this.todos,
    required this.hardware,
    required this.notes,
    required this.companyName,
    required this.technicianName,
    required this.aeMinutes,
  });
}

class PdfService {
  static Future<File> generateReport(PdfReportData data) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.nunitoRegular();
    final fontBold = await PdfGoogleFonts.nunitoBold();

    final task = data.taskDetail.task;
    final ae = task.totalMinutes == 0 ? 0.0 : (task.totalMinutes / data.aeMinutes).ceilToDouble();
    final dateStr =
        DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now().toLocal());

    final doneTodos = data.todos.where((t) => t.completed).toList();
    final openTodos = data.todos.where((t) => !t.completed).toList();

    // Gruppierung nach Workflow
    final grouped = <String, List<Todo>>{};
    for (final todo in data.todos) {
      final key = todo.workflowName ?? '';
      grouped.putIfAbsent(key, () => []).add(todo);
    }

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        ),
        header: (ctx) => _buildHeader(
          data.companyName,
          data.technicianName,
          dateStr,
          font,
          fontBold,
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(data.companyName,
                style: pw.TextStyle(font: font, fontSize: 8,
                    color: PdfColors.grey600)),
            pw.Text('Seite ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(font: font, fontSize: 8,
                    color: PdfColors.grey600)),
          ],
        ),
        build: (ctx) => [
          _buildTaskSection(task, data.taskDetail.customer, ae, font, fontBold),
          pw.SizedBox(height: 16),

          // Zeitübersicht
          _sectionTitle('Zeitübersicht', fontBold),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
            },
            children: [
              _tableHeaderRow(['Zeitaufwand', 'Minuten', 'AE'], fontBold),
              _tableRow(['Gesamt', '${task.totalMinutes} Min',
                  ae.toStringAsFixed(2)], font),
            ],
          ),
          pw.SizedBox(height: 16),

          // Checkliste
          if (data.todos.isNotEmpty) ...[
            _sectionTitle('Checkliste', fontBold),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Erledigt
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Erledigt (${doneTodos.length})',
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 9,
                              color: PdfColors.green700)),
                      ...doneTodos.map((t) => _checkItem(t.content, true, font)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                // Offen
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Offen (${openTodos.length})',
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 9,
                              color: PdfColors.orange700)),
                      ...openTodos.map((t) => _checkItem(t.content, false, font)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
          ],

          // Hardware
          if (data.hardware.isNotEmpty) ...[
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
                ...data.hardware.map((h) => _tableRow([
                  _hwLabels[h.type] ?? h.type,
                  h.name ?? '-',
                  h.serial ?? '-',
                ], font)),
              ],
            ),
            pw.SizedBox(height: 16),
          ],

          // Notizen
          if (data.notes.isNotEmpty) ...[
            _sectionTitle('Notizen', fontBold),
            ...data.notes.map((n) => pw.Container(
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
                  pw.Text(
                    DateFormat('dd.MM.yyyy HH:mm').format(n.createdAt.toLocal()),
                    style: pw.TextStyle(
                        font: font, fontSize: 7, color: PdfColors.grey600),
                  ),
                ],
              ),
            )),
          ],

          // Unterschriftsfeld
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

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'bericht_${task.id.substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _buildHeader(
    String company,
    String technician,
    String date,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(company,
                  style: pw.TextStyle(
                      font: fontBold, fontSize: 16, color: PdfColors.blue800)),
              pw.Text('IT-Support Bericht',
                  style: pw.TextStyle(
                      font: font, fontSize: 10, color: PdfColors.grey600)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(date,
                  style: pw.TextStyle(font: font, fontSize: 9)),
              if (technician.isNotEmpty)
                pw.Text(technician,
                    style: pw.TextStyle(font: font, fontSize: 9,
                        color: PdfColors.grey600)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTaskSection(
    Task task,
    Customer? customer,
    double ae,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(task.title,
              style: pw.TextStyle(font: fontBold, fontSize: 14)),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              if (customer != null) ...[
                pw.Text('Kunde: ',
                    style: pw.TextStyle(font: fontBold, fontSize: 10)),
                pw.Text(customer.name,
                    style: pw.TextStyle(font: font, fontSize: 10)),
                pw.SizedBox(width: 20),
              ],
              pw.Text('Status: ',
                  style: pw.TextStyle(font: fontBold, fontSize: 10)),
              pw.Text(_statusLabel(task.status),
                  style: pw.TextStyle(font: font, fontSize: 10)),
            ],
          ),
          if (task.description != null && task.description!.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(task.description!,
                style: pw.TextStyle(
                    font: font, fontSize: 9, color: PdfColors.grey700)),
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
        border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.blue800, width: 1.5)),
      ),
      child: pw.Text(title,
          style: pw.TextStyle(font: fontBold, fontSize: 11,
              color: PdfColors.blue800)),
    );
  }

  static pw.TableRow _tableHeaderRow(List<String> cells, pw.Font fontBold) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: cells
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(c,
                    style: pw.TextStyle(font: fontBold, fontSize: 9)),
              ))
          .toList(),
    );
  }

  static pw.TableRow _tableRow(List<String> cells, pw.Font font) {
    return pw.TableRow(
      children: cells
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(c,
                    style: pw.TextStyle(font: font, fontSize: 9)),
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
                    font: font,
                    fontSize: 9,
                    color:
                        done ? PdfColors.grey600 : PdfColors.black)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureLine(String label, double width, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: width,
          height: 1,
          color: PdfColors.grey400,
        ),
        pw.SizedBox(height: 4),
        pw.Text(label,
            style: pw.TextStyle(
                font: font, fontSize: 8, color: PdfColors.grey600)),
      ],
    );
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
}
