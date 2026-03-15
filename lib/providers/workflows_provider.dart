import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'database_provider.dart';
import '../db/database.dart';

class WorkflowWithDetails {
  final Workflow workflow;
  final List<WorkflowItem> items; // generated row class from WorkflowItems table
  final List<Customer> customers;

  const WorkflowWithDetails({
    required this.workflow,
    required this.items,
    required this.customers,
  });
}

final workflowsProvider =
    FutureProvider<List<WorkflowWithDetails>>((ref) async {
  final db = ref.watch(databaseProvider);
  final workflows = await (db.select(db.workflows)
        ..orderBy([(w) => drift.OrderingTerm.asc(w.name)]))
      .get();

  final result = <WorkflowWithDetails>[];
  for (final wf in workflows) {
    final items = await (db.select(db.workflowItems)
          ..where((i) => i.workflowId.equals(wf.id))
          ..orderBy([(i) => drift.OrderingTerm.asc(i.sortOrder)]))
        .get(); // returns List<WorkflowItem>

    final wcs = await (db.select(db.workflowCustomers)
          ..where((wc) => wc.workflowId.equals(wf.id)))
        .get();

    final customers = <Customer>[];
    for (final wc in wcs) {
      final c = await (db.select(db.customers)
            ..where((cu) => cu.id.equals(wc.customerId)))
          .getSingleOrNull();
      if (c != null) customers.add(c);
    }

    result.add(WorkflowWithDetails(
      workflow: wf,
      items: items,
      customers: customers,
    ));
  }
  return result;
});
