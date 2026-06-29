# Medora

Medora is an iOS app I built to help people keep their health stuff in one place. The app brings together care plans, Apple Health data, daily tasks, symptom logging, clinical trial search, and an AI assistant called Aura.

The main idea was to make something that feels simple to use, especially for someone managing a condition or trying to stay on top of their care.

## Features

* Onboarding for basic info, health goals, medications, and optional care partner details
* Apple Health support for things like steps, calories, sleep, heart rate, blood pressure, and blood glucose
* Daily checklist for reminders, routines, and care tasks
* Symptom log with a journal-style flow
* Widget deep link for quickly opening the symptom logger
* Clinical trial search using ClinicalTrials.gov
* Aura AI assistant for health-related questions and support
* Profile and report pages for account info and health summaries
* Localization support for multiple languages

## Screens

* Welcome / onboarding
* Home dashboard
* Checklist
* Health
* Aura AI
* Clinical Trials
* Profile

## Tech Stack

* Swift
* SwiftUI
* HealthKit
* WidgetKit
* Supabase
* ClinicalTrials.gov API
* Featherless AI API

## How It Works

When a user first opens Medora, they go through onboarding. This collects basic details like their name, age, conditions they are managing, Apple Health permissions, account info, medication reminders, and optional care partner information.

After onboarding, the app opens into the main tab view. From there, users can check their health data, manage daily tasks, log symptoms, talk with Aura, and look through clinical trials.

## Widget Support

Medora includes a widget extension that can open the symptom log directly with this deep link:

```text
medora://log-symptom
```

## Requirements

* Xcode
* iOS device or simulator with HealthKit support
* Supabase project/configuration
* Featherless AI API access

HealthKit works best on a real iPhone, but a simulator can work too if it has seeded health data.

## Setup

1. Clone the repo
2. Open `Medora.xcodeproj` in Xcode
3. Add the needed API keys and backend config
4. Build and run the app

## Build

```bash
xcodebuild -scheme Medora -configuration Debug build
```

## Notes

* The app uses a light color scheme by default
* Health permissions are asked for during onboarding, but users can still continue if they deny access
* Some credentials are still hardcoded right now, so they should definetly be moved into secure config before production
* This is still a work in progress, so some parts may need cleanup or refinning

## License / Credit

Made by Aahish Abbani.

I built most of the app myself, but used AI for help with parts of the UI, structure, and debugging.
