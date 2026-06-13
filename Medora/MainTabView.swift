//
//  MainTabView.swift
//  Medora
//
//  The main app shell shown after onboarding. Provides the bottom
//  navigation bar that switches between the home screen, the daily
//  checklist, and the Clinical Trials section.
//

import SwiftUI

struct MainTabView: View {
    let userName: String
    let userEmail: String
    @ObservedObject var healthStore: HealthStore
    @ObservedObject var checklistStore: ChecklistStore
    @ObservedObject var authStore: AuthStore
    @ObservedObject var reportStore: ReportStore
    @Binding var shouldOpenSymptomLog: Bool
    var onSignOut: () -> Void = {}
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var selectedTab = 0
    private let profileTab = 5

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(userName: userName,
                             checklistStore: checklistStore,
                             shouldOpenSymptomLog: $shouldOpenSymptomLog)
                }
                .tabItem {
                    Label(loc.t("Home"), systemImage: "house.fill")
                }
                .tag(0)

                NavigationStack {
                    ChecklistView(store: checklistStore, healthStore: healthStore)
                }
                .tabItem {
                    Label(loc.t("Checklist"), systemImage: "checklist")
                }
                .tag(1)

                NavigationStack {
                    HealthView(healthStore: healthStore)
                }
                .tabItem {
                    Label(loc.t("Health"), systemImage: "heart.text.square.fill")
                }
                .tag(2)

                NavigationStack {
                    AIChatView(healthStore: healthStore,
                               authStore: authStore,
                               checklistStore: checklistStore,
                               reportStore: reportStore)
                        .navigationTitle(loc.t("Aura AI"))
                }
                .tabItem {
                    Label(loc.t("Aura AI"), systemImage: "sparkles")
                }
                .tag(3)

                NavigationStack {
                    ClinicalTrialsView()
                }
                .tabItem {
                    Label(loc.t("Trials"), systemImage: "cross.case.fill")
                }
                .tag(4)

                NavigationStack {
                    ProfileView(userName: userName,
                                userEmail: userEmail,
                                reportStore: reportStore,
                                onSignOut: onSignOut)
                }
                .tabItem {
                    Label(loc.t("Profile"), systemImage: "person.crop.circle.fill")
                }
                .tag(profileTab)
            }
            .tint(Color.medoraBlue)

            if let report = reportStore.lastCompleted {
                ReportReadyBanner(report: report) {
                    selectedTab = profileTab
                    withAnimation { reportStore.lastCompleted = nil }
                } onDismiss: {
                    withAnimation { reportStore.lastCompleted = nil }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: reportStore.lastCompleted)
        // Auto-dismiss the banner after a few seconds.
        .task(id: reportStore.lastCompleted?.id) {
            guard reportStore.lastCompleted != nil else { return }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            withAnimation { reportStore.lastCompleted = nil }
        }
        // Tapping a "report ready" notification routes here.
        .onReceive(NotificationCenter.default.publisher(for: .medoraOpenReports)) { _ in
            selectedTab = profileTab
            withAnimation { reportStore.lastCompleted = nil }
        }
    }
}

// MARK: - In-app "report ready" banner

private struct ReportReadyBanner: View {
    let report: HealthReport
    var onTap: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Report ready")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("Tap to view it on your Profile")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer(minLength: 8)

            // Standalone button so the X doesn't also trigger the row tap.
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.medoraBlue, Color(red: 0.38, green: 0.2, blue: 0.9)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(color: Color.medoraBlue.opacity(0.35), radius: 14, x: 0, y: 8)
        // Row-level tap so it doesn't nest with the dismiss button.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Home

/// Landing screen: greets the user and surfaces today's health metrics and
/// checklist tasks at a glance.
private struct HomeView: View {
    let userName: String
    @ObservedObject var checklistStore: ChecklistStore
    @Binding var shouldOpenSymptomLog: Bool
    @ObservedObject private var loc = LocalizationManager.shared

    private let today = Date()
    @State private var isShowingSymptomLog = false

    private var greeting: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? loc.t("Welcome back") : "\(loc.t("Welcome")), \(trimmed)"
    }

    private var todaysTasks: [ChecklistTask] {
        checklistStore.tasks(for: today)
    }

    var body: some View {
        ZStack {
            MedoraBackground()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    symptomsCard
                    tasksCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Medora")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingSymptomLog) {
            NavigationStack {
                SymptomLogView()
            }
        }
        .onChange(of: shouldOpenSymptomLog) { newValue in
            if newValue {
                isShowingSymptomLog = true
                shouldOpenSymptomLog = false
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            Text(greeting)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Text(todayLabel)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: today)
    }

    // MARK: Today's tasks

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(loc.t("Today's Tasks"))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                if !todaysTasks.isEmpty {
                    Text("\(todaysTasks.filter(\.isDone).count)/\(todaysTasks.count)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if todaysTasks.isEmpty {
                emptyTasksView
            } else {
                VStack(spacing: 8) {
                    ForEach(todaysTasks) { task in
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
                    checklistStore.toggle(task, on: today)
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
            Text(loc.t("No tasks for today yet."))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(loc.t("Add tasks in the Checklist tab and they'll appear here."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var symptomsCard: some View {
        Button {
            isShowingSymptomLog = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.medoraBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.t("Record any symptoms"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text(loc.t("Type or dictate how you are feeling"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG && targetEnvironment(simulator)
#Preview {
    MainTabView(userName: "Alex",
                userEmail: "alex@example.com",
                healthStore: HealthStore(),
                checklistStore: ChecklistStore(),
                authStore: AuthStore(),
                reportStore: ReportStore(),
                shouldOpenSymptomLog: .constant(false))
}
#endif
