//
//  RootView.swift
//  Medora
//
//  Top-level view that shows the onboarding flow until it's complete,
//  then swaps in the main app (with its navigation bar). The signed-in
//  profile is persisted, so returning users skip onboarding entirely.
//

import SwiftUI

struct RootView: View {
    /// Deep link flag from the widget — when true, the symptom log sheet
    /// opens automatically.
    @Binding var shouldOpenSymptomLog: Bool

    /// Shared health store so data loaded during onboarding stays available
    /// in the main app.
    @StateObject private var healthStore = HealthStore()

    /// Shared checklist store so tasks added in the Checklist tab show up on
    /// the home screen.
    @StateObject private var checklistStore = ChecklistStore()

    /// Handles secure account creation through Supabase Auth.
    @StateObject private var authStore = AuthStore()

    /// Owns background health-report generation so it survives leaving the
    /// Summarize screen and keeps the generated reports across launches.
    @StateObject private var reportStore = ReportStore()

    /// Persisted across launches; empty while onboarding hasn't finished.
    @AppStorage("medora.user.name") private var storedUserName = ""
    @AppStorage("medora.user.email") private var storedUserEmail = ""

    /// True while we check for a stored Supabase session at launch, so
    /// keychain-restored users don't see onboarding flash by first.
    @State private var isRestoringSession = true

    var body: some View {
        ZStack {
            Color(red: 0.9, green: 0.97, blue: 1.0)
                .ignoresSafeArea()

            if !storedUserName.isEmpty {
                MainTabView(userName: storedUserName,
                            userEmail: storedUserEmail,
                            healthStore: healthStore,
                            checklistStore: checklistStore,
                            authStore: authStore,
                            reportStore: reportStore,
                            shouldOpenSymptomLog: $shouldOpenSymptomLog,
                            onSignOut: signOut)
                    .environmentObject(authStore)
                    .transition(.opacity)
                    .task {
                        // Onboarding only loads health data on the run where
                        // the user connects Apple Health; returning launches
                        // re-query here instead.
                        await healthStore.refreshHealthData()
                        // Ensure we can deliver the "report ready" notification.
                        NotificationManager.shared.requestPermission()
                    }
            } else if isRestoringSession {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.medoraBlue)
            } else {
                ContentView(
                    healthStore: healthStore,
                    onCreateAccount: { name, email, password, age, managing, reminders, cpName, cpEmail, cpRel in
                        try await authStore.signUp(
                            name: name,
                            email: email,
                            password: password,
                            age: age,
                            managing: managing,
                            medicationReminders: reminders,
                            carePartnerName: cpName,
                            carePartnerEmail: cpEmail,
                            carePartnerRelationship: cpRel
                        )
                    },
                    onComplete: { name, email in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            storedUserName = name
                            storedUserEmail = email
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .task(restoreSessionIfNeeded)
    }

    /// Runs once at launch. If onboarding was completed on this device we
    /// already have a stored profile; otherwise check whether a Supabase
    /// session survives (e.g. after a reinstall) before showing onboarding.
    @Sendable
    private func restoreSessionIfNeeded() async {
        let restoredProfile = await authStore.restoreSession()

        guard storedUserName.isEmpty else {
            isRestoringSession = false
            return
        }

        if let profile = restoredProfile, !profile.email.isEmpty {
            storedUserName = profile.fullName.isEmpty ? profile.email : profile.fullName
            storedUserEmail = profile.email
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            isRestoringSession = false
        }
    }

    private func signOut() {
        Task {
            await authStore.signOut()
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            storedUserName = ""
            storedUserEmail = ""
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
#Preview {
    RootView(shouldOpenSymptomLog: .constant(false))
}
#endif
