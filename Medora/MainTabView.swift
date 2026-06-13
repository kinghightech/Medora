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
    var onSignOut: () -> Void = {}
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(userName: userName,
                         checklistStore: checklistStore)
            }
            .tabItem {
                Label(loc.t("Home"), systemImage: "house.fill")
            }

            NavigationStack {
                ChecklistView(store: checklistStore, healthStore: healthStore)
            }
            .tabItem {
                Label(loc.t("Checklist"), systemImage: "checklist")
            }

            NavigationStack {
                HealthView(healthStore: healthStore)
            }
            .tabItem {
                Label(loc.t("Health"), systemImage: "heart.text.square.fill")
            }

            NavigationStack {
                AIChatView(healthStore: healthStore, authStore: authStore, checklistStore: checklistStore)
                    .navigationTitle(loc.t("Aura AI"))
            }
            .tabItem {
                Label(loc.t("Aura AI"), systemImage: "sparkles")
            }

            NavigationStack {
                ClinicalTrialsView()
            }
            .tabItem {
                Label(loc.t("Trials"), systemImage: "cross.case.fill")
            }

            NavigationStack {
                ProfileView(userName: userName, userEmail: userEmail, onSignOut: onSignOut)
            }
            .tabItem {
                Label(loc.t("Profile"), systemImage: "person.crop.circle.fill")
            }
        }
        .tint(Color.medoraBlue)
    }
}

// MARK: - Home

/// Landing screen: greets the user and surfaces today's health metrics and
/// checklist tasks at a glance.
private struct HomeView: View {
    let userName: String
    @ObservedObject var checklistStore: ChecklistStore
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
                authStore: AuthStore())
}
#endif
