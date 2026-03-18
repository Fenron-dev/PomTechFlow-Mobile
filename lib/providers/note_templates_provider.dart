import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'database_provider.dart';
import '../db/database.dart';

/// Alle Notiz-Vorlagen, alphabetisch nach Name sortiert.
final noteTemplatesProvider = FutureProvider<List<NoteTemplate>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.noteTemplates)
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();
});
