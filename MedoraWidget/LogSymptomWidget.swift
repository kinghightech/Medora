//
//  LogSymptomWidget.swift
//  MedoraWidget
//
//  A simple home screen widget that opens the Medora app directly
//  to the Symptom Journal when tapped.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct LogSymptomProvider: TimelineProvider {
    func placeholder(in context: Context) -> LogSymptomEntry {
        LogSymptomEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LogSymptomEntry) -> Void) {
        completion(LogSymptomEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LogSymptomEntry>) -> Void) {
        // Static widget — refresh once per hour (content doesn't change)
        let entry = LogSymptomEntry(date: .now)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Entry

struct LogSymptomEntry: TimelineEntry {
    let date: Date
}

// MARK: - Widget Views

struct LogSymptomWidgetEntryView: View {
    var entry: LogSymptomEntry
    @Environment(\.widgetFamily) var family

    // Medora brand blue
    private let medoraBlue = Color(red: 0.05, green: 0.45, blue: 0.73)

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        default:
            mediumView
        }
    }

    // MARK: Small widget

    private var smallView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(medoraBlue.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(medoraBlue)
            }

            Text("Log Symptom")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Tap to record")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.98, blue: 1.0),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(URL(string: "medora://log-symptom"))
    }

    // MARK: Medium widget

    private var mediumView: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(medoraBlue.opacity(0.12))
                    .frame(width: 56, height: 56)

                Image(systemName: "book.closed.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(medoraBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Symptom Journal")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Tap to record how you're feeling")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.98, blue: 1.0),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(URL(string: "medora://log-symptom"))
    }
}

// MARK: - Widget Configuration

struct LogSymptomWidget: Widget {
    let kind: String = "LogSymptomWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LogSymptomProvider()) { entry in
            LogSymptomWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Log Symptom")
        .description("Quickly open Medora to record a symptom.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Small", as: .systemSmall) {
    LogSymptomWidget()
} timeline: {
    LogSymptomEntry(date: .now)
}

#Preview("Medium", as: .systemMedium) {
    LogSymptomWidget()
} timeline: {
    LogSymptomEntry(date: .now)
}
#endif
