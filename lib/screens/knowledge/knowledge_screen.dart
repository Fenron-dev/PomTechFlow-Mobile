import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/database_provider.dart';
import '../../db/database.dart';

// ─── Provider ──────────────────────────────────────────────────────────────

final knowledgeProvider =
    StreamProvider<List<KnowledgeEntry>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.knowledgeEntries)
        ..orderBy([(k) => drift.OrderingTerm.desc(k.updatedAt)]))
      .watch();
});

// ─── Screen ────────────────────────────────────────────────────────────────

class KnowledgeScreen extends ConsumerStatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  ConsumerState<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends ConsumerState<KnowledgeScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(knowledgeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wissensdatenbank'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Eintrag hinzufügen',
            onPressed: () => _showForm(context, ref, null),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Suchen (Titel, Problem, Lösung, Tags)…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: entriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (entries) {
                final filtered = _query.isEmpty
                    ? entries
                    : entries.where((e) {
                        return e.title.toLowerCase().contains(_query) ||
                            e.problem.toLowerCase().contains(_query) ||
                            e.solution.toLowerCase().contains(_query) ||
                            (e.tags?.toLowerCase().contains(_query) ?? false);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book_outlined,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          entries.isEmpty
                              ? 'Noch keine Einträge'
                              : 'Keine Einträge gefunden',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline),
                        ),
                        if (entries.isEmpty) ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _showForm(context, ref, null),
                            icon: const Icon(Icons.add),
                            label: const Text('Eintrag hinzufügen'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _KnowledgeCard(
                    entry: filtered[i],
                    query: _query,
                    onEdit: () => _showForm(context, ref, filtered[i]),
                    onDelete: () => _delete(context, ref, filtered[i].id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showForm(
      BuildContext context, WidgetRef ref, KnowledgeEntry? entry) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _KnowledgeForm(existing: entry),
    );
    ref.invalidate(knowledgeProvider);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text('Dieser KB-Eintrag wird dauerhaft gelöscht.'),
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
    await (db.delete(db.knowledgeEntries)..where((k) => k.id.equals(id))).go();
  }
}

// ─── Card ──────────────────────────────────────────────────────────────────

class _KnowledgeCard extends StatefulWidget {
  final KnowledgeEntry entry;
  final String query;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _KnowledgeCard({
    required this.entry,
    required this.query,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_KnowledgeCard> createState() => _KnowledgeCardState();
}

class _KnowledgeCardState extends State<_KnowledgeCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tags = widget.entry.tags
        ?.split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(widget.entry.title,
                style: Theme.of(context).textTheme.titleSmall),
            subtitle: Text(
              widget.entry.problem,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () =>
                      setState(() => _expanded = !_expanded),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: widget.onEdit,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: cs.error),
                  onPressed: widget.onDelete,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lösung',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: cs.primary)),
                  const SizedBox(height: 4),
                  MarkdownBody(
                    data: widget.entry.solution,
                    styleSheet: MarkdownStyleSheet.fromTheme(
                        Theme.of(context)),
                  ),
                ],
              ),
            ),
            if (tags != null && tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: tags
                      .map((t) => Chip(
                            label: Text(t,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Form ──────────────────────────────────────────────────────────────────

class _KnowledgeForm extends ConsumerStatefulWidget {
  final KnowledgeEntry? existing;
  const _KnowledgeForm({this.existing});

  @override
  ConsumerState<_KnowledgeForm> createState() => _KnowledgeFormState();
}

class _KnowledgeFormState extends ConsumerState<_KnowledgeForm> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _problemCtrl;
  late final TextEditingController _solutionCtrl;
  late final TextEditingController _tagsCtrl;
  bool _previewSolution = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.existing?.title ?? '');
    _problemCtrl =
        TextEditingController(text: widget.existing?.problem ?? '');
    _solutionCtrl =
        TextEditingController(text: widget.existing?.solution ?? '');
    _tagsCtrl =
        TextEditingController(text: widget.existing?.tags ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _problemCtrl.dispose();
    _solutionCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final problem = _problemCtrl.text.trim();
    final solution = _solutionCtrl.text.trim();
    if (title.isEmpty || problem.isEmpty || solution.isEmpty) return;

    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final tags = _tagsCtrl.text.trim().isEmpty ? null : _tagsCtrl.text.trim();

    if (widget.existing == null) {
      await db.into(db.knowledgeEntries).insert(KnowledgeEntriesCompanion.insert(
            title: title,
            problem: problem,
            solution: solution,
            tags: drift.Value(tags),
            updatedAt: drift.Value(now),
          ));
    } else {
      await (db.update(db.knowledgeEntries)
            ..where((k) => k.id.equals(widget.existing!.id)))
          .write(KnowledgeEntriesCompanion(
        title: drift.Value(title),
        problem: drift.Value(problem),
        solution: drift.Value(solution),
        tags: drift.Value(tags),
        updatedAt: drift.Value(now),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 20,
        ),
        child: ListView(
          controller: scrollCtrl,
          children: [
            Text(
              widget.existing == null
                  ? 'Eintrag hinzufügen'
                  : 'Eintrag bearbeiten',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titel / Symptom *',
                hintText: 'z.B. Windows lässt sich nicht starten',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _problemCtrl,
              decoration: const InputDecoration(
                labelText: 'Problem *',
                hintText: 'Fehlerbeschreibung',
              ),
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Lösung *',
                    style: Theme.of(context).textTheme.bodySmall),
                IconButton(
                  icon: Icon(_previewSolution
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined),
                  tooltip: _previewSolution ? 'Bearbeiten' : 'Vorschau',
                  onPressed: () =>
                      setState(() => _previewSolution = !_previewSolution),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (_previewSolution)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                      color:
                          Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: MarkdownBody(
                  data: _solutionCtrl.text.isEmpty
                      ? '_Leer_'
                      : _solutionCtrl.text,
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)),
                ),
              )
            else
              TextField(
                controller: _solutionCtrl,
                decoration: const InputDecoration(
                  hintText: 'Lösungsschritte (Markdown möglich)',
                  border: OutlineInputBorder(),
                ),
                minLines: 4,
                maxLines: 12,
                textCapitalization: TextCapitalization.sentences,
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagsCtrl,
              decoration: const InputDecoration(
                labelText: 'Tags (kommagetrennt)',
                hintText: 'z.B. windows,boot,bios',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Text(
                  widget.existing == null ? 'Hinzufügen' : 'Speichern'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
