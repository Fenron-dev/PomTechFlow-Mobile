import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../db/database.dart';
import 'package:drift/drift.dart' as drift;

class DataExchangeService {
  /// Exportiert ausgewählte Datenkategorien als JSON-Datei und teilt sie.
  static Future<void> exportData(
    AppDatabase db, {
    bool customers = true,
    bool workflows = true,
    bool hardwareBundles = true,
  }) async {
    final Map<String, dynamic> data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'type': 'data_exchange',
    };

    if (customers) {
      final rows = await db.select(db.customers).get();
      data['customers'] = rows
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'email': c.email,
                'phone': c.phone,
                'address': c.address,
                'notes': c.notes,
              })
          .toList();
    }

    if (workflows) {
      final wfs = await db.select(db.workflows).get();
      final wfList = [];
      for (final wf in wfs) {
        final items = await (db.select(db.workflowItems)
              ..where((i) => i.workflowId.equals(wf.id))
              ..orderBy([(i) => drift.OrderingTerm.asc(i.sortOrder)]))
            .get();
        wfList.add({
          'id': wf.id,
          'name': wf.name,
          'description': wf.description,
          'items': items.map((i) => {'id': i.id, 'itemText': i.itemText, 'sortOrder': i.sortOrder}).toList(),
        });
      }
      data['workflows'] = wfList;
    }

    if (hardwareBundles) {
      final bundles = await db.select(db.hardwareBundles).get();
      final bundleList = [];
      for (final b in bundles) {
        final items = await (db.select(db.hardwareBundleItems)
              ..where((i) => i.bundleId.equals(b.id))
              ..orderBy([(i) => drift.OrderingTerm.asc(i.sortOrder)]))
            .get();
        bundleList.add({
          'id': b.id,
          'name': b.name,
          'description': b.description,
          'items': items
              .map((i) => {
                    'type': i.type,
                    'name': i.name,
                    'serial': i.serial,
                    'notes': i.notes,
                    'sortOrder': i.sortOrder,
                  })
              .toList(),
        });
      }
      data['hardwareBundles'] = bundleList;
    }

    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/ptf_data_$ts.json');
    await file.writeAsString(json);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'PomTechFlow Daten',
      text: 'PomTechFlow Stammdaten-Export',
    );
  }

  /// Importiert Daten aus einer JSON-Datei. Bereits vorhandene Einträge (gleiche ID) werden übersprungen.
  static Future<DataImportResult> importData(AppDatabase db) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) {
      return DataImportResult.cancelled();
    }

    final path = result.files.first.path;
    if (path == null) return DataImportResult.cancelled();

    try {
      final content = await File(path).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      if (data['type'] != 'data_exchange') {
        return DataImportResult.error('Keine gültige Datenaustausch-Datei.');
      }

      int importedCustomers = 0;
      int importedWorkflows = 0;
      int importedBundles = 0;

      await db.transaction(() async {
        // Kunden
        final customerList = data['customers'] as List? ?? [];
        for (final c in customerList) {
          final existing = await (db.select(db.customers)
                ..where((row) => row.id.equals(c['id'] as String)))
              .getSingleOrNull();
          if (existing == null) {
            await db.into(db.customers).insert(CustomersCompanion.insert(
                  id: drift.Value(c['id'] as String),
                  name: c['name'] as String,
                  email: drift.Value(c['email'] as String?),
                  phone: drift.Value(c['phone'] as String?),
                  address: drift.Value(c['address'] as String?),
                  notes: drift.Value(c['notes'] as String?),
                ));
            importedCustomers++;
          }
        }

        // Workflows
        final workflowList = data['workflows'] as List? ?? [];
        for (final wf in workflowList) {
          final existing = await (db.select(db.workflows)
                ..where((row) => row.id.equals(wf['id'] as String)))
              .getSingleOrNull();
          if (existing == null) {
            await db.into(db.workflows).insert(WorkflowsCompanion.insert(
                  id: drift.Value(wf['id'] as String),
                  name: wf['name'] as String,
                  description: drift.Value(wf['description'] as String?),
                ));
            for (final item in (wf['items'] as List? ?? [])) {
              await db.into(db.workflowItems).insert(
                    WorkflowItemsCompanion.insert(
                      id: drift.Value(item['id'] as String),
                      workflowId: wf['id'] as String,
                      itemText: item['itemText'] as String,
                      sortOrder: drift.Value(item['sortOrder'] as int? ?? 0),
                    ),
                  );
            }
            importedWorkflows++;
          }
        }

        // Hardware Bundles
        final bundleList = data['hardwareBundles'] as List? ?? [];
        for (final b in bundleList) {
          final existing = await (db.select(db.hardwareBundles)
                ..where((row) => row.id.equals(b['id'] as String)))
              .getSingleOrNull();
          if (existing == null) {
            await db.into(db.hardwareBundles).insert(
                  HardwareBundlesCompanion.insert(
                    id: drift.Value(b['id'] as String),
                    name: b['name'] as String,
                    description: drift.Value(b['description'] as String?),
                  ),
                );
            int sortIdx = 0;
            for (final item in (b['items'] as List? ?? [])) {
              await db.into(db.hardwareBundleItems).insert(
                    HardwareBundleItemsCompanion.insert(
                      bundleId: b['id'] as String,
                      type: item['type'] as String,
                      name: drift.Value(item['name'] as String?),
                      serial: drift.Value(item['serial'] as String?),
                      notes: drift.Value(item['notes'] as String?),
                      sortOrder: drift.Value(sortIdx++),
                    ),
                  );
            }
            importedBundles++;
          }
        }
      });

      return DataImportResult.success(
        customers: importedCustomers,
        workflows: importedWorkflows,
        bundles: importedBundles,
      );
    } catch (e) {
      return DataImportResult.error('Fehler beim Importieren: $e');
    }
  }
}

class DataImportResult {
  final bool cancelled;
  final String? error;
  final int customers;
  final int workflows;
  final int bundles;

  DataImportResult._({
    this.cancelled = false,
    this.error,
    this.customers = 0,
    this.workflows = 0,
    this.bundles = 0,
  });

  factory DataImportResult.cancelled() => DataImportResult._(cancelled: true);
  factory DataImportResult.error(String msg) => DataImportResult._(error: msg);
  factory DataImportResult.success({
    required int customers,
    required int workflows,
    required int bundles,
  }) =>
      DataImportResult._(
          customers: customers, workflows: workflows, bundles: bundles);

  bool get isSuccess => !cancelled && error == null;

  String get summary =>
      '$customers Kunden, $workflows Workflows, $bundles Bundles importiert';
}
