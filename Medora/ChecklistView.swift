//
//  ChecklistView.swift
//  Medora
//
//  A daily checklist with a progress bar and a month calendar.
//  The calendar opens on today's date; tapping a day lets the user add and
//  check off tasks for that specific day. Tasks persist across launches.
//

import SwiftUI
import Combine
import UserNotifications
import EventKit

// MARK: - Model

/// A single checklist item belonging to one calendar day.
struct ChecklistTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    
    // Pill properties
    var isPill: Bool?
    var dosage: String?
    var timeOfDay: String?
    var colorHex: String?
    var isSyncedFromHealthKit: Bool?
    var appleMedicationIdString: String?

    init(id: UUID = UUID(), 
         title: String, 
         isDone: Bool = false, 
         isPill: Bool? = false, 
         dosage: String? = nil, 
         timeOfDay: String? = nil, 
         colorHex: String? = nil, 
         isSyncedFromHealthKit: Bool? = false, 
         appleMedicationIdString: String? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.isPill = isPill
        self.dosage = dosage
        self.timeOfDay = timeOfDay
        self.colorHex = colorHex
        self.isSyncedFromHealthKit = isSyncedFromHealthKit
        self.appleMedicationIdString = appleMedicationIdString
    }
}

// MARK: - Notification Manager

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleMedicationReminder(for task: ChecklistTask, on date: Date) {
        guard task.isPill == true, let timeStr = task.timeOfDay else { return }
        
        let calendar = Calendar.current
        var targetHour = 8
        var targetMinute = 0
        
        let cleaned = timeStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned == "morning" {
            targetHour = 8
        } else if cleaned == "afternoon" {
            targetHour = 13
        } else if cleaned == "evening" {
            targetHour = 18
        } else if cleaned == "night" || cleaned == "bedtime" {
            targetHour = 21
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            if let timeDate = formatter.date(from: timeStr) {
                let comps = calendar.dateComponents([.hour, .minute], from: timeDate)
                targetHour = comps.hour ?? 8
                targetMinute = comps.minute ?? 0
            } else {
                formatter.dateFormat = "HH:mm"
                if let timeDate = formatter.date(from: timeStr) {
                    let comps = calendar.dateComponents([.hour, .minute], from: timeDate)
                    targetHour = comps.hour ?? 8
                    targetMinute = comps.minute ?? 0
                }
            }
        }
        
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        dateComponents.hour = targetHour
        dateComponents.minute = targetMinute
        
        guard let scheduledDate = calendar.date(from: dateComponents), scheduledDate > Date() else {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Medication Reminder"
        let dosageText = task.dosage.map { " (\($0))" } ?? ""
        content.body = "Time to take your \(task.title)\(dosageText)."
        content.sound = .default
        
        let dateKey = ChecklistStore.key(for: date)
        let identifier = "medora.reminder.\(task.id.uuidString).\(dateKey)"
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
    
    func cancelMedicationReminder(for task: ChecklistTask, on date: Date) {
        let dateKey = ChecklistStore.key(for: date)
        let identifier = "medora.reminder.\(task.id.uuidString).\(dateKey)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

// MARK: - Store

/// Holds the tasks for every day, keyed by `yyyy-MM-dd`, and persists them to
/// `UserDefaults` as JSON so they survive app launches.
@MainActor
final class ChecklistStore: ObservableObject {
    @Published private(set) var tasksByDay: [String: [ChecklistTask]] = [:]

    private let storageKey = "medora.checklist.tasksByDay"
    private let defaults = UserDefaults.standard

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        load()
    }

    static func key(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    func tasks(for date: Date) -> [ChecklistTask] {
        tasksByDay[Self.key(for: date)] ?? []
    }

    func addTask(_ title: String, on date: Date) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasksByDay[Self.key(for: date), default: []].append(ChecklistTask(title: trimmed, isPill: false))
        save()
    }

    func addPill(_ title: String, dosage: String, timeOfDay: String, colorHex: String, on date: Date, scheduleReminder: Bool = true) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = ChecklistTask(
            title: trimmed,
            isDone: false,
            isPill: true,
            dosage: dosage.isEmpty ? "1 dose" : dosage,
            timeOfDay: timeOfDay.isEmpty ? "Morning" : timeOfDay,
            colorHex: colorHex.isEmpty ? "#4D96FF" : colorHex,
            isSyncedFromHealthKit: false
        )
        tasksByDay[Self.key(for: date), default: []].append(task)
        save()
        
        if scheduleReminder {
            NotificationManager.shared.scheduleMedicationReminder(for: task, on: date)
        }
    }

    func syncWithApplePills(_ applePills: [ApplePill], on date: Date) {
        let key = Self.key(for: date)
        var currentTasks = tasksByDay[key] ?? []
        
        let colors = ["#FF6B6B", "#4D96FF", "#6BCB77", "#FFD93D", "#9B5DE5"]
        var colorIdx = 0
        
        for pill in applePills {
            let exists = currentTasks.contains { task in
                task.isPill == true && (task.appleMedicationIdString == pill.id || task.title.lowercased() == pill.name.lowercased())
            }
            if !exists {
                let colorHex = colors[colorIdx % colors.count]
                colorIdx += 1
                
                let task = ChecklistTask(
                    title: pill.name,
                    isDone: false,
                    isPill: true,
                    dosage: "1 dose",
                    timeOfDay: "Morning",
                    colorHex: colorHex,
                    isSyncedFromHealthKit: true,
                    appleMedicationIdString: pill.id
                )
                currentTasks.append(task)
                
                if pill.hasSchedule {
                    NotificationManager.shared.scheduleMedicationReminder(for: task, on: date)
                }
            }
        }
        
        tasksByDay[key] = currentTasks
        save()
    }

    func toggle(_ task: ChecklistTask, on date: Date) {
        let key = Self.key(for: date)
        guard let index = tasksByDay[key]?.firstIndex(where: { $0.id == task.id }) else { return }
        tasksByDay[key]?[index].isDone.toggle()
        save()
    }

    func delete(at offsets: IndexSet, on date: Date) {
        let key = Self.key(for: date)
        guard let tasks = tasksByDay[key] else { return }
        for index in offsets {
            if index < tasks.count {
                let task = tasks[index]
                if task.isPill == true {
                    NotificationManager.shared.cancelMedicationReminder(for: task, on: date)
                }
            }
        }
        tasksByDay[key]?.remove(atOffsets: offsets)
        if tasksByDay[key]?.isEmpty == true {
            tasksByDay[key] = nil
        }
        save()
    }

    /// True if the given day has at least one task and all of them are done.
    func isComplete(for date: Date) -> Bool {
        let dayTasks = tasks(for: date)
        return !dayTasks.isEmpty && dayTasks.allSatisfy(\.isDone)
    }

    func hasTasks(for date: Date) -> Bool {
        !(tasksByDay[Self.key(for: date)]?.isEmpty ?? true)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [ChecklistTask]].self, from: data) else {
            return
        }
        tasksByDay = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasksByDay) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
