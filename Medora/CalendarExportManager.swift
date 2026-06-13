//
//  CalendarExportManager.swift
//  Medora
//
//  Exports checklist tasks for a given day to Apple Calendar as EKEvents.
//  Each task gets a time slot derived from its timeOfDay field (or a default
//  time if none is set). Pills are labeled with 💊 and tasks with ✅.
//

import Combine
import EventKit
import SwiftUI

// MARK: - Export Result

enum CalendarExportResult {
    case success(Int)                  // number of events created
    case permissionDenied
    case partialSuccess(Int, [String]) // created, failed titles
    case failure(Error)
}

// MARK: - CalendarExportManager

@MainActor
final class CalendarExportManager: ObservableObject {
    static let shared = CalendarExportManager()

    private let eventStore = EKEventStore()

    private init() {}

    // MARK: - Authorization

    /// Requests full calendar access (iOS 17+) with a fallback for older OS.
    func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Export

    /// Exports all tasks for the selected date as Apple Calendar events.
    func exportTasks(_ tasks: [ChecklistTask], on date: Date) async -> CalendarExportResult {
        guard !tasks.isEmpty else { return .success(0) }

        // Request access if not already granted
        let status = authorizationStatus
        let isAuthorized: Bool
        if #available(iOS 17.0, *) {
            isAuthorized = (status == .fullAccess)
        } else {
            isAuthorized = (status == .authorized)
        }
        if !isAuthorized {
            let granted = await requestAccess()
            guard granted else { return .permissionDenied }
        }

        guard let defaultCalendar = eventStore.defaultCalendarForNewEvents else {
            return .failure(NSError(domain: "CalendarExportManager", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "No default calendar found."]))
        }

        var successCount = 0
        var failedTitles: [String] = []

        for task in tasks {
            let event = EKEvent(eventStore: eventStore)
            event.calendar = defaultCalendar

            // Title: pill vs task
            if task.isPill == true {
                let dosage = task.dosage.map { " \($0)" } ?? ""
                event.title = "💊 \(task.title)\(dosage)"
                var notes = "Medication reminder added by Medora."
                if let time = task.timeOfDay { notes += "\nTime: \(time)" }
                if let dosage = task.dosage { notes += "\nDosage: \(dosage)" }
                event.notes = notes
            } else {
                event.title = "✅ \(task.title)"
                event.notes = "Task added by Medora."
            }

            // Compute start time
            let startDate = eventDate(for: task, on: date)
            event.startDate = startDate
            event.endDate = startDate.addingTimeInterval(30 * 60) // 30-minute block
            event.alarms = [EKAlarm(relativeOffset: -10 * 60)]   // 10-min reminder

            do {
                try eventStore.save(event, span: .thisEvent)
                successCount += 1
            } catch {
                failedTitles.append(task.title)
            }
        }

        if failedTitles.isEmpty {
            return .success(successCount)
        } else {
            return .partialSuccess(successCount, failedTitles)
        }
    }

    // MARK: - Time Helpers

    /// Maps a task's timeOfDay string (or pill time) to a Date on the given day.
    private func eventDate(for task: ChecklistTask, on date: Date) -> Date {
        var hour = 8  // default: morning

        if let timeStr = task.timeOfDay {
            let cleaned = timeStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch cleaned {
            case "morning":          hour = 8
            case "afternoon":        hour = 13
            case "evening":          hour = 18
            case "night", "bedtime": hour = 21
            default:
                // Try parsing exact time strings like "9:30 AM" or "14:00"
                let f1 = DateFormatter()
                f1.dateFormat = "h:mm a"
                if let t = f1.date(from: timeStr) {
                    hour = Calendar.current.component(.hour, from: t)
                } else {
                    let f2 = DateFormatter()
                    f2.dateFormat = "HH:mm"
                    if let t = f2.date(from: timeStr) {
                        hour = Calendar.current.component(.hour, from: t)
                    }
                }
            }
        }

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? date
    }
}
