import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/tasks_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../db/database.dart';

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

  Future<void> _deleteNote(String id) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.notes)..where((n) => n.id.equals(id))).go();
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
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _NoteCard(
                  note: notes[i],
                  onDelete: () => _deleteNote(notes[i].id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onDelete;
  const _NoteCard({required this.note, required this.onDelete});

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
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: Theme.of(context).colorScheme.error,
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
