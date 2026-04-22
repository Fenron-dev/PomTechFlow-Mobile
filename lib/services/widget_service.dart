import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Pushes the current timer/task state to the native Homescreen-Widget.
///
/// Keys stored in shared storage (Flutter prefix "flutter." is added automatically):
///   widgetTimerStatus  – 'idle' | 'running' | 'paused'
///   widgetElapsedSecs  – int  (elapsed seconds at the time of last save)
///   widgetTaskName     – String
///   widgetOpenTasks    – int
///   widgetStartTimeMs  – String (epoch ms as string, avoids 32-bit int overflow)
class WidgetService {
  static const String _androidProvider =
      'dev.fenron.pomtechflow_mobile.TimerWidgetProvider';
  static const String _iOSName = 'PomTechFlowWidget';
  static const String _iOSAppGroup = 'group.dev.fenron.pomtechflowMobile';

  // home_widget only supports Android and iOS — guard every call.
  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Call once at app start to register the iOS App Group.
  static Future<void> init() async {
    if (!_supported) return;
    await HomeWidget.setAppGroupId(_iOSAppGroup);
  }

  /// Saves current state and triggers a widget redraw on both platforms.
  static Future<void> update({
    required String timerStatus, // 'idle' | 'running' | 'paused'
    required int elapsedSecs,
    required String taskName,
    required int openTasks,
    DateTime? startTime,
  }) async {
    if (!_supported) return;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData('widgetTimerStatus', timerStatus),
        HomeWidget.saveWidgetData('widgetElapsedSecs', elapsedSecs),
        HomeWidget.saveWidgetData('widgetTaskName', taskName.isEmpty ? 'Kein aktiver Task' : taskName),
        HomeWidget.saveWidgetData('widgetOpenTasks', openTasks),
        HomeWidget.saveWidgetData(
          'widgetStartTimeMs',
          (startTime?.millisecondsSinceEpoch ?? 0).toString(),
        ),
      ]);
      await HomeWidget.updateWidget(
        androidName: _androidProvider,
        iOSName: _iOSName,
      );
    } catch (_) {
      // Widget not installed or platform not supported — silently ignore.
    }
  }

  /// Called when the user taps the Quick-Start button in the widget.
  /// Returns the launch URI if the app was opened from the widget.
  static Future<Uri?> initialUri() async {
    if (!_supported) return null;
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }
}
