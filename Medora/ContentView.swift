//
//  ContentView.swift
//  Medora
//
//  Onboarding flow. ContentView owns the form state and step machine;
//  each screen is its own small view so SwiftUI only re-renders the
//  screen being edited.
//

import SwiftUI

// MARK: - Onboarding model

fileprivate enum OnboardingField: Hashable {
    case firstName
    case lastName
    case age
    case email
    case password
    case confirmPassword
    case cpName
    case cpEmail
}

fileprivate enum OnboardingStep: Int, CaseIterable {
    case welcome            // Screen 1: Welcome to Medora
    case name               // Screen 2: What should we call you?
    case age                // Screen 3: How old are you?
    case managing           // Screen 4: What are you currently managing?
    case healthPermission   // Screen 5: Connect your Apple Health data
    case account            // Screen 6: Where should we save your progress?
    case reminders          // Screen 7: Would you like medication reminders?
    case carePartner        // Screen 8: Add a care partner (optional)
    case completed          // Screen 9: You're all set

    var progress: Double {
        self == .completed ? 1 : Double(rawValue + 1) / Double(Self.allCases.count)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}

fileprivate enum OnboardingValidation {
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".")
    }

    static func isValidPassword(_ password: String) -> Bool {
        password.count >= 8
    }
}

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var healthStore: HealthStore

    /// Called when the user completes onboarding and registers their account.
    var onCreateAccount: (
        _ name: String,
        _ email: String,
        _ password: String,
        _ age: Int?,
        _ managing: [String],
        _ reminders: Bool,
        _ carePartnerName: String?,
        _ carePartnerEmail: String?,
        _ carePartnerRelationship: String?
    ) async throws -> Void = { _, _, _, _, _, _, _, _, _ in }

    /// Called when onboarding finishes and we transition to the main app.
    var onComplete: (String, String) -> Void = { _, _ in }

    // MARK: State

    @State private var step: OnboardingStep = .welcome
    @FocusState private var focusedField: OnboardingField?

    // Screen 2: Name
    @State private var firstName = ""
    @State private var lastName = ""

    // Screen 3: Age
    @State private var ageString = ""

    // Screen 4: Managing conditions
    private let availableConditions = [
        "Heart Health", "Diabetes", "Cancer", "Asthma",
        "High Blood Pressure", "Recovery After Surgery",
        "Mental Health", "Chronic Pain", "Autoimmune Condition", "Other"
    ]
    @State private var selectedConditions: Set<String> = []

    // Screen 6: Account
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    // Screen 7: Medication reminders
    @State private var wantsReminders: Bool? = nil

    // Screen 8: Care partner
    @State private var cpName = ""
    @State private var cpEmail = ""
    @State private var cpRelationship = "Spouse"
    private let relationships = ["Spouse", "Parent", "Caregiver", "Family Member"]

    // Loader & errors
    @State private var isSubmitting = false
    @State private var onboardingError: String? = nil

    // MARK: Validation

    private var cleanFullName: String {
        let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return l.isEmpty ? f : "\(f) \(l)"
    }

    private var parsedAge: Int? {
        Int(ageString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isNameValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isAgeValid: Bool {
        if let age = parsedAge, age >= 13 && age < 120 {
            return true
        }
        return false
    }

    private var isAccountValid: Bool {
        OnboardingValidation.isValidEmail(email)
            && OnboardingValidation.isValidPassword(password)
            && password == confirmPassword
    }

    private var isCarePartnerValid: Bool {
        let nameTrim = cpName.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailTrim = cpEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if nameTrim.isEmpty && emailTrim.isEmpty { return true }
        return !nameTrim.isEmpty && OnboardingValidation.isValidEmail(emailTrim)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Image("onboardingbackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            // Soft overlay for readability; tapping the margins dismisses the keyboard.
            Color.white.opacity(0.12)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                }

            VStack(spacing: 0) {
                OnboardingHeader(
                    progress: step.progress,
                    showsBack: step != .welcome && step != .completed,
                    onBack: goBack
                )
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

                ScrollView {
                    stepContent
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.immediately)

                bottomButtons
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch step {
            case .welcome:
                WelcomeStep()
            case .name:
                NameStep(firstName: $firstName, lastName: $lastName, focusedField: $focusedField)
            case .age:
                AgeStep(ageString: $ageString, focusedField: $focusedField)
            case .managing:
                ManagingStep(conditions: availableConditions, selected: $selectedConditions)
            case .healthPermission:
                HealthPermissionStep()
            case .account:
                AccountStep(email: $email,
                            password: $password,
                            confirmPassword: $confirmPassword,
                            focusedField: $focusedField)
            case .reminders:
                RemindersStep(wantsReminders: $wantsReminders)
            case .carePartner:
                CarePartnerStep(name: $cpName,
                                email: $cpEmail,
                                selectedRelationship: $cpRelationship,
                                relationships: relationships,
                                focusedField: $focusedField)
            case .completed:
                CompletedStep(error: onboardingError)
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
    }

    // MARK: Pinned bottom button bar

    @ViewBuilder
    private var bottomButtons: some View {
        VStack(spacing: 10) {
            switch step {
            case .welcome:
                primaryButton("Get Started") {
                    advanceStep(to: .name)
                }

            case .name:
                primaryButton("Continue") {
                    advanceStep(to: .age)
                }
                .disabled(!isNameValid)

            case .age:
                primaryButton("Continue") {
                    advanceStep(to: .managing)
                }
                .disabled(!isAgeValid)

            case .managing:
                primaryButton("Continue") {
                    advanceStep(to: .healthPermission)
                }

            case .healthPermission:
                Button(action: requestHealthAccess) {
                    HStack(spacing: 10) {
                        if healthStore.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(healthStore.isLoading ? "Connecting" : "Connect Apple Health")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(healthStore.isLoading)

                secondaryButton("Maybe Later") {
                    advanceStep(to: .account)
                }

            case .account:
                primaryButton("Continue") {
                    advanceStep(to: .reminders)
                }
                .disabled(!isAccountValid)

            case .reminders:
                primaryButton("Continue") {
                    if wantsReminders == true {
                        NotificationManager.shared.requestPermission()
                    }
                    advanceStep(to: .carePartner)
                }
                .disabled(wantsReminders == nil)

            case .carePartner:
                primaryButton("Add Care Partner") {
                    advanceStep(to: .completed)
                }
                .disabled(!isCarePartnerValid || cpName.isEmpty)

                secondaryButton("Skip") {
                    cpName = ""
                    cpEmail = ""
                    advanceStep(to: .completed)
                }

            case .completed:
                Button(action: submitRegistrationAndComplete) {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isSubmitting ? "Creating account..." : "Scan Document")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSubmitting)
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    // MARK: Actions

    private func advanceStep(to nextStep: OnboardingStep) {
        focusedField = nil
        HapticManager.shared.triggerImpact(style: .medium)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            step = nextStep
        }
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        focusedField = nil
        HapticManager.shared.triggerImpact(style: .light)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            step = previous
        }
    }

    private func requestHealthAccess() {
        Task {
            _ = await healthStore.requestAccessAndLoadData()
            // Even if they deny, we advance to the next step (.account).
            advanceStep(to: .account)
        }
    }

    private func submitRegistrationAndComplete() {
        isSubmitting = true
        onboardingError = nil

        let finalName = cleanFullName
        let finalEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let finalPassword = password
        let finalAge = parsedAge
        let finalManaging = Array(selectedConditions)
        let finalReminders = wantsReminders ?? false
        let trimmedCpName = cpName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCpName = trimmedCpName.isEmpty ? nil : trimmedCpName
        let finalCpEmail = trimmedCpName.isEmpty ? nil : cpEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCpRelationship = trimmedCpName.isEmpty ? nil : cpRelationship

        Task { @MainActor in
            do {
                try await onCreateAccount(
                    finalName,
                    finalEmail,
                    finalPassword,
                    finalAge,
                    finalManaging,
                    finalReminders,
                    finalCpName,
                    finalCpEmail,
                    finalCpRelationship
                )
                isSubmitting = false
                HapticManager.shared.triggerNotification(type: .success)
                // Sign up succeeded, notify parent to complete onboarding
                onComplete(finalName, finalEmail)
            } catch {
                isSubmitting = false
                HapticManager.shared.triggerNotification(type: .error)
                onboardingError = error.localizedDescription
            }
        }
    }
}

// MARK: - Header (back button + progress)

private struct OnboardingHeader: View {
    let progress: Double
    let showsBack: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if showsBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.medoraDeepBlue)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.5), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Back")
                .transition(.opacity)
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.35))

                    Capsule()
                        .fill(Color.medoraBlue)
                        .frame(width: max(12, geo.size.width * progress))
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: progress)
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: 44)
    }
}

