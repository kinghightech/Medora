//
//  RootView.swift
//  Medora
//
//  Top-level view that shows the onboarding flow until it's complete,
//  then swaps in the main app (with its navigation bar).
//

import SwiftUI

struct RootView: View {
    /// Shared health store so data loaded during onboarding stays available
    /// in the main app.
    @StateObject private var healthStore = HealthStore()

    /// Shared checklist store so tasks added in the Checklist tab show up on
    /// the home screen.
    @StateObject private var checklistStore = ChecklistStore()

    /// The user's name once onboarding finishes; nil while onboarding.
    @State private var userName: String?

    var body: some View {
        ZStack {
            Color(red: 0.9, green: 0.97, blue: 1.0)
                .ignoresSafeArea()

            if let userName {
                MainTabView(userName: userName,
                            healthStore: healthStore,
                            checklistStore: checklistStore)
                    .transition(.opacity)
            } else {
                ContentView(healthStore: healthStore, onComplete: { name in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        userName = name
                    }
                })
            }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
#Preview {
    RootView()
}
#endif
