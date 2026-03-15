import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Notifications werden nur auf Mobile-Plattformen unterstützt
  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> initialize() async {
    if (!_supported || _initialized) return;
    tzdata.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
          android: androidSettings, iOS: iosSettings),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  static Future<void> scheduleTaskReminder(
    String taskId,
    String title,
    DateTime plannedDate,
  ) async {
    if (!_supported) return;
    if (plannedDate.isBefore(DateTime.now())) return;
    await initialize();

    final scheduledDate = tz.TZDateTime.from(plannedDate, tz.local);

    await _plugin.zonedSchedule(
      taskId.hashCode.abs() % 100000,
      'Task fällig: $title',
      'Dieser Task ist für heute geplant.',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          'Task Erinnerungen',
          channelDescription: 'Erinnerungen für geplante Tasks',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelTaskReminder(String taskId) async {
    if (!_supported) return;
    await _plugin.cancel(taskId.hashCode.abs() % 100000);
  }
}
