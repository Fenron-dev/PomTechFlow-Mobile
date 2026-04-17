import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../../../providers/tasks_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/note_templates_provider.dart';
import '../../../db/database.dart';
import 'package:drift/drift.dart' as drift;

class NotesTab extends ConsumerStatefulWidget {
  final String taskId;
  const NotesTab({super.key, required this.taskId});

  @override
  ConsumerState<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<NotesTab> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final db = ref.read(databaseProvider);
    await db.into(db.notes).insert(
          NotesCompanion.insert(taskId: widget.taskId, content: text),
        );
    _ctrl.clear();
    ref.invalidate(notesProvider(widget.taskId));
  }

  /// Extracts unique [placeholder] names from template content, preserving order.
  List<String> _extractPlaceholders(String content) {
    final regex = RegExp(r'\[([^\]]+)\]');
    final seen = <String>{};
    final result = <String>[];
    for (final match in regex.allMatches(content)) {
      final name = match.group(1)!;
      if (seen.add(name)) result.add(name);
    }
    return result;
  }

  Future<void> _showTemplatePicker() async {
    final templatesAsync = ref.read(noteTemplatesProvider);
    final templates = templatesAsync.valueOrNull ?? [];

    if (!mounted) return;

    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Vorlagen vorhanden. Vorlagen zuerst anlegen.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<NoteTemplate>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined),
                  const SizedBox(width: 10),
                  Text('Vorlage wählen',
                      style: Theme.of(sheetCtx).textTheme.titleLarge),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: templates.length,
                itemBuilder: (_, i) {
                  final t = templates[i];
                  final placeholders = _extractPlaceholders(t.content);
                  return ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(t.name),
                    subtitle: placeholders.isEmpty
                        ? const Text('Kein Formular – direkt einfügen')
                        : Text('${placeholders.length} Felder: ${placeholders.take(3).map((p) => p.length > 20 ? '${p.substring(0, 20)}…' : p).join(', ')}${placeholders.length > 3 ? ' …' : ''}'),
                    onTap: () => Navigator.pop(sheetCtx, t),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;

    final placeholders = _extractPlaceholders(selected.content);

    if (placeholders.isEmpty) {
      // No placeholders – insert content directly
      final db = ref.read(databaseProvider);
      await db.into(db.notes).insert(
            NotesCompanion.insert(taskId: widget.taskId, content: selected.content),
          );
      ref.invalidate(notesProvider(widget.taskId));
      return;
    }

    await _showTemplateFillForm(selected, placeholders);
  }

  Future<void> _showTemplateFillForm(
      NoteTemplate template, List<String> placeholders) async {
    final controllers = {
      for (final p in placeholders) p: TextEditingController(),
    };

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(template.name,
                          style: Theme.of(sheetCtx).textTheme.titleLarge,
                          overflow: TextOverflow.ellipsis),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(sheetCtx, true),
                      child: const Text('Speichern'),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (int i = 0; i < placeholders.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _TemplateField(
                        ctrl: controllers[placeholders[i]]!,
                        label: placeholders[i],
                        hint: placeholders[i],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      String filled = template.content;
      for (final p in placeholders) {
        final value = controllers[p]!.text.trim();
        filled = filled.replaceAll('[$p]', value.isEmpty ? '[$p]' : value);
      }
      final db = ref.read(databaseProvider);
      await db.into(db.notes).insert(
            NotesCompanion.insert(taskId: widget.taskId, content: filled),
          );
      ref.invalidate(notesProvider(widget.taskId));
    }

    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Future<void> _deleteNote(String id) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.notes)..where((n) => n.id.equals(id))).go();
    ref.invalidate(notesProvider(widget.taskId));
  }

  Future<void> _editNote(Note note) async {
    final ctrl = TextEditingController(text: note.content);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Notiz bearbeiten'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          minLines: 2,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    final newContent = ctrl.text.trim();
    ctrl.dispose();
    if (confirmed != true || newContent.isEmpty || newContent == note.content) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.notes)..where((n) => n.id.equals(note.id)))
        .write(NotesCompanion(content: drift.Value(newContent)));
    ref.invalidate(notesProvider(widget.taskId));
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider(widget.taskId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                    hintText: 'Neue Notiz...',
                    isDense: true,
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send),
                onPressed: _addNote,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.description_outlined),
                tooltip: 'Vorlage verwenden',
                onPressed: _showTemplatePicker,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: notesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (notes) {
              if (notes.isEmpty) {
                return Center(
                  child: Text('Noch keine Notizen',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: notes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _NoteCard(
                  note: notes[i],
                  onDelete: () => _deleteNote(notes[i].id),
                  onEdit: () => _editNote(notes[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TemplateField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  const _TemplateField(
      {required this.ctrl, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      maxLines: 3,
      minLines: 2,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
      textCapitalization: TextCapitalization.sentences,
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  const _NoteCard({required this.note, required this.onDelete, required this.onEdit});

  bool get _isLong => note.content.length > 200 || '\n'.allMatches(note.content).length >= 4;

  void _showPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('dd.MM.yyyy HH:mm').format(note.createdAt.toLocal()),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogCtx),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: MarkdownBody(
                  data: note.content,
                  softLineBreak: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: note.content,
                    softLineBreak: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('dd.MM.yyyy HH:mm')
                        .format(note.createdAt.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLong)
                  IconButton(
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    tooltip: 'Vollansicht',
                    onPressed: () => _showPopup(context),
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Theme.of(context).colorScheme.error,
                  onPressed: onDelete,
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
