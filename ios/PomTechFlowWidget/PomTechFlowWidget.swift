import WidgetKit
import SwiftUI

// ── Data model ────────────────────────────────────────────────────────────────

struct TimerData {
    let timerStatus: String   // "idle" | "running" | "paused"
    let elapsedSecs: Int
    let taskName: String
    let openTasks: Int
    let startTimeMs: Double   // epoch ms (0 if not running)

    static let empty = TimerData(
        timerStatus: "idle",
        elapsedSecs: 0,
        taskName: "Kein aktiver Task",
        openTasks: 0,
        startTimeMs: 0
    )

    /// Reads values from the shared App Group UserDefaults.
    static func fromSharedDefaults() -> TimerData {
        let defaults = UserDefaults(suiteName: "group.dev.fenron.pomtechflowMobile")
        let status    = defaults?.string(forKey: "flutter.widgetTimerStatus") ?? "idle"
        let elapsed   = defaults?.integer(forKey: "flutter.widgetElapsedSecs") ?? 0
        let taskName  = defaults?.string(forKey: "flutter.widgetTaskName") ?? ""
        let openTasks = defaults?.integer(forKey: "flutter.widgetOpenTasks") ?? 0
        let startStr  = defaults?.string(forKey: "flutter.widgetStartTimeMs") ?? "0"
        let startMs   = Double(startStr) ?? 0.0
        return TimerData(
            timerStatus: status,
            elapsedSecs: elapsed,
            taskName: taskName.isEmpty ? "Kein aktiver Task" : taskName,
            openTasks: openTasks,
            startTimeMs: startMs
        )
    }

    /// Converts stored epoch-ms timestamp to a Date for the timer display.
    var timerStartDate: Date? {
        guard startTimeMs > 0 else { return nil }
        return Date(timeIntervalSince1970: startTimeMs / 1000.0)
    }
}

// ── Timeline Provider ─────────────────────────────────────────────────────────

struct TimerWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: .now, data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(TimerEntry(date: .now, data: TimerData.fromSharedDefaults()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let data = TimerData.fromSharedDefaults()
        let entry = TimerEntry(date: .now, data: data)

        // Refresh every 30 minutes; the app pushes updates on state change.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct TimerEntry: TimelineEntry {
    let date: Date
    let data: TimerData
}

// ── Widget View ───────────────────────────────────────────────────────────────

struct TimerWidgetEntryView: View {
    var entry: TimerEntry

    private var statusLabel: String {
        switch entry.data.timerStatus {
        case "running": return "▶ Läuft"
        case "paused":  return "⏸ Pausiert"
        default:        return "Kein Timer"
        }
    }

    private var statusColor: Color {
        switch entry.data.timerStatus {
        case "running": return .green
        case "paused":  return .orange
        default:        return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // Header
            HStack {
                Text("PomTechFlow")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .bold()
                Spacer()
                if entry.data.openTasks > 0 {
                    Text("\(entry.data.openTasks) offen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Timer display
            if entry.data.timerStatus == "running",
               let start = entry.data.timerStartDate {
                Text(start, style: .timer)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            } else {
                let h = entry.data.elapsedSecs / 3600
                let m = (entry.data.elapsedSecs % 3600) / 60
                let s = entry.data.elapsedSecs % 60
                Text(String(format: "%d:%02d:%02d", h, m, s))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            // Task name
            Text(entry.data.taskName)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)

            Spacer(minLength: 0)

            // Status
            Text(statusLabel)
                .font(.caption2)
                .foregroundStyle(statusColor)
        }
        .padding(12)
        .containerBackground(
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.1, blue: 0.2),
                         Color(red: 0.05, green: 0.05, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .widget
        )
        // Tapping the widget opens the app via the registered URL
        .widgetURL(URL(string: "pomtechflow://widget/open_dashboard"))
    }
}

// ── Widget configuration ──────────────────────────────────────────────────────

struct PomTechFlowWidget: Widget {
    let kind: String = "PomTechFlowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimerWidgetProvider()) { entry in
            TimerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("PomTechFlow Timer")
        .description("Aktiver Timer und offene Tasks auf dem Homescreen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ── Preview ───────────────────────────────────────────────────────────────────

#Preview(as: .systemMedium) {
    PomTechFlowWidget()
} timeline: {
    TimerEntry(date: .now, data: TimerData(
        timerStatus: "running",
        elapsedSecs: 735,
        taskName: "Server-Wartung Kunde GmbH",
        openTasks: 3,
        startTimeMs: Date().timeIntervalSince1970 * 1000 - 735_000
    ))
}
