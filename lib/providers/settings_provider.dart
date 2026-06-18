import 'dart:math';
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
  /// Absolute path to a logo image (PNG/JPG) for PDF reports. Null = no logo.
  final String? logoPath;
  /// Internal billing email address (never sent to customers).
  final String billingEmail;
  /// Scratch-pad text shown on dashboard.
  final String scratchPad;
  /// Custom base directory for saving files (PDFs, Fotos, Exporte).
  /// Leerer String = Standard-App-Verzeichnis.
  final String storageBasePath;
  /// Whether daily auto-backup is enabled.
  final bool autoBackupEnabled;
  /// Directory for automatic backups. Empty = app documents directory.
  final String autoBackupPath;
  /// ISO date string of last successful auto-backup (YYYY-MM-DD).
  final String lastAutoBackupDate;

  // ── Lokale Synchronisation (v16) ──────────────────────────────────────────
  /// 'STANDALONE' | 'SERVER' | 'CLIENT'
  final String syncRole;
  /// Stable UUID for this device, generated once at first start.
  final String deviceId;
  /// Human-readable name for this device shown to peers (default: technicianName).
  final String deviceName;
  /// Host/IP of the server (only relevant in CLIENT mode).
  final String syncServerHost;
  /// Port the server listens on / client connects to.
  final int syncServerPort;
  /// Auto-sync enabled (timer-based polling).
  final bool syncAutoEnabled;
  /// Auto-sync interval in minutes.
  final int syncAutoIntervalMinutes;
  /// Sync when app starts or comes to foreground.
  final bool syncOnAppStart;
  final bool syncOnResume;
  /// Sync AppSettings table across devices (off by default —
  /// device-specific keys like storagePath are always excluded).
  final bool syncAppSettings;

  // ── mDNS Rediscovery ─────────────────────────────────────────────────────
  /// Server deviceId stored after pairing — used for mDNS rediscovery.
  final String syncServerDeviceId;
  /// Server human-readable name stored after pairing.
  final String syncServerName;

  // ── Bildschirm wach halten ────────────────────────────────────────────────
  /// Bildschirm bleibt aktiv, solange die App im Vordergrund ist.
  final bool keepScreenAwake;
  /// keepScreenAwake gilt nur wenn das Gerät aufgeladen wird.
  final bool keepScreenAwakeChargingOnly;

  const AppSettings({
    this.companyName = 'Meine IT-Firma',
    this.technicianName = '',
    this.aeMinutes = 10,
    this.pomodoroMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.primaryColor = '#2563EB',
    this.themeMode = 'system',
    this.logoPath,
    this.billingEmail = '',
    this.scratchPad = '',
    this.storageBasePath = '',
    this.autoBackupEnabled = false,
    this.autoBackupPath = '',
    this.lastAutoBackupDate = '',
    // sync defaults
    this.syncRole = 'STANDALONE',
    this.deviceId = '',
    this.deviceName = '',
    this.syncServerHost = '',
    this.syncServerPort = 8765,
    this.syncAutoEnabled = true,
    this.syncAutoIntervalMinutes = 5,
    this.syncOnAppStart = true,
    this.syncOnResume = true,
    this.syncAppSettings = false,
    this.syncServerDeviceId = '',
    this.syncServerName = '',
    this.keepScreenAwake = false,
    this.keepScreenAwakeChargingOnly = false,
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
    String? logoPath,
    bool clearLogo = false,
    String? billingEmail,
    String? scratchPad,
    String? storageBasePath,
    bool? autoBackupEnabled,
    String? autoBackupPath,
    String? lastAutoBackupDate,
    String? syncRole,
    String? deviceId,
    String? deviceName,
    String? syncServerHost,
    int? syncServerPort,
    bool? syncAutoEnabled,
    int? syncAutoIntervalMinutes,
    bool? syncOnAppStart,
    bool? syncOnResume,
    bool? syncAppSettings,
    String? syncServerDeviceId,
    String? syncServerName,
    bool? keepScreenAwake,
    bool? keepScreenAwakeChargingOnly,
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
        logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
        billingEmail: billingEmail ?? this.billingEmail,
        scratchPad: scratchPad ?? this.scratchPad,
        storageBasePath: storageBasePath ?? this.storageBasePath,
        autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
        autoBackupPath: autoBackupPath ?? this.autoBackupPath,
        lastAutoBackupDate: lastAutoBackupDate ?? this.lastAutoBackupDate,
        syncRole: syncRole ?? this.syncRole,
        deviceId: deviceId ?? this.deviceId,
        deviceName: deviceName ?? this.deviceName,
        syncServerHost: syncServerHost ?? this.syncServerHost,
        syncServerPort: syncServerPort ?? this.syncServerPort,
        syncAutoEnabled: syncAutoEnabled ?? this.syncAutoEnabled,
        syncAutoIntervalMinutes: syncAutoIntervalMinutes ?? this.syncAutoIntervalMinutes,
        syncOnAppStart: syncOnAppStart ?? this.syncOnAppStart,
        syncOnResume: syncOnResume ?? this.syncOnResume,
        syncAppSettings: syncAppSettings ?? this.syncAppSettings,
        syncServerDeviceId: syncServerDeviceId ?? this.syncServerDeviceId,
        syncServerName: syncServerName ?? this.syncServerName,
        keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
        keepScreenAwakeChargingOnly: keepScreenAwakeChargingOnly ?? this.keepScreenAwakeChargingOnly,
      );

  /// Effective device name for display: falls back to technicianName then 'Dieses Gerät'.
  String get effectiveDeviceName =>
      deviceName.isNotEmpty ? deviceName : (technicianName.isNotEmpty ? technicianName : 'Dieses Gerät');
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final db = ref.watch(databaseProvider);
    final rows = await db.select(db.appSettings).get();
    final map = {for (final r in rows) r.key: r.value};

    // Generate deviceId once if missing
    String deviceId = map['deviceId'] ?? '';
    if (deviceId.isEmpty) {
      deviceId = _generateDeviceId();
      final db2 = ref.read(databaseProvider);
      await db2.into(db2.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: 'deviceId', value: deviceId),
          );
    }

    return AppSettings(
      companyName: map['companyName'] ?? 'Meine IT-Firma',
      technicianName: map['technicianName'] ?? '',
      aeMinutes: int.tryParse(map['aeMinutes'] ?? '') ?? 10,
      pomodoroMinutes: int.tryParse(map['pomodoroMinutes'] ?? '') ?? 25,
      shortBreakMinutes: int.tryParse(map['shortBreakMinutes'] ?? '') ?? 5,
      longBreakMinutes: int.tryParse(map['longBreakMinutes'] ?? '') ?? 15,
      primaryColor: map['primaryColor'] ?? '#2563EB',
      themeMode: map['themeMode'] ?? 'system',
      logoPath: map['logoPath'],
      billingEmail: map['billingEmail'] ?? '',
      scratchPad: map['scratchPad'] ?? '',
      storageBasePath: map['storageBasePath'] ?? '',
      autoBackupEnabled: map['autoBackupEnabled'] == 'true',
      autoBackupPath: map['autoBackupPath'] ?? '',
      lastAutoBackupDate: map['lastAutoBackupDate'] ?? '',
      // sync
      syncRole: map['syncRole'] ?? 'STANDALONE',
      deviceId: deviceId,
      deviceName: map['deviceName'] ?? '',
      syncServerHost: map['syncServerHost'] ?? '',
      syncServerPort: int.tryParse(map['syncServerPort'] ?? '') ?? 8765,
      syncAutoEnabled: (map['syncAutoEnabled'] ?? 'true') == 'true',
      syncAutoIntervalMinutes: int.tryParse(map['syncAutoIntervalMinutes'] ?? '') ?? 5,
      syncOnAppStart: (map['syncOnAppStart'] ?? 'true') == 'true',
      syncOnResume: (map['syncOnResume'] ?? 'true') == 'true',
      syncAppSettings: map['syncAppSettings'] == 'true',
      syncServerDeviceId: map['syncServerDeviceId'] ?? '',
      syncServerName: map['syncServerName'] ?? '',
      keepScreenAwake: map['keepScreenAwake'] == 'true',
      keepScreenAwakeChargingOnly: map['keepScreenAwakeChargingOnly'] == 'true',
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
      if (settings.logoPath != null) 'logoPath': settings.logoPath!,
      'billingEmail': settings.billingEmail,
      'scratchPad': settings.scratchPad,
      'storageBasePath': settings.storageBasePath,
      'autoBackupEnabled': settings.autoBackupEnabled.toString(),
      'autoBackupPath': settings.autoBackupPath,
      'lastAutoBackupDate': settings.lastAutoBackupDate,
      // sync
      'syncRole': settings.syncRole,
      'deviceId': settings.deviceId,
      'deviceName': settings.deviceName,
      'syncServerHost': settings.syncServerHost,
      'syncServerPort': settings.syncServerPort.toString(),
      'syncAutoEnabled': settings.syncAutoEnabled.toString(),
      'syncAutoIntervalMinutes': settings.syncAutoIntervalMinutes.toString(),
      'syncOnAppStart': settings.syncOnAppStart.toString(),
      'syncOnResume': settings.syncOnResume.toString(),
      'syncAppSettings': settings.syncAppSettings.toString(),
      'syncServerDeviceId': settings.syncServerDeviceId,
      'syncServerName': settings.syncServerName,
      'keepScreenAwake': settings.keepScreenAwake.toString(),
      'keepScreenAwakeChargingOnly': settings.keepScreenAwakeChargingOnly.toString(),
    };
    // If logoPath was cleared (null), delete the key from DB
    if (settings.logoPath == null) {
      await (db.delete(db.appSettings)
            ..where((s) => s.key.equals('logoPath')))
          .go();
    }
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

// ─── Helper ───────────────────────────────────────────────────────────────────

String _generateDeviceId() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
}
