import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../db/database.dart';
import '../providers/settings_provider.dart' as sp show AppSettings, SettingsNotifier;
import 'backup_service.dart';

class AutoBackupService {
  /// Call on every app start / foreground resume.
  /// Runs a backup if auto-backup is enabled and hasn't run today yet.
  /// Returns a status message (empty = no backup needed/run).
  static Future<String> checkAndRun(
    AppDatabase db,
    sp.AppSettings settings,
    sp.SettingsNotifier notifier,
  ) async {
    if (!settings.autoBackupEnabled) return '';

    final today = _todayStr();
    if (settings.lastAutoBackupDate == today) return '';

    try {
      final dir = await _resolveDir(settings.autoBackupPath);
      await dir.create(recursive: true);
      await BackupService.exportBackupToDir(db, dir.path);
      await notifier.save(settings.copyWith(lastAutoBackupDate: today));
      return 'Auto-Backup gespeichert: ${dir.path}';
    } catch (e) {
      return 'Auto-Backup fehlgeschlagen: $e';
    }
  }

  static String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Future<Directory> _resolveDir(String configuredPath) async {
    if (configuredPath.isNotEmpty) {
      return Directory(configuredPath);
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/backups');
  }

  /// Returns the effective backup directory path for display.
  static Future<String> effectivePath(String configuredPath) async {
    if (configuredPath.isNotEmpty) return configuredPath;
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/backups';
  }
}

final autoBackupProvider = Provider<AutoBackupService>((_) => AutoBackupService());
