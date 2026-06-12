import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import '../../providers/database_provider.dart';
import '../../providers/note_templates_provider.dart';
import '../../db/database.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class NoteTemplatesScreen extends ConsumerWidget {
  const NoteTemplatesScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, NoteTemplate t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vorlage löschen?'),
        content: Text('"${t.name}" wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(databaseProvider);
    await (db.delete(db.noteTemplates)..where((r) => r.id.equals(t.id))).go();
    ref.invalidate(noteTemplatesProvider);
  }

  void _openForm(BuildContext context, NoteTemplate? template) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TemplateFormSheet(template: template),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(noteTemplatesProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notiz-Vorlagen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Neue Vorlage',
            onPressed: () => _openForm(context, null),
          ),
        ],
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (templates) => templates.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.description_outlined,
                        size: 64, color: cs.outlineVariant),
                    const SizedBox(height: 16),
                    Text('Noch keine Vorlagen',
                        style: TextStyle(color: cs.outline)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Erste Vorlage erstellen'),
                      onPressed: () => _openForm(context, null),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                itemCount: templates.length,
                itemBuilder: (_, i) {
                  final t = templates[i];
                  final tags = _parseTags(t.tags);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        child: Icon(Icons.description_outlined,
                            color: cs.primary, size: 20),
                      ),
                      title: Text(t.name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(
                            t.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.outline),
                          ),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: tags
                                  .map((tag) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text('#$tag',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                    color: cs.primary)),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Bearbeiten',
                            onPressed: () => _openForm(context, t),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 20, color: cs.error),
                            tooltip: 'Löschen',
                            onPressed: () => _delete(context, ref, t),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  List<String> _parseTags(String? raw) => raw == null || raw.isEmpty
      ? []
      : raw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
}

// ─── Formular Bottom-Sheet ────────────────────────────────────────────────────

class _TemplateFormSheet extends ConsumerStatefulWidget {
  final NoteTemplate? template;
  const _TemplateFormSheet({this.template});

  @override
  ConsumerState<_TemplateFormSheet> createState() => _TemplateFormSheetState();
}

class _TemplateFormSheetState extends ConsumerState<_TemplateFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contentCtrl;
  late List<String> _tags;
  final _tagCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.template?.name ?? '');
    _contentCtrl =
        TextEditingController(text: widget.template?.content ?? '');
    _tags = _parseTags(widget.template?.tags);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  List<String> _parseTags(String? raw) => raw == null || raw.isEmpty
      ? []
      : raw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll(' ', '_');
    if (tag.isEmpty || _tags.contains(tag)) {
      _tagCtrl.clear();
      return;
    }
    setState(() => _tags.add(tag));
    _tagCtrl.clear();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (name.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name und Inhalt dürfen nicht leer sein.')),
      );
      return;
    }
    final tagsStr = _tags.isEmpty ? null : _tags.join(',');
    final db = ref.read(databaseProvider);
    final now = DateTime.now();

    if (widget.template == null) {
      await db.into(db.noteTemplates).insert(
            NoteTemplatesCompanion.insert(
              name: name,
              content: content,
              tags: Value(tagsStr),
            ),
          );
    } else {
      await (db.update(db.noteTemplates)
            ..where((r) => r.id.equals(widget.template!.id)))
          .write(NoteTemplatesCompanion(
        name: Value(name),
        content: Value(content),
        tags: Value(tagsStr),
        updatedAt: Value(now),
      ));
    }
    ref.invalidate(noteTemplatesProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNew = widget.template == null;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, scrollCtrl) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(isNew ? 'Neue Vorlage' : 'Vorlage bearbeiten'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(
                onPressed: _save,
                child: const Text('Speichern'),
              ),
            ),
          ],
        ),
        body: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(16),
          children: [
            // ── Name ───────────────────────────────────────────────
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Vorlagenname *',
                hintText: 'z.B. Fernwartungs-Bericht',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),

            // ── Hinweis Platzhalter ────────────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: cs.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Platzhalter mit [Eckige Klammern] markieren – z.B. [Problem], [Lösung], [Kunde].\n'
                      'Beim Anwenden der Vorlage werden sie als ausfüllbare Bereiche hervorgehoben.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Inhalt ─────────────────────────────────────────────
            TextField(
              controller: _contentCtrl,
              maxLines: null,
              minLines: 8,
              decoration: const InputDecoration(
                labelText: 'Vorlage-Inhalt *',
                hintText:
                    'Problem: [Problem beschreiben]\n\nUrsache: [Ursache]\n\nLösung: [Lösung]',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),

            // ── Tags ───────────────────────────────────────────────
            Text('Vorausgefüllte Tags',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Beim Anwenden der Vorlage werden diese Tags automatisch gesetzt.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 10),

            if (_tags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _tags
                    .map((t) => InputChip(
                          label: Text('#$t'),
                          onDeleted: () =>
                              setState(() => _tags.remove(t)),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
            ],

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagCtrl,
                    decoration: const InputDecoration(
                      hintText: 'fernwartung, kunde, incident ...',
                      prefixText: '# ',
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Tag hinzufügen',
                    ),
                    onSubmitted: _addTag,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _addTag(_tagCtrl.text),
                  child: const Text('Hinzufügen'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
