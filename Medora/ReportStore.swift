//
//  ReportStore.swift
//  Medora
//
//  Owns long-lived health-report generation. Generation runs inside a Task held
//  by the store (not by a view), so the user can leave the Summarize screen and
//  the report keeps generating in the background. Finished reports are written
//  to permanent on-disk storage, surface on the Profile tab, and trigger both a
//  system notification and an in-app banner the moment they're ready.
//

import Combine
import Foundation
import PDFKit
import SwiftUI
import UIKit
import UserNotifications

// MARK: - Model

/// A completed, saved health report. The PDF lives on disk in the app's
/// documents directory; only the file *name* is persisted, because the absolute
/// container path can change between launches — we recompute the URL on demand.
struct HealthReport: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let dateRangeText: String
    let createdAt: Date
    let fileName: String

    var fileURL: URL {
        ReportStore.reportsDirectory.appendingPathComponent(fileName)
    }
}

// MARK: - Store

@MainActor
final class ReportStore: ObservableObject {
    /// Previously generated reports, newest first.
    @Published private(set) var reports: [HealthReport] = []

    /// Non-nil while a report is generating in the background.
    @Published private(set) var activeJob: ActiveJob?

    /// Set when a report finishes so the UI can surface an in-app banner. The
    /// banner clears this once it's shown / tapped / times out.
    @Published var lastCompleted: HealthReport?

    /// Most recent failure message, surfaced by the Summarize screen.
    @Published var lastError: String?

    /// A generation in flight. `progress` is the tail of the streamed narrative,
    /// shown live if the user keeps the Summarize screen open.
    struct ActiveJob: Equatable {
        let id: UUID
        let dateRangeText: String
        let startedAt: Date
        var progress: String
    }

    enum ReportError: LocalizedError {
        case empty
        var errorDescription: String? {
            switch self {
            case .empty: return "The AI did not generate a report. Please try again."
            }
        }
    }

    private let client = FeatherlessAIClient()
    private var generationTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    private var lastPrewarm: Date?

    private let storageKey = "medora.reports.index"
    private let defaults = UserDefaults.standard

    /// Permanent folder for generated PDFs.
    static let reportsDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("HealthReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var isGenerating: Bool { activeJob != nil }

    init() {
        load()
    }

    // MARK: - Pre-warming

    /// Fires a tiny throwaway request so the (often cold) serverless model is
    /// loaded by the time the user taps Generate. Cheap, fire-and-forget, and
    /// rate-limited so re-opening the screen doesn't spam the API.
    func prewarm() {
        guard activeJob == nil else { return }
        if let last = lastPrewarm, Date().timeIntervalSince(last) < 120 { return }
        lastPrewarm = Date()

        prewarmTask?.cancel()
        prewarmTask = Task { [client] in
            let ping: [AITranscriptMessage] = [
                AITranscriptMessage(role: "user", content: "Reply with the single word: ready")
            ]
            // Drain a couple of tokens to confirm the model is warm, then drop it.
            do {
                for try await _ in client.stream(messages: ping, maxTokens: 1) {
                    if Task.isCancelled { return }
                    break
                }
            } catch {
                // Pre-warm is best-effort; ignore failures.
            }
        }
    }

    // MARK: - Generation

    /// Everything the report needs, snapshotted on the main actor at kickoff so
    /// the background work never touches the live stores.
    struct ReportInput {
        let startDate: Date
        let endDate: Date
        let profileName: String
        let conditions: String
        let age: Int?
        let summary: HealthDataSummary
        let thirtyDayHistory: String
        let checklistDoneCount: Int
        let checklistTaskCount: Int
        let daysInRange: Int

        var rangeText: String { ReportStore.rangeText(start: startDate, end: endDate) }
    }

    /// Kicks off background generation. No-op if one is already running.
    func startGeneration(startDate: Date,
                         endDate: Date,
                         healthStore: HealthStore,
                         checklistStore: ChecklistStore,
                         profile: MedoraProfile?) {
        guard activeJob == nil else { return }

        // Snapshot all inputs synchronously on the main actor.
        let cal = Calendar.current
        var totalTasks = 0
        var doneTasks = 0
        var day = startDate
        while day <= endDate {
            let tasks = checklistStore.tasks(for: day)
            totalTasks += tasks.count
            doneTasks += tasks.filter(\.isDone).count
            day = cal.date(byAdding: .day, value: 1, to: day) ?? endDate.addingTimeInterval(86400)
        }
        let dayCount = cal.dateComponents([.day], from: startDate, to: endDate).day.map { $0 + 1 } ?? 1

        let input = ReportInput(
            startDate: startDate,
            endDate: endDate,
            profileName: profile?.fullName ?? "Patient",
            conditions: (profile?.managing.isEmpty == false) ? profile!.managing.joined(separator: ", ") : "None specified",
            age: profile?.age,
            summary: healthStore.summary,
            thirtyDayHistory: healthStore.thirtyDaySummaryText,
            checklistDoneCount: doneTasks,
            checklistTaskCount: totalTasks,
            daysInRange: dayCount
        )

        let jobID = UUID()
        activeJob = ActiveJob(id: jobID,
                              dateRangeText: input.rangeText,
                              startedAt: Date(),
                              progress: "")
        lastError = nil

        generationTask = Task { [weak self] in
            await self?.run(jobID: jobID, input: input)
        }
    }

    /// Stops the in-flight generation (explicit user action only — leaving the
    /// screen does NOT cancel).
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        activeJob = nil
    }

