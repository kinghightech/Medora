# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Medora** is an iOS health app built in SwiftUI that integrates health tracking, clinical trial discovery, and AI-powered health recommendations. The app uses Supabase for authentication and backend services, HealthKit for health data, and Featherless AI for conversational features.

### Key Features
- **Onboarding flow**: Captures user demographics, care partner info, and medication reminders before entering the app
- **Home screen**: Displays health metrics (steps, calories, sleep, heart rate, blood pressure, blood glucose) from HealthKit
- **Daily checklist**: Persistent task list synced across sessions
- **Clinical trials**: Searches and displays clinical trials from ClinicalTrials.gov
- **AI assistant**: Chat interface powered by Featherless AI (llama 3.1 8B)
- **Localization**: Multi-language support via LocalizationManager

## Architecture & Structure

### Navigation Flow
```
MedoraApp (entry point)
└── RootView
    ├── ContentView (onboarding, shown until userName is set)
    │   └── Requests HealthKit permissions and collects user data
    └── MainTabView (main app, shown after onboarding)
        ├── HomeView (uses HealthStore)
        ├── ChecklistView (uses ChecklistStore)
        ├── AIChatView (uses FeatherlessAIClient)
        └── ClinicalTrialsView (uses ClinicalTrialsService)
```

### State Management
- **AuthStore**: Handles Supabase signup and stores current user profile
- **HealthStore**: Manages HealthKit queries and caches summary data (calories, steps, sleep, heart rate, blood pressure, blood glucose)
- **ChecklistStore**: Persistent task list (non-Supabase, likely UserDefaults-based)
- **LocalizationManager**: Singleton managing string translations across the app

### Key Classes & Services

**SupabaseClient.swift**: Global `supabase` instance initialized with credentials
- Supabase URL: `https://konkupewlocdjpznpgac.supabase.co`
- Used for Auth and profile metadata

**HealthStore (healthstore.swift)**:
- Wraps HealthKit queries for common metrics
- `requestAccessAndLoadData()`: First-time authorization + data load
- `refreshHealthData()`: Re-query all metrics
- Returns "No data available" for missing metrics (non-blocking fallback)

**FeatherlessAIClient.swift**:
- HTTP client for Featherless AI API (llama 3.1 8B)
- Temperature: 0.4, max tokens: 900
- Message history passed per request (stateless)

**ClinicalTrialsService.swift**: Queries ClinicalTrials.gov API

### View Hierarchy
- **ContentView.swift**: Onboarding wizard (longest file, 37KB)
- **MainTabView.swift**: Post-onboarding tab shell (Home, Checklist, AI, Trials)
- **AIChatView.swift**: Chat UI with message history
- **ChecklistView.swift**: Task list editor
- **ClinicalTrialsView.swift**: Trial search results
- **ProfileView.swift**: User profile display
- **Localization.swift**: Localizable strings + LocalizationManager singleton

## Build & Run

### Requirements
- **Xcode 26.5** or later
- **iOS 14+** target (check Info.plist; may require iOS 15+ for HealthKit)
- Swift Package Manager (SPM) for Supabase dependency
- Physical device or simulator with HealthKit support (HealthKit doesn't work in all simulators)

### Build from Command Line
```bash
xcodebuild -scheme Medora -configuration Debug build
```

### Run on Simulator
```bash
xcodebuild -scheme Medora -configuration Debug -sdk iphonesimulator build
open -a Simulator
xcodebuild -scheme Medora -configuration Debug -sdk iphonesimulator install
```

### Run on Device
```bash
xcodebuild -scheme Medora -configuration Debug build-for-testing -destination 'generic/platform=iOS'
xcodebuild -scheme Medora -configuration Debug -destination 'id=<DEVICE_UDID>' install
```

### Open in Xcode
```bash
xed Medora.xcodeproj
```

## Dependencies

### Swift Package Manager
- **supabase-swift**: Supabase authentication and client library
  - Managed in `Medora.xcodeproj/project.pbxproj`
  - Add/update via Xcode: File → Add Packages → `https://github.com/supabase/supabase-swift`

### System Frameworks
- **SwiftUI**: UI framework
- **HealthKit**: Health data queries
- **Combine**: Reactive data binding
- **Foundation**: Networking, data encoding

## Important Notes

### HealthKit Behavior
- Authorization is **non-blocking**: if the request errors or is denied, the user still enters the app with "No data available" for each metric
- Per-metric queries use `try?` to isolate individual data-type failures
- HealthKit permission prompt is shown once; denying it won't gate onboarding but will show no data
- Empty metrics (no data recorded yet) return nil gracefully, not errors

### Sensitive Credentials
- Supabase URL and publishable key are hardcoded in `SupabaseClient.swift`
- Featherless AI key is hardcoded in `FeatherlessAIClient.swift`
- These should be moved to a configuration file or environment variables for production (not checked into git)

### Simulator Limitations
- HealthKit queries work on simulator but require pre-seeded data (use the Health app to add sample data)
- Some device-specific features (certain biometric types) may not be available on simulator
- Consider testing on a physical device for accurate health data behavior

## Common Development Tasks

### Adding a New HealthKit Metric
1. Add the metric string to `HealthDataSummary` struct in `healthstore.swift`
2. Add a query case in `HealthStore.loadHealthData()`
3. Update the UI in the relevant view (likely `HomeView`)
4. Add localized label in `Localization.swift`

### Modifying Onboarding Flow
1. Edit `ContentView.swift` (largest file; consider breaking into sub-views if it grows further)
2. Update the `onCreateAccount` closure signature in `RootView` if adding new fields
3. Ensure new fields are added to Supabase user metadata in `AuthStore.signUp()`

### Adding a New Tab
1. Add a new `NavigationStack` with wrapped view in `MainTabView.swift`
2. Add corresponding `.tabItem` with label and icon
3. Create the view file in the root Medora folder
4. Add UI strings to `Localization.swift`

### Testing the AI Chat
- Verify Featherless API key in `FeatherlessAIClient.swift` is valid
- Ensure network connectivity (API calls are made to `https://api.featherless.ai/v1/chat/completions`)
- Check that message format matches Featherless OpenAI-compatible API spec
- Temperature 0.4 keeps responses focused; adjust in FeatherlessAIConfig if needed

### Testing Clinical Trials Search
- ClinicalTrials.gov API is public; no authentication required
- Verify `ClinicalTrialsService` request format matches API schema
- Test with common conditions (e.g., "diabetes", "hypertension")

## Testing Notes

- No dedicated test targets are currently set up
- Manual testing on device recommended due to HealthKit interactions
- Console output may include unrelated Apple system noise (TUIPredictionViewCell constraints, RBS entitlements, RTIInputSystemClient) — these are not app bugs
- Run on both simulator and physical device to catch HealthKit-specific issues

## Git Workflow

Recent commits show feature-driven development:
- `onboarding` — onboarding flow implementation
- `supabase` — Supabase integration
- Earlier commits — foundational app structure

Keep commits feature-scoped and descriptive. The app uses a light theme by default (`preferredColorScheme(.light)` in `MedoraApp`).

## Debugging Tips

- Xcode Console: Watch for HealthKit authorization logs and API response errors
- Instruments: Use Core Data or Networking templates if needed for performance profiling
- Health app: Manually add sample health data to test queries on simulator
- FeatherlessAIClient errors: Check network connectivity and API key validity; error messages are user-facing
