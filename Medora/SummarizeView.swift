//
//  SummarizeView.swift
//  Medora
//
//  Lets the user pick a date range and kick off a Doctor's-Report PDF. The
//  actual generation is owned by `ReportStore`, so it keeps running in the
//  background even if this screen is dismissed — the finished report lands on
//  the Profile tab and fires a notification when ready.
//

import SwiftUI

struct SummarizeView: View {
    @ObservedObject var healthStore: HealthStore
    @ObservedObject var checklistStore: ChecklistStore
    @ObservedObject var authStore: AuthStore
    @ObservedObject var reportStore: ReportStore

    @Environment(\.dismiss) private var dismiss

    // Date range
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate: Date = Date()

    // Local tracking of the job started from this screen, so we can show the
    // finished preview if the user happens to stay on the page.
    @State private var pendingJobID: UUID?
    @State private var finishedReport: HealthReport?

    /// True while the date pickers + generate button should be visible (idle or
    /// after a failure) — hidden while generating or showing a finished report.
    private var showsConfiguration: Bool {
        finishedReport == nil && reportStore.activeJob == nil
    }

    var body: some View {
        ZStack {
            MedoraBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    if showsConfiguration {
                        dateRangeSection
                    }

                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Health Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
                    .foregroundStyle(Color.medoraBlue)
            }
        }
        .onAppear {
            if let job = reportStore.activeJob { pendingJobID = job.id }
            // Warm the model so tapping Generate hits a loaded model.
            reportStore.prewarm()
        }
        .onChange(of: reportStore.activeJob) { _, newValue in
            // The job we started just finished.
            guard newValue == nil, let pending = pendingJobID else { return }
            if reportStore.lastError == nil,
               let report = reportStore.reports.first(where: { $0.id == pending }) {
                withAnimation { finishedReport = report }
            }
            pendingJobID = nil
        }
    }

    // MARK: - State-driven content

    @ViewBuilder
    private var content: some View {
        if let report = finishedReport {
            PDFPreviewCard(url: report.fileURL)
            finishedActionButtons(url: report.fileURL)
        } else if reportStore.activeJob != nil {
            generatingCard(progress: reportStore.activeJob?.progress ?? "")
        } else if let message = reportStore.lastError {
            errorCard(message: message)
            generateButton
        } else {
            generateButton
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.medoraBlue.opacity(0.15), Color(red: 0.38, green: 0.2, blue: 0.9).opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.medoraBlue, Color(red: 0.38, green: 0.2, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 4) {
                Text("Doctor's Report")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Generate a professional health summary\nyou can share with any doctor.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Date Range

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Date Range", systemImage: "calendar")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                HStack {
                    Text("From")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                    Spacer()
                    DatePicker("", selection: $startDate, in: ...endDate, displayedComponents: .date)
                        .labelsHidden()
                        .tint(Color.medoraBlue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                HStack {
                    Text("To")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                    Spacer()
                    DatePicker("", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .tint(Color.medoraBlue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.medoraHairline, lineWidth: 1)
            )

            let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            Text("\(days + 1) day\(days == 0 ? "" : "s") selected")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Generate button

    private var generateButton: some View {
        Button(action: generate) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                Text("Generate Report")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.medoraBlue, Color(red: 0.38, green: 0.2, blue: 0.9)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: Color.medoraBlue.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Generating card

    private func generatingCard(progress: String) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Color.medoraBlue)
                Text("Generating your report…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            // The whole point: reassure the user they don't have to wait here.
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.medoraBlue)
                Text("You can close this screen — Medora will keep working in the background, save the report to your Profile, and notify you when it's ready.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !progress.isEmpty {
                Text(progress)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(4)
            }

            Button {
                dismiss()
            } label: {
                Text("Close & let it run")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.medoraBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.medoraBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.medoraHairline, lineWidth: 1)
        )
    }

    // MARK: - Error card

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text("Generation failed")
                    .font(.system(size: 15, weight: .semibold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Finished action buttons

    private func finishedActionButtons(url: URL) -> some View {
        VStack(spacing: 12) {
            ShareLink(item: url) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Share Report")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.medoraBlue, Color(red: 0.38, green: 0.2, blue: 0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: Color.medoraBlue.opacity(0.35), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation {
                    finishedReport = nil
                    reportStore.lastError = nil
                }
            } label: {
                Text("Generate Another")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.medoraBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.medoraBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("Saved to your Profile under Health Reports.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func generate() {
        reportStore.lastError = nil
        finishedReport = nil
        reportStore.startGeneration(
            startDate: startDate,
            endDate: endDate,
            healthStore: healthStore,
            checklistStore: checklistStore,
            profile: authStore.currentProfile
        )
        pendingJobID = reportStore.activeJob?.id
    }
}

// MARK: - PDF Preview Card

private struct PDFPreviewCard: View {
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext.fill")
                    .foregroundStyle(Color.medoraBlue)
                    .font(.system(size: 16, weight: .semibold))
                Text("Your Report is Ready")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.medoraGreen)
                    .font(.system(size: 18))
            }

            PDFKitRepresentable(url: url)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.medoraHairline, lineWidth: 1)
                )
        }
        .padding(16)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.medoraHairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 8)
    }
}
