import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show OrderingTerm, OrderingMode;
import '../db/database.dart';
import 'database_provider.dart';

class BundleWithItems {
  final HardwareBundle bundle;
  final List<HardwareBundleItem> items;
  BundleWithItems({required this.bundle, required this.items});
}

final hardwareBundlesProvider =
    FutureProvider<List<BundleWithItems>>((ref) async {
  final db = ref.watch(databaseProvider);
  final bundles = await (db.select(db.hardwareBundles)
        ..orderBy([(b) => OrderingTerm(expression: b.name)]))
      .get();
  final result = <BundleWithItems>[];
  for (final b in bundles) {
    final items = await (db.select(db.hardwareBundleItems)
          ..where((i) => i.bundleId.equals(b.id))
          ..orderBy([(i) => OrderingTerm(expression: i.sortOrder)]))
        .get();
    result.add(BundleWithItems(bundle: b, items: items));
  }
  return result;
});
