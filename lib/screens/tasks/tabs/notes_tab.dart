import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/tasks_provider.dart';
import '../../../providers/database_provider.dart';
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

  Future<void> _showRemoteSupportTemplate() async {
    final problemCtrl = TextEditingController();
    final causeCtrl = TextEditingController();
    final solutionCtrl = TextEditingController();
    final resultCtrl = TextEditingController();

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
                    const Icon(Icons.computer_outlined),
                    const SizedBox(width: 10),
                    Text('Fernwartungs-Vorlage',
                        style: Theme.of(sheetCtx).textTheme.titleLarge),
                    const Spacer(),
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
                    _TemplateField(
                        ctrl: problemCtrl,
                        label: 'Problem *',
                        hint: 'Was war das Problem?'),
                    const SizedBox(height: 12),
                    _TemplateField(
                        ctrl: causeCtrl,
                        label: 'Ursache',
                        hint: 'Was hat das Problem verursacht?'),
                    const SizedBox(height: 12),
                    _TemplateField(
                        ctrl: solutionCtrl,
                        label: 'Lösung *',
                        hint: 'Was wurde gemacht?'),
                    const SizedBox(height: 12),
                    _TemplateField(
                        ctrl: resultCtrl,
                        label: 'Ergebnis',
                        hint: 'Was ist das Ergebnis?'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final problem = problemCtrl.text.trim();
      final solution = solutionCtrl.text.trim();
      if (problem.isEmpty && solution.isEmpty) {
        problemCtrl.dispose();
        causeCtrl.dispose();
        solutionCtrl.dispose();
        resultCtrl.dispose();
        return;
      }
      final lines = <String>['[Fernwartung]'];
      if (problem.isNotEmpty) lines.add('Problem: $problem');
      if (causeCtrl.text.trim().isNotEmpty) lines.add('Ursache: ${causeCtrl.text.trim()}');
      if (solution.isNotEmpty) lines.add('Lösung: $solution');
      if (resultCtrl.text.trim().isNotEmpty) lines.add('Ergebnis: ${resultCtrl.text.trim()}');
      final db = ref.read(databaseProvider);
      await db.into(db.notes).insert(
            NotesCompanion.insert(taskId: widget.taskId, content: lines.join('\n')),
          );
      ref.invalidate(notesProvider(widget.taskId));
    }

    problemCtrl.dispose();
    causeCtrl.dispose();
    solutionCtrl.dispose();
    resultCtrl.dispose();
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
                icon: const Icon(Icons.computer_outlined),
                tooltip: 'Fernwartungs-Vorlage',
                onPressed: _showRemoteSupportTemplate,
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
                  Text(note.content,
                      style: Theme.of(context).textTheme.bodyMedium),
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
