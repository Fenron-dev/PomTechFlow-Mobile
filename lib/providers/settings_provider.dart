import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_provider.dart';
import '../db/database.dart';

class AppSettings {
  final String companyName;
  final String technicianName;
  final int aeMinutes; // Minuten pro AE (Standard: 10)
  final int pomodoroMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final String primaryColor;
  // 'system' | 'light' | 'dark'
  final String themeMode;

  const AppSettings({
    this.companyName = 'Meine IT-Firma',
    this.technicianName = '',
    this.aeMinutes = 10,
    this.pomodoroMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.primaryColor = '#2563EB',
    this.themeMode = 'system',
  });

  AppSettings copyWith({
    String? companyName,
    String? technicianName,
    int? aeMinutes,
    int? pomodoroMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    String? primaryColor,
    String? themeMode,
  }) =>
      AppSettings(
        companyName: companyName ?? this.companyName,
        technicianName: technicianName ?? this.technicianName,
        aeMinutes: aeMinutes ?? this.aeMinutes,
        pomodoroMinutes: pomodoroMinutes ?? this.pomodoroMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        primaryColor: primaryColor ?? this.primaryColor,
        themeMode: themeMode ?? this.themeMode,
      );
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final db = ref.watch(databaseProvider);
    final rows = await db.select(db.appSettings).get();
    final map = {for (final r in rows) r.key: r.value};

    return AppSettings(
      companyName: map['companyName'] ?? 'Meine IT-Firma',
      technicianName: map['technicianName'] ?? '',
      aeMinutes: int.tryParse(map['aeMinutes'] ?? '') ?? 10,
      pomodoroMinutes: int.tryParse(map['pomodoroMinutes'] ?? '') ?? 25,
      shortBreakMinutes: int.tryParse(map['shortBreakMinutes'] ?? '') ?? 5,
      longBreakMinutes: int.tryParse(map['longBreakMinutes'] ?? '') ?? 15,
      primaryColor: map['primaryColor'] ?? '#2563EB',
      themeMode: map['themeMode'] ?? 'system',
    );
  }

  Future<void> save(AppSettings settings) async {
    final db = ref.read(databaseProvider);
    final entries = {
      'companyName': settings.companyName,
      'technicianName': settings.technicianName,
      'aeMinutes': settings.aeMinutes.toString(),
      'pomodoroMinutes': settings.pomodoroMinutes.toString(),
      'shortBreakMinutes': settings.shortBreakMinutes.toString(),
      'longBreakMinutes': settings.longBreakMinutes.toString(),
      'primaryColor': settings.primaryColor,
      'themeMode': settings.themeMode,
    };
    for (final e in entries.entries) {
      await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: e.key, value: e.value),
          );
    }
    state = AsyncData(settings);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
