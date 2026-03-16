import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'database_provider.dart';
import '../db/database.dart';

final deviceLibraryProvider = FutureProvider<List<DevicePreset>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.devicePresets)
        ..orderBy([
          (d) => OrderingTerm(expression: d.type),
          (d) => OrderingTerm(expression: d.name),
        ]))
      .get();
});
