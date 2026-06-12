//
//  ContentView.swift
//  Medora
//

import SwiftUI

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

struct ContentView: View {
    private enum OnboardingStep {
        case welcome               // Screen 1: Welcome to Medora
        case name                  // Screen 2: What should we call you?
        case age                   // Screen 3: How old are you?
        case managing              // Screen 4: What are you currently managing?
        case healthPermission      // Screen 6: Connect your Apple Health data
        case account               // Screen 7: Where should we save your progress?
        case reminders             // Screen 8: Would you like medication reminders?
        case carePartner           // Screen 9: Add a care partner (optional)
        case completed             // Screen 10: You're all set
    }

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
    var onComplete: (String) -> Void = { _ in }

    // MARK: - State Variables
    @State private var step: OnboardingStep = .welcome
    @FocusState private var focusedField: OnboardingField?

    // Screen 2 Name
    @State private var firstName = ""
    @State private var lastName = ""

    // Screen 3 Age
    @State private var ageString = ""

    // Screen 4 Managing Conditions
    private let availableConditions = [
        "Heart Health", "Diabetes", "Cancer", "Asthma",
        "High Blood Pressure", "Recovery After Surgery",
        "Mental Health", "Chronic Pain", "Autoimmune Condition", "Other"
    ]
    @State private var selectedConditions: Set<String> = []

    // Screen 7 Account
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    // Screen 8 Medication Reminders
    @State private var wantsReminders: Bool? = nil

    // Screen 9 Care Partner
    @State private var cpName = ""
    @State private var cpEmail = ""
    @State private var cpRelationship = "Spouse"
    private let relationships = ["Spouse", "Parent", "Caregiver", "Family Member"]

    // Loader & Errors
    @State private var isSubmitting = false
    @State private var onboardingError: String? = nil