import SwiftUI
import HealthKit

// MARK: - Checklist screen

struct ChecklistView: View {
    @ObservedObject var store: ChecklistStore
    @ObservedObject var healthStore: HealthStore
    @ObservedObject private var loc = LocalizationManager.shared
    
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var isMonthView = false
    @State private var selectedCategory = "All"
    @State private var isShowingAddSheet = false
    @State private var isSyncing = false
    @FocusState private var isAddFieldFocused: Bool

    // Calendar export state
    @State private var isShowingExportSheet = false
    @State private var isExporting = false
    @State private var exportToast: ExportToast? = nil

    private let calendar = Calendar.current

    private var selectedTasks: [ChecklistTask] {
        store.tasks(for: selectedDate)
    }

    private var completedCount: Int {
        selectedTasks.filter(\.isDone).count
    }

    private var progress: Double {
        guard !selectedTasks.isEmpty else { return 0 }
        return Double(completedCount) / Double(selectedTasks.count)
    }

    // MARK: Week navigation helpers
    
    private var startOfWeek: Date {
        let weekday = calendar.component(.weekday, from: selectedDate)
        let diff = calendar.firstWeekday - weekday
        let adjustedDiff = diff > 0 ? diff - 7 : diff
        return calendar.date(byAdding: .day, value: adjustedDiff, to: selectedDate) ?? selectedDate
    }

    private var weekDays: [Date] {
        let start = calendar.startOfDay(for: startOfWeek)
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: start)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MedoraBackground()

