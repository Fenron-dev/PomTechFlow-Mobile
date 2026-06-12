import 'package:drift/drift.dart' as drift;
import '../db/database.dart';

/// Checks all DevicePresets with a maintenanceIntervalDays and creates
/// a new PLANNED task if the last maintenance task is overdue.
class DeviceMaintenanceService {
  /// Call once on app start (after DB is ready).
  /// Returns the number of maintenance tasks created.
  static Future<int> checkAndCreateTasks(AppDatabase db) async {
    final now = DateTime.now();
    final devices = await (db.select(db.devicePresets)
          ..where((d) => d.maintenanceIntervalDays.isNotNull()))
        .get();

    int created = 0;

    for (final device in devices) {
      final intervalDays = device.maintenanceIntervalDays!;
      final lastMaintenance = device.lastMaintenanceDate;

      // Determine the due date for the next maintenance task
      final DateTime nextDue;
      if (lastMaintenance == null) {
        // Never had maintenance → due immediately
        nextDue = now;
      } else {
        nextDue = lastMaintenance.add(Duration(days: intervalDays));
      }

      if (nextDue.isAfter(now)) continue; // not due yet

      // Check if there's already an open maintenance task for this device
      final existingTitle = 'Wartung: ${device.name}';
      final existing = await (db.select(db.tasks)
            ..where((t) =>
                t.title.equals(existingTitle) &
                t.status.isNotIn(const ['COMPLETED'])))
          .getSingleOrNull();

      if (existing != null) continue; // task already open

      // Create a new maintenance task
      await db.into(db.tasks).insert(TasksCompanion.insert(
            title: existingTitle,
            description: drift.Value(
                'Regelmäßige Wartung – Intervall: $intervalDays Tage'
                '${device.serial != null ? "\nS/N: ${device.serial}" : ""}'
                '${device.notes != null ? "\n${device.notes}" : ""}'),
            plannedDate: drift.Value(now),
            updatedAt: drift.Value(now),
          ));

      // Update lastMaintenanceDate on the device preset
      await (db.update(db.devicePresets)
            ..where((d) => d.id.equals(device.id)))
          .write(DevicePresetsCompanion(
        lastMaintenanceDate: drift.Value(now),
      ));

      created++;
    }

    return created;
  }
}
