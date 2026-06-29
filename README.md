# Medora


Medora is a SwiftUI iOS health app designed to help users manage their care plan in one place. It combines onboarding, Apple Health tracking, daily tasks, symptom logging, clinical trial discovery, and an AI assistant for health-related support.

## Features

- **Guided onboarding** to collect user details, health goals, medication reminders, and optional care partner info
- **Apple Health integration** for tracking health metrics like steps, calories, sleep, heart rate, blood pressure, and blood glucose
- **Daily checklist** for recurring tasks and care actions
- **Symptom logging** with a dedicated journal flow and widget deep link support
- **Clinical trials search** powered by ClinicalTrials.gov
- **AI assistant** for health-related guidance and support
- **Localization support** for multiple languages
- **Profile and report views** for managing account info and health summaries

## Screens

- Welcome / onboarding
- Home dashboard
- Checklist
- Health
- Aura AI
- Clinical Trials
- Profile

## Tech Stack

- **Swift**
- **SwiftUI**
- **HealthKit**
- **WidgetKit**
- **Supabase**
- **ClinicalTrials.gov API**
- **Featherless AI API**

## App Flow

1. User opens Medora
2. Onboarding collects:
   - name
   - age
   - conditions being managed
   - Apple Health access
   - account details
   - medication reminders
   - optional care partner info
3. After setup, the app opens into the main tab view
4. Users can track health data, manage tasks, log symptoms, chat with Aura AI, and browse clinical trials

## Widget Support

Medora includes a widget extension that supports a deep link for opening the symptom log:

- `medora://log-symptom`

## Requirements

- Xcode
- iOS device or simulator with HealthKit support
- Supabase account/configuration
- Featherless AI API access

> Note: HealthKit works best on a physical device or a simulator with seeded health data.

## Setup

1. Clone the repository
2. Open `Medora.xcodeproj` in Xcode
3. Configure any required API keys or backend credentials
4. Build and run the app

## Build

```bash
xcodebuild -scheme Medora -configuration Debug build
```

## Notes

- The app uses a light color scheme by default
- Health permissions are requested during onboarding, but users can continue even if access is denied
- Some credentials are currently hardcoded in the codebase and should be moved to secure configuration for production use

## License

Aahish Abbani (I) made most of it but used much help from AI to build the UI

---

If you want, I can next turn this into a **more polished GitHub README** with:
- a stronger project description
- installation steps
- screenshots section
- environment/configuration section
- “How it works” section

Or I can **write the README directly into the repo** for you.
