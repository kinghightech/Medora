//
//  MedoraApp.swift
//  Medora
//
//  Created by Aahish Abbani on 6/11/26.
//

import SwiftUI

@main
struct MedoraApp: App {
    /// When the widget is tapped, it opens `medora://log-symptom` which
    /// sets this flag so the symptom journal sheet opens automatically.
    @State private var shouldOpenSymptomLog = false

    var body: some Scene {
        WindowGroup {
            RootView(shouldOpenSymptomLog: $shouldOpenSymptomLog)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    if url.scheme == "medora" && url.host == "log-symptom" {
                        shouldOpenSymptomLog = true
                    }
                }
        }
    }
}