    private func run(jobID: UUID, input: ReportInput) async {
        // Ask iOS for extra runtime so a brief app-background mid-generation
        // (e.g. the user locks the phone) doesn't suspend us instantly.
        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "MedoraReportGeneration") {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }
        defer {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }

        do {
            let messages: [AITranscriptMessage] = [
                AITranscriptMessage(role: "system", content: Self.systemPrompt),
                AITranscriptMessage(role: "user", content: Self.buildReportPrompt(input: input)),
            ]

            var narrative = ""
            for try await delta in client.stream(messages: messages, maxTokens: 2500) {
                if Task.isCancelled { return }
                narrative += delta
                if activeJob?.id == jobID {
                    activeJob?.progress = String(narrative.suffix(200))
                }
            }

            guard !Task.isCancelled else { return }

            let trimmed = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ReportError.empty }

            // Render to permanent storage.
            let createdAt = Date()
            let fileName = "Medora_Report_\(Int(createdAt.timeIntervalSince1970)).pdf"
            let url = Self.reportsDirectory.appendingPathComponent(fileName)
            try ReportPDFRenderer.render(narrative: narrative, input: input, to: url)

            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: url)
                return
            }

            let report = HealthReport(
                id: jobID,
                title: "Doctor's Report",
                dateRangeText: input.rangeText,
                createdAt: createdAt,
                fileName: fileName
            )

            reports.insert(report, at: 0)
            save()

            activeJob = nil
            generationTask = nil
            lastCompleted = report
            notifyCompletion(report)

        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            lastError = error.localizedDescription
            activeJob = nil
            generationTask = nil
        }
    }

    // MARK: - Library management

    func deleteReport(_ report: HealthReport) {
        try? FileManager.default.removeItem(at: report.fileURL)
        reports.removeAll { $0.id == report.id }
        save()
    }

    // MARK: - Notification

    private func notifyCompletion(_ report: HealthReport) {
        let content = UNMutableNotificationContent()
        content.title = "Your health report is ready"
        content.body = "Your Doctor's Report for \(report.dateRangeText) is saved to your profile."
        content.sound = .default
        content.userInfo = ["medora.reportID": report.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "medora.report.\(report.id.uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([HealthReport].self, from: data) else {
            return
        }
        // Drop entries whose PDF no longer exists on disk.
        reports = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        if reports.count != decoded.count { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reports) {
            defaults.set(data, forKey: storageKey)
        }
    }

    // MARK: - Prompt building

    static func rangeText(start: Date, end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .none
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }

    static let systemPrompt = """
    You are a medical report writer. Write in a clear, professional tone suitable for a physician.
    Output clean, well-structured text (no markdown symbols like **, *, #). Use plain section headers
    followed by a colon and a line break. Be factual, concise, and avoid speculation.
    """

    static func buildReportPrompt(input: ReportInput) -> String {
        let completionPct = input.checklistTaskCount > 0
            ? Int((Double(input.checklistDoneCount) / Double(input.checklistTaskCount)) * 100)
            : 0

        return """
        Write a professional patient health summary report for the date range: \(input.rangeText).

        Patient Information:
        - Name: \(input.profileName)
        - Age: \(input.age.map { String($0) } ?? "Not specified")
        - Conditions Being Managed: \(input.conditions)

        Current Health Metrics (most recent readings):
        - Steps Today: \(input.summary.steps)
        - Calories Burned Today: \(input.summary.caloriesBurned)
        - Sleep Last Night: \(input.summary.sleep)
        - Heart Rate: \(input.summary.heartRate)
        - Blood Pressure: \(input.summary.bloodPressure)
        - Blood Glucose: \(input.summary.bloodGlucose)

        30-Day Trend Data (Apple Health):
        \(input.thirtyDayHistory)

        Daily Task Compliance:
        - Tasks completed: \(input.checklistDoneCount) of \(input.checklistTaskCount) over \(input.daysInRange) days (\(completionPct)% completion rate)

        Symptom Log:
        (Symptom log data is stored in Medora's secure database. Please refer to your Medora symptom history for this period.)

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
}

// MARK: - PDF Rendering

/// Renders the AI narrative + patient header into a US-Letter PDF on disk.
/// Lifted out of the view so generation can run independently of any screen.
enum ReportPDFRenderer {
    static func render(narrative: String, input: ReportStore.ReportInput, to url: URL) throws {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 56
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var yOffset: CGFloat = margin

            // ── Header banner ───────────────────────────────────────────────
            let bannerColor = UIColor(red: 0.04, green: 0.46, blue: 0.96, alpha: 1)
            bannerColor.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: pageWidth, height: 90))

            NSAttributedString(string: "Medora", attributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                .foregroundColor: UIColor.white,
            ]).draw(at: CGPoint(x: margin, y: 26))

            NSAttributedString(string: "Personal Health Report", attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            ]).draw(at: CGPoint(x: margin, y: 56))

            let dateFmt = DateFormatter()
            dateFmt.dateStyle = .long
            let genNS = NSAttributedString(string: "Generated \(dateFmt.string(from: Date()))", attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            ])
            genNS.draw(at: CGPoint(x: pageWidth - margin - genNS.size().width, y: 40))

            yOffset = 110

            // ── Patient info block ──────────────────────────────────────────
            let patientBlock = [
                "Patient: \(input.profileName)",
                "Date Range: \(input.rangeText)",
                "Conditions: \(input.conditions)",
            ].joined(separator: "   |   ")

            NSAttributedString(string: patientBlock, attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel,
            ]).draw(in: CGRect(x: margin, y: yOffset, width: contentWidth, height: 20))
            yOffset += 28

            UIColor.systemGray4.setStroke()
            let sep = UIBezierPath()
            sep.move(to: CGPoint(x: margin, y: yOffset))
            sep.addLine(to: CGPoint(x: pageWidth - margin, y: yOffset))
            sep.lineWidth = 0.75
            sep.stroke()
            yOffset += 16

            // ── Narrative ───────────────────────────────────────────────────
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 10

            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle,
            ]
            let sectionHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor(red: 0.04, green: 0.46, blue: 0.96, alpha: 1),
                .paragraphStyle: paragraphStyle,
            ]

            for rawLine in narrative.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty {
                    yOffset += 8
                    continue
                }

                if yOffset > pageHeight - margin - 60 {
                    ctx.beginPage()
                    yOffset = margin
                }

                let isHeader = line.hasSuffix(":") && line.count < 60
                let attrStr = NSAttributedString(string: line, attributes: isHeader ? sectionHeaderAttrs : bodyAttrs)
                let boundingRect = attrStr.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )

                if isHeader { yOffset += 4 }
                attrStr.draw(in: CGRect(x: margin, y: yOffset, width: contentWidth, height: ceil(boundingRect.height)))
                yOffset += ceil(boundingRect.height) + (isHeader ? 4 : 2)
            }

            // ── Footer ──────────────────────────────────────────────────────
            let footerY = pageHeight - margin + 12
            UIColor.systemGray4.setStroke()
            let footerSep = UIBezierPath()
            footerSep.move(to: CGPoint(x: margin, y: footerY - 12))
            footerSep.addLine(to: CGPoint(x: pageWidth - margin, y: footerY - 12))
            footerSep.lineWidth = 0.5
            footerSep.stroke()

            NSAttributedString(
                string: "Generated by Medora · For informational purposes only · Not a substitute for professional medical advice",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: UIColor.tertiaryLabel,
                ]
            ).draw(in: CGRect(x: margin, y: footerY, width: contentWidth, height: 20))
        }
    }
}

// MARK: - Shared PDF preview (used by Summarize + Profile)

/// Wraps a `PDFView` for inline previews. Internal (not private) so both the
/// Summarize screen and the Profile report list can reuse it.
struct PDFKitRepresentable: UIViewRepresentable {
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
        if uiView.document?.documentURL != url, let document = PDFDocument(url: url) {
            uiView.document = document
        }
    }
}

// MARK: - Notification delegate (foreground presentation + tap routing)

/// Posted when the user taps a "report ready" notification, so the UI can jump
/// to the Profile tab.
extension Notification.Name {
    static let medoraOpenReports = Notification.Name("medora.openReports")
}

/// Presents Medora's local notifications while the app is in the foreground and
/// routes taps to the reports list. Install once at launch.
final class ReportNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReportNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("medora.report.") {
            NotificationCenter.default.post(name: .medoraOpenReports, object: nil)
        }
        completionHandler()
    }
}
