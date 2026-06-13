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

/// Kunden-IDs, sortiert nach letzter Verwendung in Tasks (neueste zuerst).
/// Für „zuletzt verwendet" im Kunden-Picker.
final recentCustomerIdsProvider = FutureProvider<List<String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.customSelect(
    'SELECT customer_id AS cid, MAX(updated_at) AS last '
    'FROM tasks WHERE customer_id IS NOT NULL '
    'GROUP BY customer_id ORDER BY last DESC LIMIT 5',
  ).get();
  return rows.map((r) => r.data['cid'] as String).toList();
});
