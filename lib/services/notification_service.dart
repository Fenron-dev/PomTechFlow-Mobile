import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:drift/drift.dart' as drift;
import '../db/database.dart';

// ─── Konstanten ──────────────────────────────────────────────────────────────

const _kChannelTask = 'task_reminders';
const _kChannelQuick = 'quick_reminders';
const _kCategoryTask = 'task_alert';
const _kActionSnooze = 'snooze';
const _kActionDone = 'done';
const _kActionCancel = 'cancel';

// Trennzeichen zwischen taskId und taskTitle im Payload
const _kSep = '|||';

// ─── Top-level Background-Handler ────────────────────────────────────────────
// Muss eine Top-Level-Funktion sein (kein Klassenmember).
// Wird in einem eigenen Isolate aufgerufen wenn die App nicht im Vordergrund ist.

@pragma('vm:entry-point')
void onBackgroundNotification(NotificationResponse details) {
  WidgetsFlutterBinding.ensureInitialized();
  NotificationService.handleResponse(details);
}

// ─── Service ─────────────────────────────────────────────────────────────────

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // ── Initialisierung ────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (!_supported || _initialized) return;
    tzdata.initializeTimeZones();
    // Lokale Zeitzone setzen – ohne dies bleibt tz.local UTC und zonedSchedule
    // plant zur falschen Zeit. Wir leiten die Zeitzone aus dem Offset von
    // DateTime.now() ab (kein natives Plugin nötig).
    try {
      final offset = DateTime.now().timeZoneOffset;
      final offsetHours = offset.inHours;
      final offsetMins = offset.inMinutes.abs() % 60;
      final sign = offsetHours >= 0 ? '+' : '-';
      final h = offsetHours.abs().toString().padLeft(2, '0');
      final m = offsetMins.toString().padLeft(2, '0');
      final etcName = 'Etc/GMT${sign == '+' ? '-' : '+'}${offsetHours.abs()}';
      // Versuche zuerst den Etc/GMT-Namen (z.B. Etc/GMT-2 für UTC+2)
      try {
        tz.setLocalLocation(tz.getLocation(etcName));
      } catch (_) {
        // Fallback: ersten Treffer mit passendem UTC-Offset suchen
        final match = tz.timeZoneDatabase.locations.values.firstWhere(
          (loc) => loc.currentTimeZone.offset == offset.inMilliseconds,
          orElse: () => tz.UTC,
        );
        tz.setLocalLocation(match);
      }
      debugPrint('NotificationService: Zeitzone gesetzt $sign$h:$m');
    } catch (e) {
      debugPrint('NotificationService: Zeitzone-Fallback UTC: $e');
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          _kCategoryTask,
          actions: [
            DarwinNotificationAction.plain(
              _kActionSnooze,
              'Schlummern (10 min)',
            ),
            DarwinNotificationAction.plain(
              _kActionDone,
              'Erledigt',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              _kActionCancel,
              'Abbrechen',
              options: {DarwinNotificationActionOption.destructive},
            ),
          ],
          options: const {
            DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
          },
        ),
      ],
    );

    await _plugin.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: handleResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotification,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Fordert – falls nötig – die Berechtigung für exakte Alarme an (Android 12+).
  /// Öffnet ggf. die System-Einstellung. No-op wenn bereits erlaubt.
  static Future<void> ensureExactAlarmPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final can = await android?.canScheduleExactNotifications() ?? true;
    if (!can) await android?.requestExactAlarmsPermission();
  }

  /// Zeigt sofort eine Test-Benachrichtigung an (umgeht den Alarm-/Zeitplan-Pfad).
  /// Dient zum Eingrenzen: erscheint sie, funktioniert die Anzeige – dann liegt
  /// ein evtl. Problem am Scheduling (Exact-Alarm/Doze), nicht an der Berechtigung.
  static Future<void> showTestNotification() async {
    if (!_supported) return;
    await initialize();
    await _plugin.show(
      99999,
      'Test-Benachrichtigung',
      'Wenn du das siehst, funktionieren Benachrichtigungen ✅',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelQuick,
          'Schnell-Erinnerungen',
          channelDescription: 'Manuelle Erinnerungen vom Timer',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
    );
  }

  /// Wählt den Android-Scheduling-Modus: exakt wenn erlaubt, sonst inexakt.
  /// Verhindert, dass `zonedSchedule` bei fehlender Exact-Alarm-Berechtigung
  /// (Android 13/14) eine Exception wirft und die Erinnerung gar nicht geplant
  /// wird – inexakt feuert dann zwar evtl. minutengenau verzögert, aber feuert.
  static Future<AndroidScheduleMode> _androidMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canExact = await android?.canScheduleExactNotifications() ?? false;
    return canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  // ── Aktions-Handler ────────────────────────────────────────────────────────

  /// Verarbeitet eine Benachrichtigungs-Antwort (Tap oder Aktion).
  /// Wird sowohl im Vordergrund als auch im Hintergrund aufgerufen.
  static Future<void> handleResponse(NotificationResponse details) async {
    final payload = details.payload;
    if (payload == null) return;

    final sep = payload.indexOf(_kSep);
    if (sep < 0) return;
    final taskId = payload.substring(0, sep);
    final taskTitle = payload.substring(sep + _kSep.length);

    switch (details.actionId) {
      case _kActionSnooze:
        // Neue Erinnerung in 10 Minuten
        final snoozeTime = DateTime.now().add(const Duration(minutes: 10));
        await scheduleTaskReminder(taskId, taskTitle, snoozeTime);
        break;

      case _kActionDone:
        // Task direkt als erledigt markieren.
        // Läuft ggf. in einem Background-Isolate → eigene DB-Verbindung nötig.
        try {
          final db = AppDatabase();
          await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
            TasksCompanion(
              status: const drift.Value('COMPLETED'), // war fälschlich 'DONE'
              updatedAt: drift.Value(DateTime.now()),
            ),
          );
          await db.close();
        } catch (e, st) {
          debugPrint('NotificationService: done-Action fehlgeschlagen: $e\n$st');
        }
        break;

      // null = Tap auf die Benachrichtigung selbst → App öffnen (kein Extra-Code nötig)
      // andere IDs → ignorieren (Swipe-Dismiss etc.)
    }
  }

  // ── Task-Erinnerung planen ─────────────────────────────────────────────────

  static Future<void> scheduleTaskReminder(
    String taskId,
    String title,
    DateTime plannedDate,
  ) async {
    if (!_supported) return;
    if (plannedDate.isBefore(DateTime.now())) return;
    await initialize();
    await ensureExactAlarmPermission();

    final scheduledDate = tz.TZDateTime.from(plannedDate, tz.local);
    final id = taskId.hashCode.abs() % 100000;
    final mode = await _androidMode();

    try {
      await _plugin.zonedSchedule(
        id,
        'Task fällig: $title',
        'Geplant für ${_hhmm(plannedDate)} · Was möchtest du tun?',
        scheduledDate,
        NotificationDetails(
          android: const AndroidNotificationDetails(
            _kChannelTask,
            'Task Erinnerungen',
            channelDescription: 'Erinnerungen für geplante Tasks',
            importance: Importance.high,
            priority: Priority.high,
            actions: [
              AndroidNotificationAction(
                _kActionSnooze,
                'Schlummern (10 min)',
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                _kActionDone,
                'Erledigt',
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                _kActionCancel,
                'Abbrechen',
                cancelNotification: true,
              ),
            ],
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            categoryIdentifier: _kCategoryTask,
          ),
        ),
        payload: '$taskId$_kSep$title',
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e, st) {
      debugPrint('NotificationService.scheduleTaskReminder fehlgeschlagen: $e\n$st');
    }
  }

  static Future<void> cancelTaskReminder(String taskId) async {
    if (!_supported) return;
    await _plugin.cancel(taskId.hashCode.abs() % 100000);
  }

  // ── Schnell-Erinnerung (Timer) ─────────────────────────────────────────────

  static Future<bool> scheduleReminder(String text, DateTime when) async {
    if (!_supported) return false;
    if (when.isBefore(DateTime.now())) return false;
    await initialize();
    await ensureExactAlarmPermission();

    final scheduledDate = tz.TZDateTime.from(when, tz.local);
    final id = when.millisecondsSinceEpoch % 100000;
    final mode = await _androidMode();

    try {
      await _plugin.zonedSchedule(
        id,
        'Erinnerung',
        text,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannelQuick,
            'Schnell-Erinnerungen',
            channelDescription: 'Manuelle Erinnerungen vom Timer',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (e, st) {
      debugPrint('NotificationService.scheduleReminder fehlgeschlagen: $e\n$st');
      return false;
    }
  }

  // ── Hilfsfunktionen ────────────────────────────────────────────────────────

  static String _hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