            ScrollView {
                VStack(spacing: 16) {
                    // Circular Progress Ring Header
                    CircularProgressRing(
                        progress: progress,
                        completedCount: completedCount,
                        totalCount: selectedTasks.count
                    )
                    
                    // Calendar Picker Control
                    HStack {
                        Text(isMonthView ? monthTitle : loc.t("Weekly Plan"))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.medoraDeepBlue)
                        
                        Spacer()
                        
                        Button {
                            HapticManager.shared.triggerSelection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isMonthView.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isMonthView ? "calendar.day.timeline.left" : "calendar")
                                Text(isMonthView ? loc.t("Show Week") : loc.t("Show Month"))
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.medoraBlue)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color.medoraBlue.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)
                    
                    if isMonthView {
                        calendarCard
                    } else {
                        weekStripView
                    }
                    
                    if HKHealthStore.isHealthDataAvailable() {
                        healthSyncBanner
                    }

                    if !selectedTasks.isEmpty {
                        calendarExportBanner
                    }
                    
                    HStack {
                        categoryTabs
                        Spacer()
                    }
                    .padding(.top, 4)
                    
                    tasksListCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 88)
            }
            
            fabButton

            // Export toast overlay
            if let toast = exportToast {
                VStack {
                    Spacer()
                    ExportToastView(toast: toast)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 90)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle(loc.t("Checklist"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isShowingAddSheet) {
            AddChecklistItemSheet(store: store, selectedDate: selectedDate)
        }
        .sheet(isPresented: $isShowingExportSheet) {
            CalendarExportSheet(
                tasks: selectedTasks,
                date: selectedDate,
                isExporting: $isExporting
            ) { result in
                handleExportResult(result)
            }
        }
        .task {
            if HKHealthStore.isHealthDataAvailable() {
                await performAutoSync()
            }
        }
    }

    private func performAutoSync() async {
        let applePills = await healthStore.fetchApplePills()
        guard !applePills.isEmpty else { return }
        
        await MainActor.run {
            store.syncWithApplePills(applePills, on: selectedDate)
        }
    }

    // MARK: Circular progress ring
    
    struct CircularProgressRing: View {
        let progress: Double
        let completedCount: Int
        let totalCount: Int
        @ObservedObject private var loc = LocalizationManager.shared
        
        var body: some View {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.medoraBlue.opacity(0.12), lineWidth: 8)
                        .frame(width: 68, height: 68)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                        .stroke(
                            LinearGradient(
                                colors: [Color.medoraBlue, Color.medoraBlue.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 68, height: 68)
                        .rotationEffect(Angle(degrees: -90))
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.medoraDeepBlue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.medoraDeepBlue)
                    
                    Text("\(completedCount) of \(totalCount) completed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)
        }
        
        private var titleText: String {
            if totalCount == 0 {
                return loc.t("No tasks today")
            } else if completedCount == totalCount {
                return loc.t("All completed! 🎉")
            } else if progress >= 0.5 {
                return loc.t("Over halfway done!")
            } else {
                return loc.t("Keep it up!")
            }
        }
    }

    // MARK: Week strip view
    
    private var weekStripView: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(date)
                let complete = store.isComplete(for: date)
                let hasTasks = store.hasTasks(for: date)
                
                Button {
                    HapticManager.shared.triggerSelection()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selectedDate = date
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(dayName(for: date))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isSelected ? .white : .secondary)
                        
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 17, weight: isSelected ? .bold : .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? .white : (isToday ? Color.medoraBlue : .primary))
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(isSelected ? Color.medoraBlue : (isToday ? Color.medoraBlue.opacity(0.12) : .clear))
                            )
                        
                        Circle()
                            .fill(hasTasks ? (complete ? Color.medoraGreen : Color.medoraBlue) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color.medoraBlue.opacity(0.08) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)
    }

    private func dayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    // MARK: Export result handler

    private func handleExportResult(_ result: CalendarExportResult) {
        switch result {
        case .success(let count):
            HapticManager.shared.triggerNotification(type: .success)
            showToast(.success("\(count) event\(count == 1 ? "" : "s") added to Apple Calendar ✓"))
        case .permissionDenied:
            HapticManager.shared.triggerNotification(type: .error)
            showToast(.error("Calendar access denied. Enable in Settings."))
        case .partialSuccess(let count, _):
            HapticManager.shared.triggerNotification(type: .warning)
            showToast(.success("\(count) event\(count == 1 ? "" : "s") added (some failed)."))
        case .failure:
            HapticManager.shared.triggerNotification(type: .error)
            showToast(.error("Export failed. Please try again."))
        }
    }

    private func showToast(_ toast: ExportToast) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            exportToast = toast
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                exportToast = nil
            }
        }
    }

    // MARK: Apple Calendar export banner

    private var calendarExportBanner: some View {
        Button {
            HapticManager.shared.triggerSelection()
            isShowingExportSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#FF6B6B") ?? .red, Color(hex: "#FF8E53") ?? .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("Send to Apple Calendar"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.medoraDeepBlue)
                    Text(loc.t("Export today's checklist as calendar events."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.medoraBlue.opacity(0.5))
                }
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.medoraHairline, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Health sync banner
    
    private var healthSyncBanner: some View {
        Button {
            Task {
                isSyncing = true
                HapticManager.shared.triggerImpact(style: .medium)
                let applePills = await healthStore.fetchApplePills(requestingAuthorization: true)
                if !applePills.isEmpty {
                    await MainActor.run {
                        store.syncWithApplePills(applePills, on: selectedDate)
                    }
                    HapticManager.shared.triggerNotification(type: .success)
                }
                isSyncing = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.medoraBlue, in: Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("Sync with Apple Health"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.medoraDeepBlue)
                    Text(loc.t("Automatically import your active medications."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.medoraBlue)
                }
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.medoraHairline, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Category filter tabs
    
    private var categoryTabs: some View {
        HStack(spacing: 8) {
            ForEach(["All", "Pills", "Tasks"], id: \.self) { category in
                Button {
                    HapticManager.shared.triggerSelection()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        selectedCategory = category
                    }
                } label: {
                    Text(loc.t(category))
                        .font(.system(size: 13, weight: .bold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            Capsule()
                                .fill(selectedCategory == category ? Color.medoraBlue : Color.white)
                        )
                        .foregroundStyle(selectedCategory == category ? .white : Color.medoraDeepBlue)
                        .overlay(
                            Capsule()
                                .stroke(selectedCategory == category ? Color.clear : Color.medoraHairline, lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Tasks Card list
    
    private var filteredTasks: [ChecklistTask] {
        switch selectedCategory {
        case "Pills":
            return selectedTasks.filter { $0.isPill == true }
        case "Tasks":
            return selectedTasks.filter { $0.isPill != true }
        default:
            return selectedTasks
        }
    }

    private var tasksListCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t(selectedCategory == "All" ? "Daily Checklist" : (selectedCategory == "Pills" ? "Medications" : "General Tasks")))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.medoraDeepBlue)
                .padding(.horizontal, 4)
            
            if filteredTasks.isEmpty {
                emptyFilteredTasksView
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredTasks) { task in
                        if task.isPill == true {
                            PillRowCard(task: task) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    store.toggle(task, on: selectedDate)
                                }
                            } onDelete: {
                                if let index = selectedTasks.firstIndex(of: task) {
                                    withAnimation {
                                        store.delete(at: IndexSet(integer: index), on: selectedDate)
                                    }
                                }
                            }
                        } else {
                            TaskRowCard(task: task) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    store.toggle(task, on: selectedDate)
                                }
                            } onDelete: {
                                if let index = selectedTasks.firstIndex(of: task) {
                                    withAnimation {
                                        store.delete(at: IndexSet(integer: index), on: selectedDate)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyFilteredTasksView: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedCategory == "Pills" ? "pills.fill" : "checklist")
                .font(.system(size: 36))
                .foregroundStyle(Color.medoraBlue.opacity(0.4))
            
            Text(loc.t(selectedCategory == "Pills" ? "No medications scheduled." : "No tasks remaining."))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.medoraHairline, lineWidth: 1.2)
        )
    }

    // MARK: FAB button
    
    private var fabButton: some View {
        Button {
            HapticManager.shared.triggerSelection()
            isShowingAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(
                        colors: [Color.medoraBlue, Color.medoraBlue.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(color: Color.medoraBlue.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    // MARK: Calendar card (Classic Month View)

    private var calendarCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.medoraDeepBlue)

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.medoraDeepBlue)
            }

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(for: day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)
    }

    private func dayCell(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let complete = store.isComplete(for: date)
        let hasTasks = store.hasTasks(for: date)

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedDate = date
            }
            isAddFieldFocused = false
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(dayTextColor(isSelected: isSelected, isToday: isToday))

                Circle()
                    .fill(hasTasks ? (complete ? Color.medoraGreen : Color.medoraBlue) : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.medoraBlue : (isToday ? Color.medoraBlue.opacity(0.12) : .clear))
            )
        }
        .buttonStyle(.plain)
    }

    private func dayTextColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return Color.medoraBlue }
        return .primary
    }

    // MARK: Actions & helpers

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) {
            withAnimation(.easeOut(duration: 0.2)) {
                visibleMonth = newMonth
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var monthDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let range = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }

        let firstDay = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in range {
            if let date = calendar.date(byAdding: .day, value: offset - 1, to: firstDay) {
                days.append(date)
            }
        }
        return days
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: visibleMonth)
    }

    private var selectedDateTitle: String {
        if calendar.isDateInToday(selectedDate) {
            return loc.t("Today")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }
}

