package dev.fenron.pomtechflow_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.widget.RemoteViews

class TimerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { id ->
            updateWidget(context, appWidgetManager, id)
        }
    }

    companion object {
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            // home_widget stores data with "flutter." prefix in FlutterSharedPreferences
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE,
            )

            val status       = prefs.getString("flutter.widgetTimerStatus", "idle") ?: "idle"
            val elapsedSecs  = prefs.getLong("flutter.widgetElapsedSecs", 0L)
            val taskName     = prefs.getString("flutter.widgetTaskName", "") ?: ""
            val openTasks    = prefs.getLong("flutter.widgetOpenTasks", 0L)
            val startTimeMsStr = prefs.getString("flutter.widgetStartTimeMs", "0") ?: "0"
            val startTimeMs  = startTimeMsStr.toLongOrNull() ?: 0L

            val views = RemoteViews(context.packageName, R.layout.timer_widget)

            // ── Task name ──────────────────────────────────────────────────
            views.setTextViewText(
                R.id.tv_task_name,
                taskName.ifEmpty { "Kein aktiver Task" },
            )

            // ── Open tasks badge ───────────────────────────────────────────
            views.setTextViewText(
                R.id.tv_open_tasks,
                if (openTasks > 0) "$openTasks offen" else "",
            )

            // ── Status label ───────────────────────────────────────────────
            val statusLabel = when (status) {
                "running" -> "▶ Läuft"
                "paused"  -> "⏸ Pausiert"
                else      -> "Kein Timer"
            }
            views.setTextViewText(R.id.tv_status, statusLabel)

            // ── Chronometer ────────────────────────────────────────────────
            // Chronometer.base is in SystemClock.elapsedRealtime() space.
            // We convert wall-clock elapsed to elapsedRealtime offset.
            val chronoBase = when (status) {
                "running" -> {
                    if (startTimeMs > 0L) {
                        val wallElapsed = System.currentTimeMillis() - startTimeMs
                        SystemClock.elapsedRealtime() - wallElapsed
                    } else {
                        SystemClock.elapsedRealtime() - elapsedSecs * 1000L
                    }
                }
                "paused" -> SystemClock.elapsedRealtime() - elapsedSecs * 1000L
                else     -> SystemClock.elapsedRealtime()   // shows 00:00
            }
            views.setChronometer(
                R.id.chronometer,
                chronoBase,
                null,
                status == "running",
            )

            // ── Tap → open app ─────────────────────────────────────────────
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val launchPi = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, launchPi)

            // ── "Öffnen" button → open app to dashboard ────────────────────
            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("widget_action", "open_dashboard")
            }
            val openPi = PendingIntent.getActivity(
                context, 1, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.btn_open, openPi)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
