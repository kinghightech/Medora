//
//  ClinicalTrialsView.swift
//  Medora
//
//  Lets the user type a location and see nearby upcoming clinical trials
//  from ClinicalTrials.gov.
//

import SwiftUI
import Translation
import CoreLocation

struct ClinicalTrialsView: View {
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var locationManager = LocationManager()

    @AppStorage("medora.last.searched.location") private var lastSearchedLocation = ""
    @AppStorage("medora.last.searched.condition") private var lastSearchedCondition = ""
    @AppStorage("medora.last.searched.radius") private var lastSearchedRadius = 100

    @State private var locationText = ""
    @State private var conditionText = ""
    @State private var radiusMiles = 100
    @State private var trials: [ClinicalTrial] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    
    @State private var locationSuggestions: [GeocodeSuggestion] = []
    @State private var suggestionsTask: Task<Void, Never>? = nil
    @State private var shouldSkipSuggestions = false
    
    @FocusState private var isLocationFocused: Bool
    @FocusState private var isConditionFocused: Bool
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
        .onAppear {
            if !hasSearched {
                if !lastSearchedLocation.isEmpty {
                    shouldSkipSuggestions = true
                    locationText = lastSearchedLocation
                }
                
                if !lastSearchedCondition.isEmpty {
                    conditionText = lastSearchedCondition
                } else if let profile = authStore.currentProfile {
                    conditionText = defaultCondition(from: profile)
                }
                
                radiusMiles = lastSearchedRadius > 0 ? lastSearchedRadius : 100
                
                if !locationText.isEmpty {
                    runSearch()
                }
            }
        }
        .onChange(of: locationText) { _, newText in
            updateSuggestions(for: newText)
        }
        .onChange(of: isConditionFocused) { _, isFocused in
            if isFocused {
                locationSuggestions = []
                if errorMessage == "Please select the correct location below." {
                    errorMessage = nil
                }
            }
        }
        .onChange(of: locationManager.placemark) { _, newPlacemark in
            if let newPlacemark = newPlacemark {
                let city = newPlacemark.locality ?? ""
                let state = newPlacemark.administrativeArea ?? ""
                
                shouldSkipSuggestions = true
                if !city.isEmpty && !state.isEmpty {
                    locationText = "\(city), \(state)"
                } else if !city.isEmpty {
                    locationText = city
                } else if let zip = newPlacemark.postalCode {
                    locationText = zip
                }
                
                if !locationText.isEmpty {
                    runSearch()
                }
            }
        }
        .onChange(of: locationManager.errorMsg) { _, newError in
            if let newError = newError {
                errorMessage = newError
            }
        }
        // Apple's on-device Translation: runs whenever the config changes
        // (new language) or is invalidated (new search results).
        .translationTask(translationConfig) { session in
            await runTranslation(using: session)
        }
        .onChange(of: loc.language) { refreshTranslation() }
    }

    private func defaultCondition(from profile: MedoraProfile?) -> String {
        guard let profile = profile, let firstCondition = profile.managing.first else {
            return ""
        }
        switch firstCondition {
        case "Heart Health": return "Heart Disease"
        case "Diabetes": return "Diabetes"
        case "Cancer": return "Cancer"
        case "Asthma": return "Asthma"
        case "High Blood Pressure": return "Hypertension"
        case "Recovery After Surgery": return "Surgery Recovery"
        case "Mental Health": return "Mental Health"
        case "Chronic Pain": return "Chronic Pain"
        case "Autoimmune Condition": return "Autoimmune"
        default: return ""
        }
    }

    private func requestCurrentLocation() {
        locationManager.requestLocation()
    }

    private func updateSuggestions(for query: String) {
        suggestionsTask?.cancel()
        
        guard !shouldSkipSuggestions else {
            shouldSkipSuggestions = false
            locationSuggestions = []
            return
        }
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            locationSuggestions = []
            return
        }
        
        suggestionsTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            
            let results = await service.getPlacesAutocompleteSuggestions(for: trimmed)
            
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.locationSuggestions = results
            }
        }
    }

    // MARK: - Search input

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t("Find trials near you"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            // Medical Condition field
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.t("Medical Condition"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 10) {
                    Image(systemName: "stethoscope")
                        .foregroundStyle(Color.medoraDeepBlue)

                    TextField(loc.t("e.g. Diabetes, Cancer, Asthma"), text: $conditionText)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($isConditionFocused)
                        .onSubmit {
                            isLocationFocused = true
                        }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.medoraField)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isConditionFocused ? Color.medoraBlue : Color.medoraHairline, lineWidth: 1.5)
                )
            }

            // Location field with GPS button
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.t("Location"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Color.medoraDeepBlue)

                    TextField(loc.t("City, state, or ZIP code"), text: $locationText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($isLocationFocused)
                        .onSubmit(runSearch)
                    
                    if locationManager.isRequesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(action: requestCurrentLocation) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(Color.medoraBlue)
                                .frame(width: 30, height: 30)
                                .background(Color.medoraBlue.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(loc.t("Use Current Location"))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.medoraField)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isLocationFocused ? Color.medoraBlue : Color.medoraHairline, lineWidth: 1.5)
                )
            }
            .zIndex(10)
            .overlay(alignment: .topLeading) {
                if !locationSuggestions.isEmpty && (isLocationFocused || errorMessage == "Please select the correct location below.") {
                    VStack(alignment: .leading, spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(locationSuggestions) { suggestion in
                                    Button {
                                        shouldSkipSuggestions = true
                                        locationText = suggestion.formattedAddress
                                        locationSuggestions = []
                                        isLocationFocused = false
                                        errorMessage = nil
                                        runSearch(with: suggestion)
                                    } label: {
                                        HStack {
                                            Image(systemName: "mappin.circle.fill")
                                                .foregroundStyle(Color.medoraBlue)
                                            Text(suggestion.formattedAddress)
                                                .font(.system(size: 14))
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if suggestion != locationSuggestions.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                    .background(Color.medoraSurface)
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.medoraHairline, lineWidth: 1)
                    )
                    .offset(y: 72)
                    .frame(width: UIScreen.main.bounds.width - 76)
                }
            }

            // Radius Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(loc.t("Search Radius"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(radiusMiles) \(loc.t("miles"))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.medoraBlue)
                }

                Slider(value: Binding(
                    get: { Double(radiusMiles) },
                    set: { radiusMiles = Int($0) }
                ), in: 5...250, step: 5)
                .tint(Color.medoraBlue)
            }
            .padding(.top, 4)

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
            if !conditionText.trimmingCharacters(in: .whitespaces).isEmpty {
                messageView(icon: "stethoscope",
                            tint: Color.medoraDeepBlue,
                            title: loc.t("No trials found"),
                            subtitle: String(format: loc.t("No active clinical trials found for '%@'. Please check your spelling or try another term."), conditionText))
            } else {
                messageView(icon: "magnifyingglass",
                            tint: Color.medoraDeepBlue,
                            title: loc.t("No upcoming trials found"),
                            subtitle: loc.t("Try a nearby city or widen your search."))
            }
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
        isLocationFocused = false
        isConditionFocused = false
        locationSuggestions = []
        
        let queryLoc = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryCond = conditionText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !queryLoc.isEmpty else {
            errorMessage = "Please enter a location."
            trials = []
            hasSearched = true
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        lastSearchedLocation = queryLoc
        lastSearchedCondition = queryCond
        lastSearchedRadius = radiusMiles

        Task {
            let suggestions = await service.getPlacesAutocompleteSuggestions(for: queryLoc)
            
            if suggestions.isEmpty {
                // Try direct geocoding fallback
                do {
                    let coordinate = try await service.geocode(queryLoc)
                    let results = try await service.searchTrials(latitude: coordinate.latitude,
                                                                 longitude: coordinate.longitude,
                                                                 radiusMiles: radiusMiles,
                                                                 condition: queryCond.isEmpty ? nil : queryCond)
                    await MainActor.run {
                        self.trials = results
                        self.isLoading = false
                        self.hasSearched = true
                        refreshTranslation()
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "We couldn't find that location. Try being more specific."
                        self.trials = []
                        self.isLoading = false
                        self.hasSearched = true
                    }
                }
                return
            }
            
            if suggestions.count > 1 {
                await MainActor.run {
                    self.locationSuggestions = suggestions
                    self.errorMessage = "Please select the correct location below."
                    self.isLoading = false
                }
                return
            }
            
            let matched = suggestions.first!
            await MainActor.run {
                self.shouldSkipSuggestions = true
                self.locationText = matched.formattedAddress
            }
            
            do {
                let coordinate = try await service.geocode(matched.formattedAddress)
                let results = try await service.searchTrials(latitude: coordinate.latitude,
                                                             longitude: coordinate.longitude,
                                                             radiusMiles: radiusMiles,
                                                             condition: queryCond.isEmpty ? nil : queryCond)
                await MainActor.run {
                    self.trials = results
                    self.isLoading = false
                    self.hasSearched = true
                    refreshTranslation()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.trials = []
                    self.isLoading = false
                    self.hasSearched = true
                }
            }
        }
    }

    private func runSearch(with suggestion: GeocodeSuggestion) {
        isLocationFocused = false
        isConditionFocused = false
        shouldSkipSuggestions = true
        locationSuggestions = []
        
        let queryCond = conditionText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isLoading = true
        errorMessage = nil
        
        lastSearchedLocation = suggestion.formattedAddress
        lastSearchedCondition = queryCond
        lastSearchedRadius = radiusMiles

        Task {
            do {
                let lat: Double
                let lng: Double
                if suggestion.latitude == 0.0 && suggestion.longitude == 0.0 {
                    let coordinate = try await service.geocode(suggestion.formattedAddress)
                    lat = coordinate.latitude
                    lng = coordinate.longitude
                } else {
                    lat = suggestion.latitude
                    lng = suggestion.longitude
                }
                
                let results = try await service.searchTrials(latitude: lat,
                                                             longitude: lng,
                                                             radiusMiles: radiusMiles,
                                                             condition: queryCond.isEmpty ? nil : queryCond)
                await MainActor.run {
                    self.trials = results
                    self.isLoading = false
                    self.hasSearched = true
                    refreshTranslation()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.trials = []
                    self.isLoading = false
                    self.hasSearched = true
                }
            }
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
