import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/task_templates_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/workflows_provider.dart';
import '../../providers/hardware_bundle_provider.dart';
import '../../providers/database_provider.dart';
import '../../db/database.dart';

class TaskTemplatesScreen extends ConsumerWidget {
  const TaskTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(taskTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Task-Vorlagen')),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (templates) {
          if (templates.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('Noch keine Vorlagen'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showForm(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Neue Vorlage'),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: templates.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _TemplateCard(
              twd: templates[i],
              onEdit: () => _showForm(context, ref, templates[i]),
              onDelete: () =>
                  _delete(context, ref, templates[i].template.id),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, ref, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showForm(
      BuildContext context, WidgetRef ref, TemplateWithDetails? twd) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TemplateForm(existing: twd),
    );
    ref.invalidate(taskTemplatesProvider);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Vorlage löschen?'),
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
    final db = ref.read(databaseProvider);
    await (db.delete(db.taskTemplates)..where((t) => t.id.equals(id))).go();
    ref.invalidate(taskTemplatesProvider);
  }
}

class _TemplateCard extends StatelessWidget {
  final TemplateWithDetails twd;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TemplateCard(
      {required this.twd, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final t = twd.template;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.copy_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(t.title,
                        style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact),
                IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact),
              ],
            ),
            if (t.description != null && t.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t.description!,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (twd.customer != null)
                  Chip(
                    avatar: const Icon(Icons.business_outlined, size: 14),
                    label: Text(twd.customer!.name),
                    visualDensity: VisualDensity.compact,
                  ),
                if (twd.workflow != null)
                  Chip(
                    avatar: const Icon(Icons.checklist, size: 14),
                    label: Text(twd.workflow!.name),
                    visualDensity: VisualDensity.compact,
                  ),
                if (twd.bundle != null)
                  Chip(
                    avatar:
                        const Icon(Icons.inventory_2_outlined, size: 14),
                    label: Text(twd.bundle!.name),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Formular ─────────────────────────────────────────────────────────────────

class _TemplateForm extends ConsumerStatefulWidget {
  final TemplateWithDetails? existing;
  const _TemplateForm({this.existing});

  @override
  ConsumerState<_TemplateForm> createState() => _TemplateFormState();
}

class _TemplateFormState extends ConsumerState<_TemplateForm> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  String? _customerId;
  String? _workflowId;
  String? _bundleId;

  @override
  void initState() {
    super.initState();
    final t = widget.existing?.template;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _descCtrl = TextEditingController(text: t?.description ?? '');
    _customerId = t?.customerId;
    _workflowId = t?.workflowId;
    _bundleId = t?.hardwareBundleId;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    if (widget.existing == null) {
      await db.into(db.taskTemplates).insert(TaskTemplatesCompanion.insert(
            title: _titleCtrl.text.trim(),
            description: drift.Value(_descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim()),
            customerId: drift.Value(_customerId),
            workflowId: drift.Value(_workflowId),
            hardwareBundleId: drift.Value(_bundleId),
          ));
    } else {
      await (db.update(db.taskTemplates)
            ..where((t) => t.id.equals(widget.existing!.template.id)))
          .write(TaskTemplatesCompanion(
        title: drift.Value(_titleCtrl.text.trim()),
        description: drift.Value(_descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim()),
        customerId: drift.Value(_customerId),
        workflowId: drift.Value(_workflowId),
        hardwareBundleId: drift.Value(_bundleId),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);
    final workflowsAsync = ref.watch(workflowsProvider);
    final bundlesAsync = ref.watch(hardwareBundlesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Text(
                    widget.existing == null
                        ? 'Neue Vorlage'
                        : 'Vorlage bearbeiten',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  FilledButton(
                      onPressed: _save, child: const Text('Speichern')),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Titel *',
                        hintText: 'z.B. Neuer Arbeitsplatz einrichten'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Beschreibung', hintText: 'Optional'),
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 20),

                  // Kunde
                  customersAsync.maybeWhen(
                    data: (customers) => DropdownButtonFormField<String?>(
                      value: _customerId,
                      decoration:
                          const InputDecoration(labelText: 'Kunde (optional)'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Kein Kunde')),
                        ...customers.map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => setState(() => _customerId = v),
                    ),
                    orElse: () => const SizedBox(),
                  ),
                  const SizedBox(height: 12),

                  // Workflow (Checkliste)
                  workflowsAsync.maybeWhen(
                    data: (workflows) => DropdownButtonFormField<String?>(
                      value: _workflowId,
                      decoration: const InputDecoration(
                          labelText: 'Checkliste/Workflow (optional)'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Kein Workflow')),
                        ...workflows.map((w) => DropdownMenuItem(
                            value: w.workflow.id,
                            child: Text(w.workflow.name))),
                      ],
                      onChanged: (v) => setState(() => _workflowId = v),
                    ),
                    orElse: () => const SizedBox(),
                  ),
                  const SizedBox(height: 12),

                  // Hardware Bundle
                  bundlesAsync.maybeWhen(
                    data: (bundles) => DropdownButtonFormField<String?>(
                      value: _bundleId,
                      decoration: const InputDecoration(
                          labelText: 'Hardware Bundle (optional)'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Kein Bundle')),
                        ...bundles.map((b) => DropdownMenuItem(
                            value: b.bundle.id,
                            child: Text(b.bundle.name))),
                      ],
                      onChanged: (v) => setState(() => _bundleId = v),
                    ),
                    orElse: () => const SizedBox(),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
