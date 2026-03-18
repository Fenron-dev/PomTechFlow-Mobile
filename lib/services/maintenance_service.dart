import 'dart:io';
import 'package:drift/drift.dart' show Value, OrderingTerm;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../db/database.dart';

// ── Result types ──────────────────────────────────────────────────────────────

class MaintenanceStats {
  final int dbBytes;
  final int photoBytes;
  final int totalTasks;
  final int activeTasks;        // PLANNED | ACTIVE | PAUSED
  final int completedTasks;     // COMPLETED (not archived)
  final int archivedTasks;
  final int photoCount;
  final int orphanedFileCount;
  final int orphanedBytes;

  const MaintenanceStats({
    required this.dbBytes,
    required this.photoBytes,
    required this.totalTasks,
    required this.activeTasks,
    required this.completedTasks,
    required this.archivedTasks,
    required this.photoCount,
    required this.orphanedFileCount,
    required this.orphanedBytes,
  });

  int get totalBytes => dbBytes + photoBytes;
}

class ArchiveResult {
  final int archivedCount;
  const ArchiveResult(this.archivedCount);
}

class CleanResult {
  final int deletedFiles;
  final int freedBytes;
  const CleanResult({required this.deletedFiles, required this.freedBytes});
}

class CompressResult {
  final int processedPhotos;
  final int skippedPhotos;
  final int savedBytes;
  const CompressResult({
    required this.processedPhotos,
    required this.skippedPhotos,
    required this.savedBytes,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class MaintenanceService {
  // ── Stats ────────────────────────────────────────────────────────────────

  static Future<MaintenanceStats> getStats(
    AppDatabase db,
    String storageBasePath,
  ) async {
    // DB file size
    final dbDir = await getApplicationDocumentsDirectory();
    final dbFile = File('${dbDir.path}/pomtechflow.db');
    final dbBytes = dbFile.existsSync() ? await dbFile.length() : 0;

    // Photo folder size + file list
    final photoDir = await _photoDir(storageBasePath);
    int photoBytes = 0;
    final photoDiskPaths = <String>{};
    if (photoDir.existsSync()) {
      await for (final f in photoDir.list(recursive: true)) {
        if (f is File) {
          photoDiskPaths.add(f.path);
          photoBytes += await f.length();
        }
      }
    }

    // DB photo records
    final dbPhotos = await db.select(db.photos).get();
    final dbPaths = dbPhotos.map((p) => p.filePath).toSet();

    // Orphaned: on disk but not in DB
    final orphanedPaths =
        photoDiskPaths.difference(dbPaths).toList();
    int orphanedBytes = 0;
    for (final p in orphanedPaths) {
      orphanedBytes += await File(p).length();
    }

    // Task counts
    final tasks = await db.select(db.tasks).get();
    final archived = tasks.where((t) => t.archivedAt != null).length;
    final completed =
        tasks.where((t) => t.status == 'COMPLETED' && t.archivedAt == null).length;
    final active = tasks.length - archived - completed;

    return MaintenanceStats(
      dbBytes: dbBytes,
      photoBytes: photoBytes,
      totalTasks: tasks.length,
      activeTasks: active,
      completedTasks: completed,
      archivedTasks: archived,
      photoCount: dbPhotos.length,
      orphanedFileCount: orphanedPaths.length,
      orphanedBytes: orphanedBytes,
    );
  }

  // ── Archive tasks ────────────────────────────────────────────────────────

  /// Preview: how many COMPLETED tasks would be archived with this filter.
  static Future<int> archivePreviewCount(
    AppDatabase db, {
    int olderThanDays = 30,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
    final all = await db.select(db.tasks).get();
    return all
        .where((t) =>
            t.status == 'COMPLETED' &&
            t.archivedAt == null &&
            t.updatedAt.isBefore(cutoff))
        .length;
  }

  /// Archives all COMPLETED tasks older than [olderThanDays] days.
  static Future<ArchiveResult> archiveTasks(
    AppDatabase db, {
    int olderThanDays = 30,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
    final now = DateTime.now();

    final candidates = (await db.select(db.tasks).get())
        .where((t) =>
            t.status == 'COMPLETED' &&
            t.archivedAt == null &&
            t.updatedAt.isBefore(cutoff))
        .toList();

    for (final t in candidates) {
      await (db.update(db.tasks)..where((r) => r.id.equals(t.id)))
          .write(TasksCompanion(archivedAt: Value(now)));
    }

    return ArchiveResult(candidates.length);
  }

  /// Returns all archived tasks with their customer name.
  static Future<List<Task>> getArchivedTasks(AppDatabase db) async {
    return (db.select(db.tasks)
          ..where((t) => t.archivedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.archivedAt)]))
        .get();
  }

  /// Moves a single archived task back to COMPLETED.
  static Future<void> unarchiveTask(AppDatabase db, String taskId) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      const TasksCompanion(archivedAt: Value(null)),
    );
  }

  /// Permanently deletes all archived tasks (cascade deletes sessions, photos, etc.).
  static Future<int> deleteArchivedTasks(AppDatabase db) async {
    // Collect photo paths before cascade delete
    final archivedIds = (await (db.select(db.tasks)
              ..where((t) => t.archivedAt.isNotNull()))
            .get())
        .map((t) => t.id)
        .toList();

    if (archivedIds.isEmpty) return 0;

    // Get photos for those tasks before deletion
    final photos = await (db.select(db.photos)
          ..where((p) => p.taskId.isIn(archivedIds)))
        .get();

    final count = await (db.delete(db.tasks)
          ..where((t) => t.archivedAt.isNotNull()))
        .go();

    // Delete photo files from disk
    for (final photo in photos) {
      try {
        final f = File(photo.filePath);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }

    return count;
  }

  // ── Orphaned files cleanup ───────────────────────────────────────────────

  static Future<CleanResult> cleanOrphanedFiles(
    AppDatabase db,
    String storageBasePath,
  ) async {
    final photoDir = await _photoDir(storageBasePath);
    if (!photoDir.existsSync()) {
      return const CleanResult(deletedFiles: 0, freedBytes: 0);
    }

    final dbPhotos = await db.select(db.photos).get();
    final dbPaths = dbPhotos.map((p) => p.filePath).toSet();

    int deleted = 0;
    int freed = 0;

    await for (final entity in photoDir.list(recursive: true)) {
      if (entity is File && !dbPaths.contains(entity.path)) {
        final size = await entity.length();
        await entity.delete();
        deleted++;
        freed += size;
      }
    }

    return CleanResult(deletedFiles: deleted, freedBytes: freed);
  }

  // ── Photo compression ────────────────────────────────────────────────────

  /// Compresses all JPEG/PNG photos in the DB to [quality] (1–100).
  /// Replaces files in-place. Reports progress via [onProgress].
  static Future<CompressResult> compressPhotos(
    AppDatabase db, {
    int quality = 70,
    void Function(int done, int total)? onProgress,
  }) async {
    final photos = await db.select(db.photos).get();
    int processed = 0;
    int skipped = 0;
    int saved = 0;

    for (int i = 0; i < photos.length; i++) {
      onProgress?.call(i, photos.length);
      final photo = photos[i];
      final file = File(photo.filePath);
      if (!file.existsSync()) {
        skipped++;
        continue;
      }

      final ext = photo.filePath.toLowerCase().split('.').last;
      if (!{'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(ext)) {
        skipped++;
        continue;
      }

      try {
        final originalBytes = await file.readAsBytes();
        final originalSize = originalBytes.length;

        final decoded = img.decodeImage(originalBytes);
        if (decoded == null) { skipped++; continue; }

        // Resize if larger than 1920px on the longer side
        img.Image toEncode = decoded;
        if (decoded.width > 1920 || decoded.height > 1920) {
          toEncode = decoded.width >= decoded.height
              ? img.copyResize(decoded, width: 1920)
              : img.copyResize(decoded, height: 1920);
        }

        final compressed = img.encodeJpg(toEncode, quality: quality);
        if (compressed.length < originalSize) {
          await file.writeAsBytes(compressed);
          saved += originalSize - compressed.length;
          processed++;
        } else {
          skipped++; // Already small enough
        }
      } catch (_) {
        skipped++;
      }
    }
    onProgress?.call(photos.length, photos.length);

    return CompressResult(
      processedPhotos: processed,
      skippedPhotos: skipped,
      savedBytes: saved,
    );
  }

  // ── SQLite VACUUM ────────────────────────────────────────────────────────

  /// Reclaims unused space in the SQLite database file.
  static Future<void> vacuumDatabase(AppDatabase db) async {
    await db.customStatement('VACUUM');
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static Future<Directory> _photoDir(String storageBasePath) async {
    if (storageBasePath.isNotEmpty) {
      return Directory('$storageBasePath/photos');
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/photos');
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
