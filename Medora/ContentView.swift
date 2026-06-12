//
//  ContentView.swift
//  Medora
//
//  Created by Aahish Abbani on 6/11/26.
//

import SwiftUI

struct ContentView: View {
    private enum OnboardingStep {
        case welcome
        case name
        case healthPermission
        case healthDashboard
        case healthUnavailable
    }

    @ObservedObject var healthStore: HealthStore

    /// Called when the user finishes onboarding, passing their entered name.
    var onComplete: (String) -> Void = { _ in }

    @State private var step: OnboardingStep = .welcome
    @State private var name = ""
    @FocusState private var isNameFieldFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color(red: 0.9, green: 0.97, blue: 1.0)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    startupHeader

                    VStack(spacing: 28) {
                        switch step {
                        case .welcome:
                            welcomeScreen
                        case .name:
                            nameScreen
                        case .healthPermission:
                            healthPermissionScreen
                        case .healthDashboard:
                            healthDashboardScreen
                        case .healthUnavailable:
                            healthUnavailableScreen
                        }
                    }
                    .frame(maxWidth: cardMaxWidth)
                    .padding(.horizontal, 24)
                    .padding(.top, cardTopPadding)
                    .padding(.bottom, cardBottomPadding)
                    .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.medoraBlue.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.medoraDeepBlue.opacity(0.14), radius: 22, x: 0, y: 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 34)
            }
        }
    }

    private var canGoBack: Bool {
        switch step {
        case .name, .healthPermission:
            return true
        case .welcome, .healthDashboard, .healthUnavailable:
            return false
        }
    }

    private var cardMaxWidth: CGFloat {
        step == .healthDashboard ? 420 : 360
    }

    private var topSpacerLength: CGFloat {
        step == .healthDashboard ? 18 : 34
    }

    private var bottomSpacerLength: CGFloat {
        switch step {
        case .healthDashboard:
            return 28
        case .name, .healthPermission:
            return 86
        case .welcome, .healthUnavailable:
            return 64
        }
    }

    private var cardTopPadding: CGFloat {
        switch step {
        case .name:
            return 26
        case .healthDashboard:
            return 28
        case .welcome, .healthPermission, .healthUnavailable:
            return 34
        }
    }

    private var cardBottomPadding: CGFloat {
        step == .healthDashboard ? 28 : 34
    }

    private var startupHeader: some View {
        HStack {
            Image("MedoraLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Medora")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.medoraDeepBlue)

            Spacer(minLength: 12)

            if canGoBack {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(Color.medoraSurface, in: Circle())
                        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.1, green: 0.31, blue: 0.5))
                .accessibilityLabel("Back")
            }
        }
        .frame(maxWidth: 420)
    }

    private var logoMark: some View {
        Image("MedoraLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 86, height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.medoraBlue.opacity(0.18), radius: 14, x: 0, y: 8)
            .accessibilityHidden(true)
    }

    private var welcomeScreen: some View {
        VStack(spacing: 26) {
            logoMark

            Text("Welcome to Medora")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    step = .name
                    isNameFieldFocused = true
                }
            } label: {
                Text("Next")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingButtonStyle())
        }
    }

    private var nameScreen: some View {
        VStack(spacing: 18) {
            Text("What is your full name?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.system(size: 18, weight: .medium))
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.medoraField)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isNameFieldFocused ? Color(red: 0.05, green: 0.45, blue: 0.73) : Color.medoraHairline, lineWidth: 1.5)
                )
                .focused($isNameFieldFocused)
                .submitLabel(.done)
                .onSubmit(finishOnboarding)

            Button(action: finishOnboarding) {
                Text("Finish")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingButtonStyle())
            .disabled(trimmedName.isEmpty)
            .opacity(trimmedName.isEmpty ? 0.55 : 1)
            .padding(.top, 6)
        }
    }

    private var healthPermissionScreen: some View {
        VStack(spacing: 24) {
            logoMark

            VStack(spacing: 10) {
                Text("Welcome, \(trimmedName)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Connect Apple Health to continue.")
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button(action: requestHealthAccess) {
                HStack(spacing: 10) {
                    if healthStore.isLoading {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(healthStore.isLoading ? "Connecting" : "Connect Health")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingButtonStyle())
            .disabled(healthStore.isLoading)
        }
    }

    private var healthDashboardScreen: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Health Summary")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Today and last night")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                HealthMetricBox(
                    title: "Calories burned",
                    value: healthStore.summary.caloriesBurned,
                    systemImage: "flame.fill",
                    tint: Color(red: 0.88, green: 0.27, blue: 0.14)
                )

                HealthMetricBox(
                    title: "Steps",
                    value: healthStore.summary.steps,
                    systemImage: "figure.walk",
                    tint: Color(red: 0.05, green: 0.45, blue: 0.73)
                )

                HealthMetricBox(
                    title: "Sleep data",
                    value: healthStore.summary.sleep,
                    systemImage: "moon.zzz.fill",
                    tint: Color(red: 0.32, green: 0.28, blue: 0.68)
                )
            }

            VStack(spacing: 12) {
                Button {
                    onComplete(trimmedName)
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OnboardingButtonStyle())

                Button(action: refreshHealthData) {
                    HStack(spacing: 8) {
                        if healthStore.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }

                        Text(healthStore.isLoading ? "Refreshing" : "Refresh")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(healthStore.isLoading)
            }
        }
    }

    private var healthUnavailableScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 62))
                .foregroundStyle(Color(red: 0.86, green: 0.37, blue: 0.13))
                .accessibilityHidden(true)

            Text("Unfortunately you're not able to use our application. Please try again.")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: requestHealthAccess) {
                Text("Try Again")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingButtonStyle())
            .disabled(healthStore.isLoading)
        }
    }

    private func finishOnboarding() {
        guard !trimmedName.isEmpty else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            step = .healthPermission
            isNameFieldFocused = false
        }
    }

    private func goBack() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            switch step {
            case .welcome:
                break
            case .name:
                step = .welcome
                isNameFieldFocused = false
            case .healthPermission:
                step = .name
                isNameFieldFocused = true
            case .healthDashboard, .healthUnavailable:
                break
            }
        }
    }

    private func requestHealthAccess() {
        Task {
            let didConnect = await healthStore.requestAccessAndLoadData()

            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                step = didConnect ? .healthDashboard : .healthUnavailable
            }
        }
    }

    private func refreshHealthData() {
        Task {
            await healthStore.refreshHealthData()
        }
    }
}

private struct OnboardingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(height: 54)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.45, blue: 0.73).opacity(configuration.isPressed ? 0.78 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if DEBUG && targetEnvironment(simulator)
#Preview("Welcome") {
    ContentView(healthStore: HealthStore())
}
#endif