    // MARK: - Computeds & Validation
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
        if let age = parsedAge, age > 0 && age < 120 {
            return true
        }
        return false
    }

    private var isEmailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private var isPasswordValid: Bool {
        password.count >= 8
    }

    private var isAccountValid: Bool {
        isEmailValid && isPasswordValid && password == confirmPassword
    }

    private var isCarePartnerValid: Bool {
        let nameTrim = cpName.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailTrim = cpEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if nameTrim.isEmpty && emailTrim.isEmpty { return true }
        if !nameTrim.isEmpty && emailTrim.contains("@") && emailTrim.contains(".") { return true }
        return false
    }

    private var progressFraction: Double {
        switch step {
        case .welcome: return 0.1
        case .name: return 0.2
        case .age: return 0.3
        case .managing: return 0.4
        case .healthPermission: return 0.5
        case .account: return 0.6
        case .reminders: return 0.7
        case .carePartner: return 0.8
        case .completed: return 1.0
        }
    }

    private var canGoBack: Bool {
        step != .welcome && step != .completed
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            // Full-bleed background image
            Image("onboardingbackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                }

            // Soft overlay to maintain readability
            Color.white.opacity(0.12)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                }

            VStack(spacing: 0) {
                // Fixed Header Bar (placed outside ScrollView so it never scrolls)
                headerBar
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                // Scrollable content area in the middle
                ScrollView {
                    VStack(spacing: 32) {
                        switch step {
                        case .welcome:
                            welcomeScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)))
                        case .name:
                            nameScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)))
                        case .age:
                            ageScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)))
                        case .managing:
                            managingScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)))
                        case .healthPermission:
                            healthPermissionScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)))
                        case .account:
                            accountScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)))
                        case .reminders:
                            remindersScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)))
                        case .carePartner:
                            carePartnerScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)))
                        case .completed:
                            completedScreen
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.immediately) // dismisses keyboard when scrolling

                // Pinned buttons at the bottom of the screen (resizes cleanly above keyboard)
                bottomButtons
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 16) {
            if canGoBack {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.medoraDeepBlue)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.5))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Spacer()
                    .frame(width: 44, height: 44)
            }

            // Custom elegant progress line
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.35))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.medoraBlue)
                        .frame(width: geo.size.width * progressFraction, height: 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: progressFraction)
                }
                .frame(height: 6)
                .padding(.vertical, 19)
            }
        }
        .frame(height: 44)
    }

    // MARK: - Screen 1: Welcome to Medora
    private var welcomeScreen: some View {
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
                    .multilineTextAlignment(.center)

                Text("Your doctor's instructions, turned into a daily plan.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)

                Text("We'll set up your care profile in under a minute.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Screen 2: What should we call you?
    private var nameScreen: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("What should we call you?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .multilineTextAlignment(.center)

                Text("We'll personalize your care plan and reminders.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                TextField("First Name", text: $firstName)
                    .focused($focusedField, equals: .firstName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .lastName }
                    .glassStyle(isFocused: focusedField == .firstName)

                TextField("Last Name", text: $lastName)
                    .focused($focusedField, equals: .lastName)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .glassStyle(isFocused: focusedField == .lastName)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Screen 3: How old are you?
    private var ageScreen: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("How old are you?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .multilineTextAlignment(.center)

                Text("This helps us personalize recommendations and reminders.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Age", text: $ageString)
                .focused($focusedField, equals: .age)
                .keyboardType(.numberPad)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .glassStyle(isFocused: focusedField == .age)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Screen 4: What are you currently managing?
    private var managingScreen: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("What are you currently managing?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .multilineTextAlignment(.center)

                Text("Select anything that applies.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                ForEach(availableConditions, id: \.self) { condition in
                    let isSelected = selectedConditions.contains(condition)
                    HStack {
                        Text(condition)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? Color.medoraBlue : Color.secondary.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.65) : Color.white.opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.medoraBlue.opacity(0.6) : Color.white.opacity(0.8), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticManager.shared.triggerSelection()
                        if isSelected {
                            selectedConditions.remove(condition)
                        } else {
                            selectedConditions.insert(condition)
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

    // MARK: - Screen 6: Connect your Apple Health data
    private var healthPermissionScreen: some View {
        VStack(spacing: 28) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.medoraBlue)
                .shadow(color: Color.medoraBlue.opacity(0.18), radius: 10, x: 0, y: 6)
                .padding(.top, 16)

            VStack(spacing: 12) {
                Text("Connect your Apple Health data")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .multilineTextAlignment(.center)

                Text("Let Medora automatically track progress toward your care goals.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }

            // Health tracking highlights
            VStack(alignment: .leading, spacing: 14) {
                Label("Daily movement & active energy", systemImage: "checkmark.circle.fill")
                Label("Steps walked", systemImage: "checkmark.circle.fill")
                Label("Sleep & rest quality", systemImage: "checkmark.circle.fill")
                Label("Heart rate, blood pressure & glucose vitals", systemImage: "checkmark.circle.fill")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.medoraDeepBlue)
            .padding(18)
            .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            )

            Text("Your health data stays private and under your control.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Screen 7: Where should we save your progress?
    private var accountScreen: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Where should we save your progress?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .multilineTextAlignment(.center)

                Text("Create your account so your care plan stays synced and secure.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                TextField("Email Address", text: $email)
                    .focused($focusedField, equals: .email)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .glassStyle(isFocused: focusedField == .email)

                SecureField("Password", text: $password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirmPassword }
                    .glassStyle(isFocused: focusedField == .password)

                SecureField("Confirm Password", text: $confirmPassword)
                    .focused($focusedField, equals: .confirmPassword)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .glassStyle(isFocused: focusedField == .confirmPassword)
            }
            .padding(.horizontal, 4)

            Text("Password must be at least 8 characters.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Screen 8: Would you like medication reminders?
    private var remindersScreen: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Would you like medication reminders?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .multilineTextAlignment(.center)

                Text("We'll help you stay on track.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                reminderOptionRow(title: "Yes, remind me", selection: true)
                reminderOptionRow(title: "Not right now", selection: false)
            }
        }
    }

    private func reminderOptionRow(title: String, selection: Bool) -> some View {
        let isSelected = wantsReminders == selection
        return HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary)
            Spacer()
            Circle()
                .stroke(isSelected ? Color.medoraBlue : Color.secondary.opacity(0.6), lineWidth: 2)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .fill(isSelected ? Color.medoraBlue : Color.clear)
                        .padding(4)
                )
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.65) : Color.white.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.medoraBlue.opacity(0.6) : Color.white.opacity(0.8), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.triggerSelection()
            wantsReminders = selection
        }
    }

    // MARK: - Screen 9: Add a care partner (optional)
    private var carePartnerScreen: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Add a care partner (optional)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.medoraDeepBlue)
                    .multilineTextAlignment(.center)

                Text("Share updates with someone you trust.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                TextField("Partner Name", text: $cpName)
                    .focused($focusedField, equals: .cpName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .cpEmail }
                    .glassStyle(isFocused: focusedField == .cpName)

                TextField("Partner Email Address", text: $cpEmail)
                    .focused($focusedField, equals: .cpEmail)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .glassStyle(isFocused: focusedField == .cpEmail)

                // Relationship selection picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Relationship")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.medoraDeepBlue)
                        .padding(.leading, 6)

                    HStack(spacing: 8) {
                        ForEach(relationships, id: \.self) { relationship in
                            let isSelected = cpRelationship == relationship
                            Text(relationship)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : Color.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? Color.medoraBlue : Color.white.opacity(0.45))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.8), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    HapticManager.shared.triggerSelection()
                                    cpRelationship = relationship
                                }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Screen 10: You're all set
    private var completedScreen: some View {
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
                    .multilineTextAlignment(.center)

                Text("Medora is ready.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))

                Text("Next step:\nScan your first doctor instruction sheet and we'll turn it into a personalized care plan.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }

            if let onboardingError {
                Text(onboardingError)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
        }
    }

    // MARK: - Pinned Bottom Button Bar
    @ViewBuilder
    private var bottomButtons: some View {
        VStack(spacing: 10) {
            switch step {
            case .welcome:
                Button {
                    advanceStep(to: .name)
                } label: {
                    Text("Get Started")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

            case .name:
                Button {
                    advanceStep(to: .age)
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isNameValid)
                .opacity(isNameValid ? 1 : 0.55)

            case .age:
                Button {
                    advanceStep(to: .managing)
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isAgeValid)
                .opacity(isAgeValid ? 1 : 0.55)

            case .managing:
                Button {
                    advanceStep(to: .healthPermission)
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

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

                Button {
                    advanceStep(to: .account)
                } label: {
                    Text("Maybe Later")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.medoraDeepBlue)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

            case .account:
                Button {
                    advanceStep(to: .reminders)
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isAccountValid)
                .opacity(isAccountValid ? 1 : 0.55)

            case .reminders:
                Button {
                    advanceStep(to: .carePartner)
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(wantsReminders == nil)
                .opacity(wantsReminders == nil ? 0.55 : 1)

            case .carePartner:
                Button {
                    advanceStep(to: .completed)
                } label: {
                    Text("Add Care Partner")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isCarePartnerValid || cpName.isEmpty)
                .opacity((isCarePartnerValid && !cpName.isEmpty) ? 1 : 0.55)

                Button {
                    cpName = ""
                    cpEmail = ""
                    advanceStep(to: .completed)
                } label: {
                    Text("Skip")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.medoraDeepBlue)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

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
        } }

    // MARK: - Reusable UI Components

    // MARK: - Helpers & Actions
    private func advanceStep(to nextStep: OnboardingStep) {
        focusedField = nil
        HapticManager.shared.triggerImpact(style: .medium)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            step = nextStep
        }
    }

    private func goBack() {
        focusedField = nil
        HapticManager.shared.triggerImpact(style: .light)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            switch step {
            case .welcome:
                break
            case .name:
                step = .welcome
            case .age:
                step = .name
            case .managing:
                step = .age
            case .healthPermission:
                step = .managing
            case .account:
                step = .healthPermission
            case .reminders:
                step = .account
            case .carePartner:
                step = .reminders
            case .completed:
                step = .carePartner
            }
        }
    }

    private func requestHealthAccess() {
        Task {
            _ = await healthStore.requestAccessAndLoadData()
            // Even if they deny, we advance to next step (.account)
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
        let finalCpName = cpName.isEmpty ? nil : cpName
        let finalCpEmail = cpEmail.isEmpty ? nil : cpEmail
        let finalCpRelationship = cpName.isEmpty ? nil : cpRelationship

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
                onComplete(finalName)
            } catch {
                isSubmitting = false
                HapticManager.shared.triggerNotification(type: .error)
                onboardingError = error.localizedDescription
            }
        }
    }
}

// MARK: - Glass Text Field Modifier
struct GlassTextFieldModifier: ViewModifier {
    let isFocused: Bool
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .medium))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.55))
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
