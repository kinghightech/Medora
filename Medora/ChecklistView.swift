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

// MARK: - Model

/// A single checklist item belonging to one calendar day.
struct ChecklistTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

// MARK: - Store

/// Holds the tasks for every day, keyed by `yyyy-MM-dd`, and persists them to
/// `UserDefaults` as JSON so they survive app launches.
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
        tasksByDay[Self.key(for: date), default: []].append(ChecklistTask(title: trimmed))
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

// MARK: - Checklist screen

struct ChecklistView: View {
    @ObservedObject var store: ChecklistStore
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var newTaskText = ""
    @FocusState private var isAddFieldFocused: Bool

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

    var body: some View {
        ZStack {
            MedoraBackground()

            ScrollView {
                VStack(spacing: 16) {
                    progressCard
                    calendarCard
                    tasksCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(loc.t("Checklist"))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedDateTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(completedCount)/\(selectedTasks.count)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(Color.medoraBlue)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)
                .animation(.easeInOut(duration: 0.25), value: progress)

            Text(progressLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private var progressLabel: String {
        if selectedTasks.isEmpty {
            return loc.t("No tasks yet, add one below.")
        } else if completedCount == selectedTasks.count {
            return loc.t("All done for this day. 🎉")
        } else {
            return "\(Int(progress * 100))% \(loc.t("complete"))"
        }
    }

    // MARK: Calendar

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
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
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

    // MARK: Tasks

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t("Tasks"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.medoraBlue)

                TextField(loc.t("Add a task for this day"), text: $newTaskText)
                    .submitLabel(.done)
                    .focused($isAddFieldFocused)
                    .onSubmit(addTask)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.medoraField)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isAddFieldFocused ? Color.medoraBlue : Color.medoraHairline, lineWidth: 1.5)
            )

            if selectedTasks.isEmpty {
                emptyTasksView
            } else {
                VStack(spacing: 8) {
                    ForEach(selectedTasks) { task in
                        taskRow(task)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private func taskRow(_ task: ChecklistTask) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    store.toggle(task, on: selectedDate)
                }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(task.isDone ? Color.medoraGreen : Color.medoraBlue.opacity(0.5))
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .strikethrough(task.isDone, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                if let index = selectedTasks.firstIndex(of: task) {
                    withAnimation {
                        store.delete(at: IndexSet(integer: index), on: selectedDate)
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.medoraField)
        )
    }

    private var emptyTasksView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 30))
                .foregroundStyle(Color.medoraBlue.opacity(0.5))
            Text(loc.t("No tasks for this day yet."))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: Actions & helpers

    private func addTask() {
        store.addTask(newTaskText, on: selectedDate)
        newTaskText = ""
    }

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

    /// Days to render for `visibleMonth`, padded with `nil` for the leading
    /// blanks so the first day lands under the correct weekday column.
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

#if DEBUG && targetEnvironment(simulator)
#Preview {
    NavigationStack {
        ChecklistView(store: ChecklistStore())
    }
}
#endif