// MARK: - Subviews & Supporting Views

struct PillRowCard: View {
    let task: ChecklistTask
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(task.isDone ? Color.medoraGreen : pillColor.opacity(0.4), lineWidth: 2)
                        .frame(width: 26, height: 26)
                    
                    if task.isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.medoraGreen)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Circle()
                            .fill(pillColor.opacity(0.12))
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(task.isDone ? .secondary : Color.medoraDeepBlue)
                    .strikethrough(task.isDone, color: .secondary)
                
                HStack(spacing: 6) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(pillColor)
                    Text(task.dosage ?? "1 dose")
                    Text("•")
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(task.timeOfDay ?? "Morning")
                    
                    if task.isSyncedFromHealthKit == true {
                        Text("•")
                        HStack(spacing: 2) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 9))
                            Text("Health")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.medoraBlue.opacity(0.12))
                        .foregroundStyle(Color.medoraBlue)
                        .cornerRadius(6)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .padding(8)
                    .background(Color.red.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(task.isDone ? Color.medoraField.opacity(0.6) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(task.isDone ? Color.clear : Color.medoraHairline, lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(task.isDone ? 0.0 : 0.02), radius: 8, x: 0, y: 4)
    }
    
    private var pillColor: Color {
        guard let hex = task.colorHex else { return Color.medoraBlue }
        return Color(hex: hex) ?? Color.medoraBlue
    }
}

