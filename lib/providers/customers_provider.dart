import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'database_provider.dart';
import '../db/database.dart';

final customersProvider = FutureProvider<List<Customer>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.customers)
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .get();
});
