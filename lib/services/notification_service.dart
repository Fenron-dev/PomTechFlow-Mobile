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
        // Task direkt als erledigt markieren (ohne Riverpod – direkte DB-Verbindung)
        try {
          final db = AppDatabase();
          await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
            TasksCompanion(
              status: const drift.Value('DONE'),
              updatedAt: drift.Value(DateTime.now()),
            ),
          );
          await db.close();
        } catch (_) {}
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

    final scheduledDate = tz.TZDateTime.from(plannedDate, tz.local);
    final id = taskId.hashCode.abs() % 100000;

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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Exakte Alarme können ohne SCHEDULE_EXACT_ALARM-Berechtigung fehlschlagen
    }
  }

  static Future<void> cancelTaskReminder(String taskId) async {
    if (!_supported) return;
    await _plugin.cancel(taskId.hashCode.abs() % 100000);
  }

  // ── Schnell-Erinnerung (Timer) ─────────────────────────────────────────────

  static Future<void> scheduleReminder(String text, DateTime when) async {
    if (!_supported) return;
    if (when.isBefore(DateTime.now())) return;
    await initialize();

    final scheduledDate = tz.TZDateTime.from(when, tz.local);
    final id = when.millisecondsSinceEpoch % 100000;

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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  // ── Hilfsfunktionen ────────────────────────────────────────────────────────

  static String _hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
