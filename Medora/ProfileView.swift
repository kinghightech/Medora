//
//  ProfileView.swift
//  Medora
//
//  Profile tab. Lets the user pick the app language; the whole app
//  (everything after onboarding) re-renders in the chosen language.
//

import SwiftUI

struct ProfileView: View {
    let userName: String
    let userEmail: String
    @ObservedObject var reportStore: ReportStore
    var onSignOut: () -> Void = {}
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var showSignOutConfirmation = false
    @State private var previewingReport: HealthReport?
    @StateObject private var symptomStore = SymptomStore()

    private var displayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Medora" : trimmed
    }

    var body: some View {
        ZStack {
            MedoraBackground()

            ScrollView {
                VStack(spacing: 24) {
                    profileHeader
                    
                    VStack(spacing: 20) {
                        accountCard
                        healthReportsCard
                        languageCard
                        symptomJournalCard
                        signOutCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .task {
                await symptomStore.fetchSymptoms()
            }
        }
        .navigationTitle(loc.t("Profile"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $previewingReport) { report in
            ReportPreviewSheet(report: report)
        }
    }

    // MARK: Health Reports

    private var healthReportsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t("Health Reports"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            if let job = reportStore.activeJob {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(Color.medoraBlue)
                        .frame(width: 38, height: 38)
                        .background(Color.medoraBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.t("Generating report…"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(job.dateRangeText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .padding(10)
                .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if reportStore.reports.isEmpty {
                if reportStore.activeJob == nil {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.medoraBlue)
                            .frame(width: 38, height: 38)
                            .background(Color.medoraBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                        Text(loc.t("No reports yet. Generate one from the Aura AI tab."))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(reportStore.reports) { report in
                        reportRow(report)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private func reportRow(_ report: HealthReport) -> some View {
        Button {
            previewingReport = report
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.medoraBlue)
                    .frame(width: 38, height: 38)
                    .background(Color.medoraBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(report.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(report.dateRangeText) · \(formatRelativeTime(report.createdAt))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                ShareLink(item: report.fileURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.medoraBlue)
                        .frame(width: 32, height: 32)
                        .background(Color.medoraBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { reportStore.deleteReport(report) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.78))
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Header

    private var profileHeader: some View {
        VStack(spacing: 16) {
            Text(initials)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 100, height: 100)
                .background(
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.medoraBlue.opacity(0.8), Color.medoraDeepBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
                .shadow(color: Color.medoraBlue.opacity(0.3), radius: 12, x: 0, y: 6)

            VStack(spacing: 6) {
                Text(displayName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(userEmail.isEmpty ? "No email provided" : userEmail)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    // MARK: Account Info
    
    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t("Account Information"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            VStack(spacing: 0) {
                accountRow(title: loc.t("Name"), value: displayName, icon: "person.fill")
                Divider().padding(.leading, 44)
                accountRow(title: loc.t("Email"), value: userEmail.isEmpty ? loc.t("None") : userEmail, icon: "envelope.fill")
            }
            .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.medoraHairline, lineWidth: 1)
            )
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }
    
    private func accountRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.medoraBlue)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer(minLength: 16)
            
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
    }

    // MARK: Language

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("Preferences"))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(loc.t("Preferred language"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.medoraBlue)
                        .frame(width: 24)
                    
                    Text(loc.t("Language"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    Spacer(minLength: 16)
                    
                    Menu {
                        Picker("", selection: Binding(
                            get: { loc.language },
                            set: { newLanguage in
                                withAnimation(.easeOut(duration: 0.15)) {
                                    loc.setLanguage(newLanguage)
                                }
                            }
                        )) {
                            ForEach(AppLanguage.allCases) { language in
                                Text("\(language.flag)  \(language.displayName)")
                                    .tag(language)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(loc.language.flag) \(loc.language.displayName)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.medoraBlue)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.medoraBlue)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.medoraBlue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
            .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.medoraHairline, lineWidth: 1)
            )

            Text(loc.t("The whole app updates instantly."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    // MARK: Sign out

    private var signOutCard: some View {
        Button {
            showSignOutConfirmation = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .semibold))

                Text(loc.t("Sign Out"))
                    .font(.system(size: 16, weight: .semibold))

                Spacer(minLength: 0)
            }
            .foregroundStyle(.red)
            .padding(18)
            .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .confirmationDialog(loc.t("Sign out of Medora?"),
                            isPresented: $showSignOutConfirmation,
                            titleVisibility: .visible) {
            Button(loc.t("Sign Out"), role: .destructive) {
                onSignOut()
            }
            Button(loc.t("Cancel"), role: .cancel) {}
        } message: {
            Text(loc.t("You'll go through setup again the next time you open Medora."))
        }
    }

    private var symptomJournalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t("Symptom Journal"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            if symptomStore.symptoms.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.medoraBlue)
                        .frame(width: 38, height: 38)
                        .background(Color.medoraBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    
                    Text(loc.t("No symptoms logged yet"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(12)
                .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(symptomStore.symptoms) { log in
                        HStack(spacing: 12) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.medoraBlue)
                                .frame(width: 38, height: 38)
                                .background(Color.medoraBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(log.symptomText)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                
                                Text(formatRelativeTime(log.createdAt))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer(minLength: 8)
                            
                            Button {
                                Task {
                                    await symptomStore.deleteSymptom(id: log.id ?? UUID())
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.red.opacity(0.78))
                                    .frame(width: 32, height: 32)
                                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private func formatRelativeTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Report preview sheet

private struct ReportPreviewSheet: View {
    let report: HealthReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitRepresentable(url: report.fileURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(report.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(Color.medoraBlue)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ShareLink(item: report.fileURL) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.medoraBlue)
                        }
                    }
                }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
#Preview {
    NavigationStack {
        ProfileView(userName: "Aahish Abbani", userEmail: "aahish@example.com", reportStore: ReportStore())
    }
}
#endif
