//
//  ClinicalTrialsView.swift
//  Medora
//
//  Lets the user type a location and see nearby upcoming clinical trials
//  from ClinicalTrials.gov.
//

import SwiftUI
import Translation

struct ClinicalTrialsView: View {
    @State private var locationText = ""
    @State private var trials: [ClinicalTrial] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @FocusState private var isSearchFocused: Bool
    @ObservedObject private var loc = LocalizationManager.shared

    // On-device translation of the live (English) trial text.
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translatedText: [String: String] = [:]

    private let service = ClinicalTrialsService()

    var body: some View {
        ZStack {
            MedoraBackground()

            VStack(spacing: 16) {
                searchCard

                resultsArea
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .navigationTitle(loc.t("Clinical Trials"))
        .navigationBarTitleDisplayMode(.large)
        // Apple's on-device Translation: runs whenever the config changes
        // (new language) or is invalidated (new search results).
        .translationTask(translationConfig) { session in
            await runTranslation(using: session)
        }
        .onChange(of: loc.language) { refreshTranslation() }
    }

    // MARK: - Search input

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.t("Find trials near you"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(Color.medoraDeepBlue)

                TextField(loc.t("City, state, or ZIP code"), text: $locationText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit(runSearch)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.medoraField)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSearchFocused ? Color.medoraBlue : Color.medoraHairline, lineWidth: 1.5)
            )

            Button(action: runSearch) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(isLoading ? loc.t("Searching…") : loc.t("Search"))
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading || locationText.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(locationText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        if let errorMessage {
            messageView(icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: loc.t("Something went wrong"),
                        subtitle: errorMessage)
        } else if isLoading {
            Spacer()
            ProgressView(loc.t("Looking for trials…"))
            Spacer()
        } else if hasSearched && trials.isEmpty {
            messageView(icon: "magnifyingglass",
                        tint: Color.medoraDeepBlue,
                        title: loc.t("No upcoming trials found"),
                        subtitle: loc.t("Try a nearby city or widen your search."))
        } else if !trials.isEmpty {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(trials) { trial in
                        TrialCard(trial: trial, translations: translatedText)
                    }
                }
                .padding(.bottom, 12)
            }
        } else {
            messageView(icon: "cross.case.fill",
                        tint: Color.medoraDeepBlue,
                        title: loc.t("Search for nearby trials"),
                        subtitle: loc.t("Enter your location to see upcoming and recruiting clinical trials from ClinicalTrials.gov."))
        }
    }

    private func messageView(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func runSearch() {
        isSearchFocused = false
        let query = locationText
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let results = try await service.searchTrials(near: query)
                trials = results
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                trials = []
            }
            hasSearched = true
            isLoading = false
            refreshTranslation()
        }
    }

    // MARK: - On-device translation

    /// Translated string for the live trial text, falling back to the original.
    private func translated(_ source: String) -> String {
        translatedText[source] ?? source
    }

    /// Kicks (or re-kicks) the translation task for the current language + results.
    private func refreshTranslation() {
        guard loc.language != .english else {
            translatedText = [:]
            translationConfig = nil
            return
        }
        let newConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: loc.language.localeLanguage
        )
        if translationConfig == newConfig {
            // Same language, new results — re-run the existing task.
            translationConfig?.invalidate()
        } else {
            translationConfig = newConfig
        }
    }

    /// Batch-translates every visible trial title and condition on-device.
    @MainActor
    private func runTranslation(using session: TranslationSession) async {
        var sources = Set<String>()
        for trial in trials {
            sources.insert(trial.title)
            trial.conditions.forEach { sources.insert($0) }
        }
        guard !sources.isEmpty else { return }

        do {
            // Downloads the language model on first use (system-managed UI).
            try await session.prepareTranslation()
            let requests = sources.map { TranslationSession.Request(sourceText: $0) }
            let responses = try await session.translations(from: requests)

            var map: [String: String] = [:]
            for response in responses {
                map[response.sourceText] = response.targetText
            }
            translatedText = map
        } catch {
            // Unsupported pairing or download declined — keep English.
            translatedText = [:]
        }
    }
}

// MARK: - Trial card

private struct TrialCard: View {
    let trial: ClinicalTrial
    var translations: [String: String] = [:]
    @ObservedObject private var loc = LocalizationManager.shared

    /// On-device translation of live trial text, falling back to the original.
    private func tr(_ source: String) -> String {
        translations[source] ?? source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(tr(trial.title))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                statusBadge
            }

            if !trial.conditions.isEmpty {
                Label(trial.conditions.prefix(3).map(tr).joined(separator: ", "),
                      systemImage: "stethoscope")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let location = trial.nearestLocation {
                Label(location, systemImage: "mappin.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let url = trial.url {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(loc.t("View on ClinicalTrials.gov"))
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.medoraBlue)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
    }

    private var statusBadge: some View {
        Text(trial.statusLabel)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.14), in: Capsule())
    }

    private var badgeColor: Color {
        switch trial.status {
        case "RECRUITING":              return Color.medoraGreen
        case "NOT_YET_RECRUITING":      return Color.medoraBlue
        default:                        return Color.medoraDeepBlue
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
#Preview {
    NavigationStack {
        ClinicalTrialsView()
    }
}
#endif
