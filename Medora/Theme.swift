//
//  Theme.swift
//  Medora
//
//  Shared colors and styling used across the app.
//

import SwiftUI

extension Color {
    // MARK: Brand accents (constant across light/dark)

    /// Primary brand blue used for buttons and accents.
    static let medoraBlue = Color(red: 0.05, green: 0.45, blue: 0.73)
    /// Darker blue used for icons / secondary accents.
    static let medoraDeepBlue = Color(red: 0.1, green: 0.31, blue: 0.5)
    static let medoraGreen = Color(red: 0.03, green: 0.55, blue: 0.31)

    // MARK: App surfaces

    static let medoraBackground = Color(red: 0.9, green: 0.97, blue: 1.0)
    static let medoraSurface = Color.white
    static let medoraField = Color(red: 0.94, green: 0.97, blue: 0.99)
    static let medoraHairline = Color(red: 0.82, green: 0.87, blue: 0.91)
}

/// Solid light app background.
struct MedoraBackground: View {
    var body: some View {
        Color.medoraBackground
            .ignoresSafeArea()
    }
}

/// Reusable filled button used for primary actions across the app.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(height: 54)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.medoraBlue.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Reusable lightly-tinted button used for secondary actions across the app.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.medoraBlue)
            .frame(height: 50)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.medoraBlue.opacity(configuration.isPressed ? 0.08 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.medoraBlue.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A labelled metric row with an icon, used on the health dashboard.
struct HealthMetricBox: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.medoraField)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.medoraHairline, lineWidth: 1)
        )
    }
}

/// Helper to trigger haptic feedback on iOS devices.
struct HapticManager {
    static let shared = HapticManager()
    
    func triggerImpact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    func triggerNotification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
    
    func triggerSelection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

