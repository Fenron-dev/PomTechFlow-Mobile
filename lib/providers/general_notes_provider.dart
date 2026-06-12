import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'database_provider.dart';
import '../db/database.dart';

final generalNotesProvider = FutureProvider<List<GeneralNote>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.generalNotes)
        ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
      .get();
});

/// Alle einzigartigen Tags aus allen Notizen, alphabetisch sortiert.
final allTagsProvider = FutureProvider<List<String>>((ref) async {
  final notes = await ref.watch(generalNotesProvider.future);
  final tagSet = <String>{};
  for (final note in notes) {
    if (note.tags != null && note.tags!.isNotEmpty) {
      tagSet.addAll(
        note.tags!.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
      );
    }
  }
  return tagSet.toList()..sort();
});
