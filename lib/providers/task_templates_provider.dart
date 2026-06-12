import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'database_provider.dart';
import '../db/database.dart';

class TemplateWithDetails {
  final TaskTemplate template;
  final Customer? customer;
  /// Workflows linked via TaskTemplateWorkflows join table.
  final List<Workflow> workflows;
  /// Custom extra todo items stored in TaskTemplateTodos.
  final List<TaskTemplateTodo> customTodos;
  final HardwareBundle? bundle;

  const TemplateWithDetails({
    required this.template,
    this.customer,
    required this.workflows,
    required this.customTodos,
    this.bundle,
  });

  /// Legacy single workflow (for backward compat with old data that used workflowId).
  Workflow? get workflow => workflows.isNotEmpty ? workflows.first : null;
}

final taskTemplatesProvider =
    FutureProvider<List<TemplateWithDetails>>((ref) async {
  final db = ref.watch(databaseProvider);
  final templates = await (db.select(db.taskTemplates)
        ..orderBy([(t) => drift.OrderingTerm.asc(t.title)]))
      .get();

  final result = <TemplateWithDetails>[];
  for (final tpl in templates) {
    Customer? customer;
    HardwareBundle? bundle;

    if (tpl.customerId != null) {
      customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(tpl.customerId!)))
          .getSingleOrNull();
    }
    if (tpl.hardwareBundleId != null) {
      bundle = await (db.select(db.hardwareBundles)
            ..where((b) => b.id.equals(tpl.hardwareBundleId!)))
          .getSingleOrNull();
    }

    // Load workflows from join table
    final wfLinks = await (db.select(db.taskTemplateWorkflows)
          ..where((r) => r.templateId.equals(tpl.id)))
        .get();
    final workflows = <Workflow>[];
    for (final link in wfLinks) {
      final wf = await (db.select(db.workflows)
            ..where((w) => w.id.equals(link.workflowId)))
          .getSingleOrNull();
      if (wf != null) workflows.add(wf);
    }

    // Fall back to legacy workflowId column if join table is empty
    if (workflows.isEmpty && tpl.workflowId != null) {
      final wf = await (db.select(db.workflows)
            ..where((w) => w.id.equals(tpl.workflowId!)))
          .getSingleOrNull();
      if (wf != null) workflows.add(wf);
    }

    // Load custom todos
    final customTodos = await (db.select(db.taskTemplateTodos)
          ..where((t) => t.templateId.equals(tpl.id))
          ..orderBy([(t) => drift.OrderingTerm.asc(t.sortOrder)]))
        .get();

    result.add(TemplateWithDetails(
      template: tpl,
      customer: customer,
      workflows: workflows,
      customTodos: customTodos,
      bundle: bundle,
    ));
  }
  return result;
});