struct TaskRowCard: View {
    let task: ChecklistTask
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(task.isDone ? Color.medoraGreen : Color.medoraBlue.opacity(0.5))
            }
            .buttonStyle(.plain)
            
            Text(task.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .strikethrough(task.isDone, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .padding(8)
                    .background(Color.red.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(task.isDone ? Color.medoraField.opacity(0.6) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(task.isDone ? Color.clear : Color.medoraHairline, lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(task.isDone ? 0.0 : 0.02), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Add Checklist Item Sheet

struct AddChecklistItemSheet: View {
    @ObservedObject var store: ChecklistStore
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    
    @State private var checklistType = 0
    @State private var taskTitle = ""
    
    @State private var pillName = ""
    @State private var pillDosage = ""
    @State private var pillTime = "Morning"
    @State private var pillColorHex = "#4D96FF"
    @State private var scheduleReminder = true
    
    private let pillTimes = ["Morning", "Afternoon", "Evening", "Night", "Bedtime"]
    
    private let colorOptions = [
        ("#FF6B6B", "Coral"),
        ("#4D96FF", "Teal"),
        ("#6BCB77", "Green"),
        ("#FFD93D", "Yellow"),
        ("#9B5DE5", "Purple")
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.medoraBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        Picker("Type", selection: $checklistType) {
                            Text(loc.t("Task")).tag(0)
                            Text(loc.t("Pill")).tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 16)
                        
                        if checklistType == 0 {
                            taskForm
                        } else {
                            pillForm
                        }
                        
                        Button {
                            save()
                        } label: {
                            Text(loc.t("Add to Checklist"))
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(checklistType == 0 ? taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : pillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.horizontal)
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(loc.t("Add Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var taskForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t("Task Description"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.medoraDeepBlue)
                .padding(.leading, 4)
            
            TextField(loc.t("e.g., Drink 8 glasses of water"), text: $taskTitle)
                .glassStyle(isFocused: true)
        }
        .padding(.horizontal)
    }
    
    private var pillForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.t("Pill Name"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .padding(.leading, 4)
                
                TextField(loc.t("e.g., Ibuprofen"), text: $pillName)
                    .glassStyle(isFocused: false)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.t("Dosage"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .padding(.leading, 4)
                
                TextField(loc.t("e.g., 400 mg or 1 tablet"), text: $pillDosage)
                    .glassStyle(isFocused: false)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.t("Time of Day"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .padding(.leading, 4)
                
                Picker("Time of Day", selection: $pillTime) {
                    ForEach(pillTimes, id: \.self) { time in
                        Text(loc.t(time)).tag(time)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 1))
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text(loc.t("Pill Color Theme"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .padding(.leading, 4)
                
                HStack(spacing: 16) {
                    ForEach(colorOptions, id: \.0) { hex, name in
                        Button {
                            pillColorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? Color.medoraBlue)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: pillColorHex == hex ? 3 : 0)
                                        .shadow(radius: pillColorHex == hex ? 2 : 0)
                                )
                                .scaleEffect(pillColorHex == hex ? 1.15 : 1.0)
                                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pillColorHex)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 4)
            }
            
            Toggle(isOn: $scheduleReminder) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.t("Schedule Daily Reminder"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.medoraDeepBlue)
                    Text(loc.t("Get push notifications when it is time to take this pill."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.medoraBlue)
            .padding()
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 1))
        }
        .padding(.horizontal)
    }
    
    private func save() {
        if checklistType == 0 {
            store.addTask(taskTitle, on: selectedDate)
        } else {
            store.addPill(pillName, dosage: pillDosage, timeOfDay: pillTime, colorHex: pillColorHex, on: selectedDate, scheduleReminder: scheduleReminder)
        }
        dismiss()
    }
}

// MARK: - Calendar Export Sheet

struct CalendarExportSheet: View {
    let tasks: [ChecklistTask]
    let date: Date
    @Binding var isExporting: Bool
    let onResult: (CalendarExportResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var localExporting = false

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.medoraBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // Header illustration
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "#FF6B6B") ?? .red, Color(hex: "#FF8E53") ?? .orange],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 72, height: 72)

                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            Text(loc.t("Export to Apple Calendar"))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.medoraDeepBlue)

                            Text(dateString)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)

                        // Task preview list
                        VStack(alignment: .leading, spacing: 8) {
                            Text(loc.t("Tasks to export (\(tasks.count))"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.medoraDeepBlue)
                                .padding(.horizontal, 4)

                            VStack(spacing: 8) {
                                ForEach(tasks) { task in
                                    HStack(spacing: 12) {
                                        if task.isPill == true {
                                            Text("💊")
                                                .font(.system(size: 18))
                                        } else {
                                            Text("✅")
                                                .font(.system(size: 18))
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color.medoraDeepBlue)

                                            if let time = task.timeOfDay ?? (task.isPill == true ? "Morning" : nil) {
                                                Text(timeLabel(for: time))
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.medoraHairline, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 2)

                        // Info note
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Color.medoraBlue)
                            Text(loc.t("Each task will be added as a 30-minute event with a 10-minute reminder."))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.medoraBlue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

                        // Action buttons
                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    localExporting = true
                                    isExporting = true
                                    let result = await CalendarExportManager.shared.exportTasks(tasks, on: date)
                                    isExporting = false
                                    localExporting = false
                                    dismiss()
                                    onResult(result)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if localExporting {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "calendar.badge.plus")
                                    }
                                    Text(localExporting ? loc.t("Exporting…") : loc.t("Export to Calendar"))
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(localExporting)

                            Button {
                                dismiss()
                            } label: {
                                Text(loc.t("Cancel"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.medoraDeepBlue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(localExporting)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func timeLabel(for timeOfDay: String) -> String {
        switch timeOfDay.lowercased() {
        case "morning":          return "8:00 AM – 8:30 AM"
        case "afternoon":        return "1:00 PM – 1:30 PM"
        case "evening":          return "6:00 PM – 6:30 PM"
        case "night", "bedtime": return "9:00 PM – 9:30 PM"
        default:                 return "\(timeOfDay) (30 min)"
        }
    }
}

// MARK: - Export Toast

enum ExportToast: Equatable {
    case success(String)
    case error(String)

    var message: String {
        switch self {
        case .success(let msg), .error(let msg): return msg
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

struct ExportToastView: View {
    let toast: ExportToast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(toast.isSuccess ? Color.medoraGreen : .red)

            Text(toast.message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.medoraDeepBlue)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(toast.isSuccess ? Color.medoraGreen.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1.5)
        )
    }
}

// MARK: - Color Hex Extension


extension Color {
    init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.remove(at: cleanHex.startIndex)
        }
        
        guard cleanHex.count == 6 else {
            return nil
        }
        
        var rgbValue: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgbValue)
        
        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}

#if DEBUG && targetEnvironment(simulator)
#Preview {
    NavigationStack {
        ChecklistView(store: ChecklistStore(), healthStore: HealthStore())
    }
}
#endif
