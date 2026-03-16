import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'database_provider.dart';
import '../db/database.dart';

class TemplateWithDetails {
  final TaskTemplate template;
  final Customer? customer;
  final Workflow? workflow;
  final HardwareBundle? bundle;

  const TemplateWithDetails({
    required this.template,
    this.customer,
    this.workflow,
    this.bundle,
  });
}

final taskTemplatesProvider =
    FutureProvider<List<TemplateWithDetails>>((ref) async {
  final db = ref.watch(databaseProvider);
  final templates = await (db.select(db.taskTemplates)
        ..orderBy([(t) => OrderingTerm.asc(t.title)]))
      .get();

  final result = <TemplateWithDetails>[];
  for (final tpl in templates) {
    Customer? customer;
    Workflow? workflow;
    HardwareBundle? bundle;

    if (tpl.customerId != null) {
      customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(tpl.customerId!)))
          .getSingleOrNull();
    }
    if (tpl.workflowId != null) {
      workflow = await (db.select(db.workflows)
            ..where((w) => w.id.equals(tpl.workflowId!)))
          .getSingleOrNull();
    }
    if (tpl.hardwareBundleId != null) {
      bundle = await (db.select(db.hardwareBundles)
            ..where((b) => b.id.equals(tpl.hardwareBundleId!)))
          .getSingleOrNull();
    }

    result.add(TemplateWithDetails(
      template: tpl,
      customer: customer,
      workflow: workflow,
      bundle: bundle,
    ));
  }
  return result;
});
