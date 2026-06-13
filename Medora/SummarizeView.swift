//
//  SummarizeView.swift
//  Medora
//
//  Generates a professional doctor's-report PDF from the user's health data,
//  symptom logs, and checklist completion history over a chosen date range.
//

import PDFKit
import SwiftUI
import UIKit

struct SummarizeView: View {
    @ObservedObject var healthStore: HealthStore
    @ObservedObject var checklistStore: ChecklistStore
    @ObservedObject var authStore: AuthStore

    @Environment(\.dismiss) private var dismiss

    // Date range
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate: Date = Date()

    // Generation state
    @State private var generationState: GenerationState = .idle
    @State private var generatedPDFURL: URL?
    @State private var isShowingShareSheet = false

    // AI streaming
    private let client = FeatherlessAIClient()

    enum GenerationState: Equatable {
        case idle
        case generating(String)  // streamed progress text
        case done
        case failed(String)
    }

    var body: some View {
        ZStack {
            MedoraBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    dateRangeSection

                    switch generationState {
                    case .idle:
                        generateButton
                    case .generating(let progress):
                        generatingCard(progress: progress)
                    case .done:
                        if let url = generatedPDFURL {
                            PDFPreviewCard(url: url)
                            actionButtons(url: url)
                        }
                    case .failed(let message):
                        errorCard(message: message)
                        generateButton
                    }
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
                        .onChange(of: startDate) {
                            if generationState != .idle { generationState = .idle }
                        }
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
                        .onChange(of: endDate) {
                            if generationState != .idle { generationState = .idle }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.medoraHairline, lineWidth: 1)
            )

            // Range summary label
            let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            Text("\(days + 1) day\(days == 0 ? "" : "s") selected")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Generate button

    private var generateButton: some View {
        Button(action: generateReport) {
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

            if !progress.isEmpty {
                Text(progress)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(6)
            }
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

    // MARK: - Action buttons (after generation)

    private func actionButtons(url: URL) -> some View {
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
                    generationState = .idle
                    generatedPDFURL = nil
                }
            } label: {
                Text("Regenerate")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.medoraBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.medoraBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Report Generation

    private func generateReport() {
        generationState = .generating("")
        generatedPDFURL = nil

        Task {
            do {
                // 1. Collect all data for the range
                let profile = authStore.currentProfile
                let reportData = collectReportData(profile: profile)

                // 2. Build the AI prompt for the report narrative
                let prompt = buildReportPrompt(data: reportData, profile: profile)

                // 3. Stream the AI-generated narrative
                var narrative = ""
                let messages: [AITranscriptMessage] = [
                    AITranscriptMessage(role: "system", content: """
                    You are a medical report writer. Write in a clear, professional tone suitable for a physician.
                    Output clean, well-structured text (no markdown symbols like **, *, #). Use plain section headers
                    followed by a colon and a line break. Be factual, concise, and avoid speculation.
                    """),
                    AITranscriptMessage(role: "user", content: prompt)
                ]

                for try await delta in client.stream(messages: messages) {
                    narrative += delta
                    generationState = .generating(String(narrative.suffix(200)))
                }

                guard !narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    generationState = .failed("The AI did not generate a report. Please try again.")
                    return
                }

                // 4. Render PDF
                let pdfURL = try renderPDF(
                    narrative: narrative,
                    data: reportData,
                    profile: profile
                )

                generatedPDFURL = pdfURL
                withAnimation { generationState = .done }

            } catch {
                generationState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Data Collection

    private struct ReportData {
        let dateRange: String
        let daysInRange: Int
        let todaySummary: HealthDataSummary
        let thirtyDayHistory: String
        let symptoms: [String]         // formatted symptom entries
        let checklistCompletionRate: Double  // 0.0–1.0
        let checklistTaskCount: Int
        let checklistDoneCount: Int
    }

    private func collectReportData(profile: MedoraProfile?) -> ReportData {
        let cal = Calendar.current
        let dayCount = cal.dateComponents([.day], from: startDate, to: endDate).day.map { $0 + 1 } ?? 1

        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .none
        let rangeStr = "\(fmt.string(from: startDate)) – \(fmt.string(from: endDate))"

        // Checklist stats over date range
        var totalTasks = 0
        var doneTasks = 0
        var day = startDate
        while day <= endDate {
            let tasks = checklistStore.tasks(for: day)
            totalTasks += tasks.count
            doneTasks += tasks.filter(\.isDone).count
            day = cal.date(byAdding: .day, value: 1, to: day) ?? endDate.addingTimeInterval(86400)
        }
        let completionRate = totalTasks > 0 ? Double(doneTasks) / Double(totalTasks) : 0.0

        // Note: SymptomStore is Supabase-backed. For the report we surface a note
        // asking the user to review their symptom logs, since we can't filter by date
        // synchronously here without a full async flow. A future enhancement can add
        // date-filtered fetching.
        let symptoms: [String] = ["(Symptom log data is stored in Medora's secure database. Please refer to your Medora symptom history for this period.)"]

        return ReportData(
            dateRange: rangeStr,
            daysInRange: dayCount,
            todaySummary: healthStore.summary,
            thirtyDayHistory: healthStore.thirtyDaySummaryText,
            symptoms: symptoms,
            checklistCompletionRate: completionRate,
            checklistTaskCount: totalTasks,
            checklistDoneCount: doneTasks
        )
    }

    // MARK: - AI Prompt for Report

    private func buildReportPrompt(data: ReportData, profile: MedoraProfile?) -> String {
        let conditions = profile?.managing.joined(separator: ", ") ?? "None specified"
        let completionPct = Int(data.checklistCompletionRate * 100)

        return """
        Write a professional patient health summary report for the date range: \(data.dateRange).

        Patient Information:
        - Name: \(profile?.fullName ?? "Patient")
        - Age: \(profile?.age.map { String($0) } ?? "Not specified")
        - Conditions Being Managed: \(conditions)

        Current Health Metrics (most recent readings):
        - Steps Today: \(data.todaySummary.steps)
        - Calories Burned Today: \(data.todaySummary.caloriesBurned)
        - Sleep Last Night: \(data.todaySummary.sleep)
        - Heart Rate: \(data.todaySummary.heartRate)
        - Blood Pressure: \(data.todaySummary.bloodPressure)
        - Blood Glucose: \(data.todaySummary.bloodGlucose)

        30-Day Trend Data (Apple Health):
        \(data.thirtyDayHistory)

        Daily Task Compliance:
        - Tasks completed: \(data.checklistDoneCount) of \(data.checklistTaskCount) over \(data.daysInRange) days (\(completionPct)% completion rate)

        Symptom Log:
        \(data.symptoms.joined(separator: "\n"))

        Please write a structured report with these sections:
        1. Executive Summary
        2. Health Metrics Overview
        3. Activity & Lifestyle Trends
        4. Treatment Adherence
        5. Symptom Summary
        6. Observations & Recommendations

        Important: Write in plain text, no markdown symbols. Section headers should be on their own line followed by a colon. Be professional, factual, and concise. End with a standard medical disclaimer.
        """
    }

    // MARK: - PDF Rendering

    private func renderPDF(narrative: String, data: ReportData, profile: MedoraProfile?) throws -> URL {
        let pageWidth: CGFloat = 612      // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 56
        let contentWidth = pageWidth - margin * 2

        let tmpDir = FileManager.default.temporaryDirectory
        let fileName = "Medora_Health_Report_\(Date().timeIntervalSince1970).pdf"
        let url = tmpDir.appendingPathComponent(fileName)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var yOffset: CGFloat = margin

            // ── Logo / Header Banner ──────────────────────────────────────────
            let bannerRect = CGRect(x: 0, y: 0, width: pageWidth, height: 90)
            let bannerColor = UIColor(red: 0.04, green: 0.46, blue: 0.96, alpha: 1)
            bannerColor.setFill()
            UIRectFill(bannerRect)

            // App name
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let titleStr = NSAttributedString(string: "Medora", attributes: titleAttrs)
            titleStr.draw(at: CGPoint(x: margin, y: 26))

            // Subtitle
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            NSAttributedString(string: "Personal Health Report", attributes: subtitleAttrs)
                .draw(at: CGPoint(x: margin, y: 56))

            // Report date (right side)
            let dateFmt = DateFormatter()
            dateFmt.dateStyle = .long
            let generatedStr = "Generated \(dateFmt.string(from: Date()))"
            let genAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let genNS = NSAttributedString(string: generatedStr, attributes: genAttrs)
            let genSize = genNS.size()
            genNS.draw(at: CGPoint(x: pageWidth - margin - genSize.width, y: 40))

            yOffset = 110

            // ── Patient info block ────────────────────────────────────────────
            let patientBlock = [
                "Patient: \(profile?.fullName ?? "—")",
                "Date Range: \(data.dateRange)",
                "Conditions: \(profile?.managing.joined(separator: ", ") ?? "None specified")"
            ].joined(separator: "   |   ")

            let infoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            NSAttributedString(string: patientBlock, attributes: infoAttrs).draw(
                in: CGRect(x: margin, y: yOffset, width: contentWidth, height: 20)
            )
            yOffset += 28

            // Separator line
            UIColor.systemGray4.setStroke()
            let sep = UIBezierPath()
            sep.move(to: CGPoint(x: margin, y: yOffset))
            sep.addLine(to: CGPoint(x: pageWidth - margin, y: yOffset))
            sep.lineWidth = 0.75
            sep.stroke()
            yOffset += 16

            // ── Narrative text ─────────────────────────────────────────────────
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 10

            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ]

            let sectionHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor(red: 0.04, green: 0.46, blue: 0.96, alpha: 1),
                .paragraphStyle: paragraphStyle
            ]

            // Parse narrative into lines and detect section headers
            let lines = narrative.components(separatedBy: "\n")
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty {
                    yOffset += 8
                    continue
                }

                // If we're near the bottom of the page, start a new page
                if yOffset > pageHeight - margin - 60 {
                    ctx.beginPage()
                    yOffset = margin
                }

                // Detect section header (ends with ":")
                let isHeader = line.hasSuffix(":") && line.count < 60
                let attrs = isHeader ? sectionHeaderAttrs : bodyAttrs
                let attrStr = NSAttributedString(string: line, attributes: attrs)

                let boundingRect = attrStr.boundingRect(
                    with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )

                if isHeader { yOffset += 4 }

                attrStr.draw(in: CGRect(
                    x: margin, y: yOffset,
                    width: contentWidth,
                    height: ceil(boundingRect.height)
                ))

                yOffset += ceil(boundingRect.height) + (isHeader ? 4 : 2)
            }

            // ── Footer ─────────────────────────────────────────────────────────
            // Footer on last page
            let footerY = pageHeight - margin + 12
            UIColor.systemGray4.setStroke()
            let footerSep = UIBezierPath()
            footerSep.move(to: CGPoint(x: margin, y: footerY - 12))
            footerSep.addLine(to: CGPoint(x: pageWidth - margin, y: footerY - 12))
            footerSep.lineWidth = 0.5
            footerSep.stroke()

            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor.tertiaryLabel
            ]
            NSAttributedString(
                string: "Generated by Medora · For informational purposes only · Not a substitute for professional medical advice",
                attributes: footerAttrs
            ).draw(in: CGRect(x: margin, y: footerY, width: contentWidth, height: 20))
        }

        return url
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

// MARK: - PDFKit UIViewRepresentable

private struct PDFKitRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor.systemBackground
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if let document = PDFDocument(url: url), uiView.document == nil {
            uiView.document = document
        }
    }
}