// MARK: - Screen 1: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Image("MedoraLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.medoraBlue.opacity(0.18), radius: 14, x: 0, y: 8)
                .padding(.top, 20)

            VStack(spacing: 12) {
                Text("Welcome to Medora")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.medoraDeepBlue)

                Text("Your doctor's instructions, turned into a daily plan.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))
                    .padding(.horizontal, 10)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "heart.text.square.fill", text: "Health tracking that fills itself in")
                FeatureRow(icon: "pills.fill", text: "Reminders for the moments that matter")
                FeatureRow(icon: "person.2.fill", text: "Keep someone you trust in the loop")
            }
            .glassCard()

            Text("We'll set up your care profile in under a minute.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Screen 2: Name

private struct NameStep: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @FocusState.Binding var focusedField: OnboardingField?

    var body: some View {
        VStack(spacing: 28) {
            OnboardingTitle(title: "What should we call you?",
                            subtitle: "We'll personalize your care plan and reminders.")

            VStack(spacing: 14) {
                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)
                    .focused($focusedField, equals: .firstName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .lastName }
                    .glassStyle(isFocused: focusedField == .firstName)

                TextField("Last Name", text: $lastName)
                    .textContentType(.familyName)
                    .focused($focusedField, equals: .lastName)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .glassStyle(isFocused: focusedField == .lastName)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Screen 3: Age

private struct AgeStep: View {
    @Binding var ageString: String
    @FocusState.Binding var focusedField: OnboardingField?

    /// True once the user has typed an age that is below the 13+ minimum.
    private var isUnderage: Bool {
        if let age = Int(ageString.trimmingCharacters(in: .whitespacesAndNewlines)), age > 0, age < 13 {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 28) {
            OnboardingTitle(title: "How old are you?",
                            subtitle: "This helps us personalize recommendations and reminders.")

            TextField("Age", text: $ageString)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .age)
                .glassStyle(isFocused: focusedField == .age)
                .padding(.horizontal, 4)
                .onChange(of: ageString) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(3))
                    if filtered != newValue {
                        ageString = filtered
                    }
                }

            if isUnderage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("You must be 13 or older to use Medora.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isUnderage)
    }
}

// MARK: - Screen 4: Managing conditions

private struct ManagingStep: View {
    let conditions: [String]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(spacing: 24) {
            OnboardingTitle(title: "What are you currently managing?",
                            subtitle: "Select anything that applies.")

            VStack(spacing: 8) {
                ForEach(conditions, id: \.self) { condition in
                    SelectableRow(title: condition,
                                  isSelected: selected.contains(condition)) {
                        if selected.contains(condition) {
                            selected.remove(condition)
                        } else {
                            selected.insert(condition)
                        }
                    }
                }
            }

            Text("Don't worry — you can always update this later.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }
}

// MARK: - Screen 5: Apple Health

private struct HealthPermissionStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.medoraBlue)
                .shadow(color: Color.medoraBlue.opacity(0.18), radius: 10, x: 0, y: 6)
                .padding(.top, 16)

            OnboardingTitle(title: "Connect your Apple Health data",
                            subtitle: "Let Medora automatically track progress toward your care goals.")

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "flame.fill", text: "Daily movement & active energy")
                FeatureRow(icon: "figure.walk", text: "Steps walked")
                FeatureRow(icon: "bed.double.fill", text: "Sleep & rest quality")
                FeatureRow(icon: "heart.fill", text: "Heart rate, blood pressure & glucose vitals")
            }
            .glassCard()

            Label("Your health data stays private and under your control.", systemImage: "lock.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Screen 6: Account

private struct AccountStep: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmPassword: String
    @FocusState.Binding var focusedField: OnboardingField?

    var body: some View {
        VStack(spacing: 28) {
            OnboardingTitle(title: "Where should we save your progress?",
                            subtitle: "Create your account so your care plan stays synced and secure.")

            VStack(spacing: 14) {
                TextField("Email Address", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .glassStyle(isFocused: focusedField == .email)

                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirmPassword }
                    .glassStyle(isFocused: focusedField == .password)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirmPassword)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .glassStyle(isFocused: focusedField == .confirmPassword)
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                RequirementRow(text: "At least 8 characters",
                               satisfied: OnboardingValidation.isValidPassword(password))
                RequirementRow(text: "Passwords match",
                               satisfied: !password.isEmpty && password == confirmPassword)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Screen 7: Medication reminders

private struct RemindersStep: View {
    @Binding var wantsReminders: Bool?

    var body: some View {
        VStack(spacing: 28) {
            OnboardingTitle(title: "Would you like medication reminders?",
                            subtitle: "We'll help you stay on track.")

            VStack(spacing: 12) {
                SelectableRow(title: "Yes, remind me",
                              isSelected: wantsReminders == true,
                              indicator: .radio) {
                    wantsReminders = true
                }
                SelectableRow(title: "Not right now",
                              isSelected: wantsReminders == false,
                              indicator: .radio) {
                    wantsReminders = false
                }
            }
        }
    }
}

// MARK: - Screen 8: Care partner

private struct CarePartnerStep: View {
    @Binding var name: String
    @Binding var email: String
    @Binding var selectedRelationship: String
    let relationships: [String]
    @FocusState.Binding var focusedField: OnboardingField?

    var body: some View {
        VStack(spacing: 28) {
            OnboardingTitle(title: "Add a care partner (optional)",
                            subtitle: "Share updates with someone you trust.")

            VStack(spacing: 14) {
                TextField("Partner Name", text: $name)
                    .textContentType(.name)
                    .focused($focusedField, equals: .cpName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .cpEmail }
                    .glassStyle(isFocused: focusedField == .cpName)

                TextField("Partner Email Address", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .cpEmail)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .glassStyle(isFocused: focusedField == .cpEmail)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Relationship")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.medoraDeepBlue)
                        .padding(.leading, 6)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)],
                              spacing: 8) {
                        ForEach(relationships, id: \.self) { option in
                            relationshipChip(option)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }

    private func relationshipChip(_ option: String) -> some View {
        let isSelected = selectedRelationship == option
        return Button {
            HapticManager.shared.triggerSelection()
            selectedRelationship = option
        } label: {
            Text(option)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.medoraBlue : Color.white.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.8), lineWidth: 1)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Screen 9: Completed

private struct CompletedStep: View {
    let error: String?

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 86))
                .foregroundStyle(Color.medoraGreen)
                .shadow(color: Color.medoraGreen.opacity(0.18), radius: 10, x: 0, y: 6)
                .padding(.top, 16)

            VStack(spacing: 12) {
                Text("You're all set")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.medoraDeepBlue)

                Text("Medora is ready.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))

                Text("Next step:\nScan your first doctor instruction sheet and we'll turn it into a personalized care plan.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }
            .multilineTextAlignment(.center)

            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - Shared onboarding components

/// Centered title + subtitle used at the top of each step.
private struct OnboardingTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.medoraDeepBlue)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }
}

/// Icon-in-a-squircle + text row used in the welcome and Health cards.
private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.medoraBlue)
                .frame(width: 32, height: 32)
                .background(Color.medoraBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.medoraDeepBlue)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

/// Tappable glass row with a checkbox or radio indicator. A real Button so
/// presses highlight instantly and VoiceOver reads it as a control.
private struct SelectableRow: View {
    enum Indicator {
        case checkbox
        case radio
    }

    let title: String
    let isSelected: Bool
    var indicator: Indicator = .checkbox
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.triggerSelection()
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                indicatorView
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.7) : Color.white.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.medoraBlue.opacity(0.65) : Color.white.opacity(0.8),
                            lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case .checkbox:
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.medoraBlue : Color.secondary.opacity(0.5))
        case .radio:
            Circle()
                .stroke(isSelected ? Color.medoraBlue : Color.secondary.opacity(0.5), lineWidth: 2)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .fill(isSelected ? Color.medoraBlue : Color.clear)
                        .padding(4)
                )
        }
    }
}

/// Live validation hint shown under the account fields.
private struct RequirementRow: View {
    let text: String
    let satisfied: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(satisfied ? Color.medoraGreen : Color.secondary.opacity(0.5))

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(satisfied ? Color.medoraGreen : Color.secondary)
        }
    }
}

// Use shared PressableButtonStyle from Theme.swift

private extension View {
    /// Translucent white card used for grouped content over the background image.
    func glassCard() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            )
    }
}

// MARK: - Glass text field modifier

struct GlassTextFieldModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .medium))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.7 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isFocused ? Color.medoraBlue : Color.white.opacity(0.85), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
    }
}

extension View {
    func glassStyle(isFocused: Bool) -> some View {
        self.modifier(GlassTextFieldModifier(isFocused: isFocused))
    }
}
