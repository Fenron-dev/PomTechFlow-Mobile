import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' show Value;
import '../../providers/database_provider.dart';
import '../../providers/general_notes_provider.dart';
import '../../db/database.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String? _filterTag;
  String _searchQuery = '';
  bool _showSearch = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchQuery = '';
        _searchCtrl.clear();
      }
    });
  }

  void _showForm(GeneralNote? note, List<String> allTags) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NoteFormSheet(note: note, allTags: allTags),
    );
  }

  Future<void> _delete(GeneralNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notiz löschen?'),
        content: Text(
          note.content.length > 80
              ? '${note.content.substring(0, 80)}…'
              : note.content,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(databaseProvider);
    await (db.delete(db.generalNotes)..where((n) => n.id.equals(note.id))).go();
    ref.invalidate(generalNotesProvider);
    ref.invalidate(allTagsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(generalNotesProvider);
    final allTags = ref.watch(allTagsProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Notizen durchsuchen...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('Notizen'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            tooltip: _showSearch ? 'Suche schließen' : 'Suchen',
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (notes) {
          final q = _searchQuery.toLowerCase();
          final filtered = notes.where((n) {
            // Tag filter
            if (_filterTag != null) {
              if (n.tags == null || n.tags!.isEmpty) return false;
              if (!n.tags!.split(',').map((t) => t.trim()).contains(_filterTag)) {
                return false;
              }
            }
            // Search filter
            if (q.isNotEmpty) {
              return n.content.toLowerCase().contains(q) ||
                  (n.tags?.toLowerCase().contains(q) ?? false);
            }
            return true;
          }).toList();

          return Column(
            children: [
              // ── Tag-Filter-Leiste ────────────────────────────────
              if (allTags.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('Alle'),
                        selected: _filterTag == null,
                        onSelected: (_) =>
                            setState(() => _filterTag = null),
                      ),
                      const SizedBox(width: 6),
                      ...allTags.map((t) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text('#$t'),
                              selected: _filterTag == t,
                              onSelected: (_) => setState(
                                  () => _filterTag =
                                      _filterTag == t ? null : t),
                            ),
                          )),
                    ],
                  ),
                ),

              // ── Notizen-Liste ────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.note_outlined,
                                size: 64,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Keine Treffer für "$_searchQuery"'
                                  : _filterTag != null
                                      ? 'Keine Notizen mit Tag "#$_filterTag"'
                                      : 'Noch keine Notizen',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline),
                            ),
                            if (_filterTag == null && _searchQuery.isEmpty) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => _showForm(null, allTags),
                                icon: const Icon(Icons.add),
                                label: const Text('Erste Notiz erstellen'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _NoteCard(
                          note: filtered[i],
                          onTap: () => _showForm(filtered[i], allTags),
                          onDelete: () => _delete(filtered[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(null, allTags),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─── Note Card ────────────────────────────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  final GeneralNote note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NoteCard(
      {required this.note, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tags = note.tags != null && note.tags!.isNotEmpty
        ? note.tags!
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList()
        : <String>[];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note.content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tags
                      .map((t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#$t',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: cs.primary),
                            ),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                DateFormat('dd.MM.yyyy HH:mm')
                    .format(note.createdAt.toLocal()),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: cs.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Note Form Sheet ──────────────────────────────────────────────────────────

class _NoteFormSheet extends ConsumerStatefulWidget {
  final GeneralNote? note;
  final List<String> allTags;

  const _NoteFormSheet({this.note, required this.allTags});

  @override
  ConsumerState<_NoteFormSheet> createState() => _NoteFormSheetState();
}

class _NoteFormSheetState extends ConsumerState<_NoteFormSheet> {
  late final TextEditingController _contentCtrl;
  late List<String> _selectedTags;
  final _tagCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _contentCtrl = TextEditingController(text: widget.note?.content ?? '');
    _selectedTags = widget.note?.tags != null && widget.note!.tags!.isNotEmpty
        ? widget.note!.tags!
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList()
        : [];
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll(' ', '_');
    if (tag.isEmpty || _selectedTags.contains(tag)) {
      _tagCtrl.clear();
      return;
    }
    setState(() => _selectedTags.add(tag));
    _tagCtrl.clear();
  }

  Future<void> _save() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) return;
    final tagsStr =
        _selectedTags.isEmpty ? null : _selectedTags.join(',');
    final db = ref.read(databaseProvider);

    if (widget.note == null) {
      await db.into(db.generalNotes).insert(
            GeneralNotesCompanion.insert(
              content: content,
              tags: Value(tagsStr),
            ),
          );
    } else {
      await (db.update(db.generalNotes)
            ..where((n) => n.id.equals(widget.note!.id)))
          .write(GeneralNotesCompanion(
        content: Value(content),
        tags: Value(tagsStr),
        updatedAt: Value(DateTime.now()),
      ));
    }
    ref.invalidate(generalNotesProvider);
    ref.invalidate(allTagsProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final suggestedTags =
        widget.allTags.where((t) => !_selectedTags.contains(t)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, scrollCtrl) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title:
              Text(widget.note == null ? 'Neue Notiz' : 'Notiz bearbeiten'),
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
            // ── Notiztext ──────────────────────────────────────────
            TextField(
              controller: _contentCtrl,
              maxLines: null,
              minLines: 6,
              autofocus: widget.note == null,
              decoration: const InputDecoration(
                hintText: 'Notizinhalt...',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),

            // ── Tags ───────────────────────────────────────────────
            Text('Tags',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),

            // Ausgewählte Tags
            if (_selectedTags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _selectedTags
                    .map((t) => InputChip(
                          label: Text('#$t'),
                          onDeleted: () =>
                              setState(() => _selectedTags.remove(t)),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
            ],

            // Vorhandene Tags als Vorschläge
            if (suggestedTags.isNotEmpty) ...[
              Text('Vorhandene Tags:',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: suggestedTags
                    .take(15)
                    .map((t) => ActionChip(
                          label: Text('#$t'),
                          onPressed: () => _addTag(t),
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.add, size: 14),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],

            // Neuen Tag eingeben
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagCtrl,
                    decoration: const InputDecoration(
                      hintText: 'linux, on/linux/install ...',
                      prefixText: '# ',
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Neuer Tag',
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
          ],
        ),
      ),
    );
  }
}
