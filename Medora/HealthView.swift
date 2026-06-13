//
//  HealthView.swift
//  Medora
//
//  Dedicated "Health" tab. Surfaces each HealthKit metric imported by
//  HealthStore in its own labelled section. The raw HealthStore data and
//  the HealthKit integration are left completely untouched; this view is
//  purely presentational.
//

import SwiftUI

struct HealthView: View {
    @ObservedObject var healthStore: HealthStore
    @ObservedObject private var loc = LocalizationManager.shared

    /// Translates the "No data available" placeholder; leaves real values as-is.
    private func metricValue(_ value: String) -> String {
        value == "No data available" ? loc.t("No data available") : value
    }

    var body: some View {
        ZStack {
            MedoraBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // Page header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(loc.t("Your Health"))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(loc.t("Live data from Apple Health"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        refreshButton
                    }
                    .padding(.top, 4)

                    // ── Activity ──────────────────────────────────────────────
                    HealthSection(title: loc.t("Activity"), icon: "figure.run", iconTint: Color.medoraBlue) {
                        HealthMetricBox(
                            title: loc.t("Steps"),
                            value: metricValue(healthStore.summary.steps),
                            systemImage: "figure.walk",
                            tint: Color.medoraBlue
                        )
                        HealthMetricBox(
                            title: loc.t("Calories burned"),
                            value: metricValue(healthStore.summary.caloriesBurned),
                            systemImage: "flame.fill",
                            tint: Color(red: 0.88, green: 0.27, blue: 0.14)
                        )
                    }

                    // ── Sleep ─────────────────────────────────────────────────
                    HealthSection(title: loc.t("Sleep"), icon: "moon.zzz.fill", iconTint: Color(red: 0.32, green: 0.28, blue: 0.68)) {
                        HealthMetricBox(
                            title: loc.t("Sleep data"),
                            value: metricValue(healthStore.summary.sleep),
                            systemImage: "moon.zzz.fill",
                            tint: Color(red: 0.32, green: 0.28, blue: 0.68)
                        )
                    }

                    // ── Heart & Vitals ────────────────────────────────────────
                    HealthSection(title: loc.t("Heart & Vitals"), icon: "heart.fill", iconTint: Color(red: 0.94, green: 0.21, blue: 0.26)) {
                        HealthMetricBox(
                            title: loc.t("Heart Rate"),
                            value: metricValue(healthStore.summary.heartRate),
                            systemImage: "heart.fill",
                            tint: Color(red: 0.94, green: 0.21, blue: 0.26)
                        )
                        HealthMetricBox(
                            title: loc.t("Blood Pressure"),
                            value: metricValue(healthStore.summary.bloodPressure),
                            systemImage: "heart.text.square.fill",
                            tint: Color(red: 0.05, green: 0.72, blue: 0.61)
                        )
                        HealthMetricBox(
                            title: loc.t("Blood Glucose"),
                            value: metricValue(healthStore.summary.bloodGlucose),
                            systemImage: "water.waves",
                            tint: Color(red: 0.92, green: 0.49, blue: 0.19)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(loc.t("Health"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Refresh

    private var refreshButton: some View {
        Button(action: refreshHealthData) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.medoraBlue)
                .frame(width: 40, height: 40)
                .background(Color.medoraBlue.opacity(0.12), in: Circle())
                .opacity(healthStore.isLoading ? 0 : 1)
                .overlay {
                    if healthStore.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(healthStore.isLoading)
        .accessibilityLabel("Refresh health data")
    }

    private func refreshHealthData() {
        Task {
            _ = await healthStore.requestAccessAndLoadData()
        }
    }
}

// MARK: - HealthSection

/// A titled card group that wraps one or more `HealthMetricBox` rows.
private struct HealthSection<Content: View>: View {
    let title: String
    let icon: String
    let iconTint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 32, height: 32)
                    .background(iconTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            content()
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}

#if DEBUG && targetEnvironment(simulator)
#Preview {
    NavigationStack {
        HealthView(healthStore: HealthStore())
    }
}
#endif
