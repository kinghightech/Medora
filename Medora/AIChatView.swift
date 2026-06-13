//
//  AIChatView.swift
//  Medora
//
//  Created by Aahish Abbani on 6/11/26.
//

import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct AIChatView: View {
    @ObservedObject var healthStore: HealthStore
    @ObservedObject var authStore: AuthStore
    @ObservedObject var checklistStore: ChecklistStore

    @State private var messages: [AIChatMessage] = [
        AIChatMessage(
            role: .assistant,
            text: "Hi, I'm Aura AI. I'm your personal health companion. Ask me anything about your health and I can help you."
        )
    ]
    @State private var inputText = ""
    @State private var pendingAttachment: AIAttachment?
    @State private var isSending = false
    @State private var isShowingFileImporter = false
    @State private var fileImportError: String?

    // Checklist proposal state
    @State private var pendingChecklistProposal: [String] = []
    @State private var proposalSelectedItems: Set<Int> = []
    @State private var showChecklistSuccessToast = false
    @State private var proposalSourceMessageID: UUID?

    // Summarize sheet
    @State private var isShowingSummarize = false

    private let client = FeatherlessAIClient()

    var body: some View {
        ZStack {
            MedoraBackground()
                .ignoresSafeArea()

            if isUnderage {
                ageGateView
            } else {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(messages) { message in
                                    AIMessageBubble(message: message)
                                        .id(message.id)
                                }

                                // Checklist proposal card appears inline after the last AI message
                                if !pendingChecklistProposal.isEmpty {
                                    ChecklistProposalCard(
                                        items: pendingChecklistProposal,
                                        selectedItems: $proposalSelectedItems,
                                        onApprove: approveChecklist,
                                        onDismiss: dismissChecklist
                                    )
                                    .id("proposal-card")
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }

                                if isSending {
                                    AIMessageBubble(
                                        message: AIChatMessage(
                                            role: .assistant,
                                            text: "Thinking..."
                                        )
                                    )
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 16)
                            .padding(.bottom, 18)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: messages.count) {
                            scrollToBottom(proxy)
                        }
                        .onChange(of: messages.last?.text) {
                            scrollToBottom(proxy)
                        }
                        .onChange(of: isSending) {
                            scrollToBottom(proxy)
                        }
                        .onChange(of: pendingChecklistProposal.isEmpty) {
                            if !pendingChecklistProposal.isEmpty {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        proxy.scrollTo("proposal-card", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        if let pendingAttachment {
                            AttachmentChip(attachment: pendingAttachment) {
                                self.pendingAttachment = nil
                            }
                            .padding(.horizontal, 14)
                        }

                        if let fileImportError {
                            Text(fileImportError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                        }

                        HStack(alignment: .bottom, spacing: 10) {
                            Button {
                                fileImportError = nil
                                isShowingFileImporter = true
                            } label: {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(AIIconButtonStyle())
                            .accessibilityLabel("Attach document")

                            TextField("Message Aura AI", text: $inputText, axis: .vertical)
                                .lineLimit(1...4)
                                .textFieldStyle(.plain)
                                .font(.system(size: 16))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(Color.medoraField, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.medoraHairline, lineWidth: 1)
                                )
                                .submitLabel(.send)
                                .onSubmit(sendMessage)

                            Button(action: sendMessage) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(AISendButtonStyle())
                            .disabled(!canSend)
                            .opacity(canSend ? 1 : 0.5)
                            .accessibilityLabel("Send")
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }
                    .padding(.top, 12)
                    .background(.ultraThinMaterial)
                }
            }

            // Success toast
            if showChecklistSuccessToast {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                        Text("Added to your checklist!")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.medoraGreen, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingSummarize = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Summarize")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [Color.medoraBlue, Color(red: 0.38, green: 0.2, blue: 0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Generate health summary report")
            }
        }
        .sheet(isPresented: $isShowingSummarize) {
            NavigationStack {
                SummarizeView(
                    healthStore: healthStore,
                    checklistStore: checklistStore,
                    authStore: authStore
                )
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: Self.importContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Age gating & tailoring

    private var userAge: Int? {
        authStore.currentProfile?.age
    }

    /// Children under 13 are blocked from the AI companion (and shown a gate instead).
    private var isUnderage: Bool {
        if let age = userAge { return age < 13 }
        return false
    }

    private enum AgeBand {
        case youth      // 13–24
        case adult      // 25–54
        case senior     // 55+
        case unspecified
    }

    private var ageBand: AgeBand {
        guard let age = userAge else { return .unspecified }
        switch age {
        case ..<13: return .unspecified   // handled by the age gate
        case 13...24: return .youth
        case 25...54: return .adult
        default: return .senior
        }
    }

    /// Guidance injected into the system prompt so the model adapts tone and
    /// examples to the user's life stage.
    private var audienceGuidance: String {
        switch ageBand {
        case .youth:
            return """
            The user is a teen or young adult (ages 13–24). Use a warm, encouraging, and relatable tone with clear, \
            jargon-free explanations. Relate advice to school, sports, social life, and building healthy habits early, \
            and be especially supportive and non-judgmental about sleep, screen time, diet, stress, and body image.
            """
        case .adult:
            return """
            The user is an adult (ages 25–54). Use a direct, practical, and respectful tone. Give efficient, \
            evidence-based guidance that fits a busy life balancing work, family, and health, and connect advice to \
            long-term prevention and managing everyday stress.
            """
        case .senior:
            return """
            The user is an older adult (ages 55+). Use a clear, patient, and respectful tone without slang. Keep steps \
            simple and easy to follow, and be attentive to mobility, medication management, chronic-condition care, and \
            staying independent. Gently encourage confirming changes with their doctor.
            """
        case .unspecified:
            return "Tailor your tone and examples to a general adult audience."
        }
    }

    private var ageGateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Color.medoraBlue)

            Text("You need to be 13 or older to use Aura AI")
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)

            Text("Aura AI isn't available for users under 13. Please ask a parent or guardian for help.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: 360)
    }

    private static let importContentTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .text, .json, .commaSeparatedText]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return types
    }()

    private var canSend: Bool {
        !isSending && !isUnderage && (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingAttachment != nil)
    }

    // MARK: - Send

    private func sendMessage() {
        guard canSend else { return }

        // Dismiss any prior proposal when the user sends a new message
        withAnimation { pendingChecklistProposal = [] }

        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachment = pendingAttachment
        let displayText = userText.isEmpty ? "Please explain this attachment." : userText
        let apiText = buildUserPrompt(text: displayText, attachment: attachment)

        messages.append(
            AIChatMessage(
                role: .user,
                text: displayText,
                attachmentName: attachment?.fileName
            )
        )
        inputText = ""
        pendingAttachment = nil
        fileImportError = nil
        isSending = true

        Task {
            let transcript = transcriptMessages(addingLatestUserText: apiText)
            var assembled = ""
            var assistantIndex: Int?

            do {
                for try await delta in client.stream(messages: transcript) {
                    assembled += delta

                    if let index = assistantIndex {
                        messages[index].text = stripProposalBlock(from: assembled)
                    } else {
                        // First token arrived: drop the "Thinking..." indicator and show the bubble.
                        isSending = false
                        messages.append(AIChatMessage(role: .assistant, text: stripProposalBlock(from: assembled)))
                        assistantIndex = messages.count - 1
                    }
                }

                if assistantIndex == nil {
                    messages.append(
                        AIChatMessage(role: .assistant, text: "The AI service did not return a message.")
                    )
                }

                // After stream ends, check if the full response contained a checklist proposal.
                parseChecklistProposal(from: assembled, messageIndex: assistantIndex)

            } catch {
                if let index = assistantIndex, !assembled.isEmpty {
                    // Keep whatever streamed in before the failure.
                    messages[index].text = stripProposalBlock(from: assembled)
                } else {
                    messages.append(AIChatMessage(role: .assistant, text: error.localizedDescription))
                }
            }

            isSending = false
        }
    }

    // MARK: - Checklist Proposal Parsing

    private let proposalStart = "CHECKLIST_PROPOSAL_START"
    private let proposalEnd   = "CHECKLIST_PROPOSAL_END"

    /// Strips the raw `CHECKLIST_PROPOSAL_START…END` block from a string for display.
    private func stripProposalBlock(from text: String) -> String {
        guard let startRange = text.range(of: proposalStart) else { return text }
        let before = String(text[text.startIndex..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return before
    }

    /// Detects and extracts the proposal block, populating `pendingChecklistProposal`.
    private func parseChecklistProposal(from text: String, messageIndex: Int?) {
        guard let startRange = text.range(of: proposalStart),
              let endRange   = text.range(of: proposalEnd),
              startRange.upperBound < endRange.lowerBound else { return }

        let block = String(text[startRange.upperBound..<endRange.lowerBound])
        let items = block
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("• ") }
            .map { line -> String in
                if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
                if line.hasPrefix("• ") { return String(line.dropFirst(2)) }
                return line
            }
            .filter { !$0.isEmpty }

        guard !items.isEmpty else { return }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            pendingChecklistProposal = items
            proposalSelectedItems = Set(items.indices)
            if let idx = messageIndex {
                proposalSourceMessageID = messages[idx].id
            }
        }
    }

    // MARK: - Checklist Actions

    private func approveChecklist() {
        let today = Date()
        for index in proposalSelectedItems.sorted() where index < pendingChecklistProposal.count {
            checklistStore.addTask(pendingChecklistProposal[index], on: today)
        }

        withAnimation {
            pendingChecklistProposal = []
            showChecklistSuccessToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showChecklistSuccessToast = false }
        }
    }

    private func dismissChecklist() {
        withAnimation { pendingChecklistProposal = [] }
    }

    // MARK: - System Prompt

    private func transcriptMessages(addingLatestUserText latestUserText: String) -> [AITranscriptMessage] {
        let conditions = authStore.currentProfile?.managing.joined(separator: ", ") ?? "None specified"
        let healthData = """
        Calories: \(healthStore.summary.caloriesBurned)
        Steps: \(healthStore.summary.steps)
        Sleep: \(healthStore.summary.sleep)
        Heart Rate: \(healthStore.summary.heartRate)
        Blood Pressure: \(healthStore.summary.bloodPressure)
        Blood Glucose: \(healthStore.summary.bloodGlucose)
        """

        let systemPrompt = """
        You are Aura AI, a highly advanced personal health companion inside the Medora app.
        You strictly follow these rules:
        1. ONLY answer questions about health, medicine, wellness, and biology.
        2. If the user asks about ANYTHING else (e.g. math, coding, general knowledge, movies), you must politely refuse and remind them you are a health companion.
        3. Do NOT lie or invent medical data. Be transparent about your limitations and do not claim to diagnose or prescribe.
        4. Format your answers in Markdown. Use short paragraphs, **bold** for key points, and bullet or numbered lists for steps.

        Audience:
        \(audienceGuidance)

        Here is the user's current health context from Apple Health and their profile:
        Managing Conditions: \(conditions)
        Today's Health Data:
        \(healthData)

        30-Day Trend Data:
        \(healthStore.thirtyDaySummaryText)

        Use this data naturally when answering. Reference trends when relevant (e.g. "Over the past 30 days, your average sleep has been…").

        ── CHECKLIST SKILL ───────────────────────────────────────────────────────
        You have the ability to propose a checklist of health tasks. USE THIS SKILL
        SPARINGLY — only when the user shares a doctor's note, discharge summary,
        clinical paper, or detailed medical instruction that contains 3–8 specific,
        concrete, actionable tasks (e.g. "take X medication", "schedule follow-up",
        "do 30 min of walking").

        When warranted, append EXACTLY this block at the very END of your reply and
        nothing else after it:

        CHECKLIST_PROPOSAL_START
        - Task one
        - Task two
        - Task three
        CHECKLIST_PROPOSAL_END

        Rules for this skill:
        • Do NOT emit this block for general health questions or conversations.
        • Do NOT invent tasks not grounded in the attached document/context.
        • Each task must be short (≤10 words), specific, and actionable.
        • 3 minimum, 8 maximum tasks.
        • If you are unsure whether tasks are warranted, do NOT emit the block.
        ──────────────────────────────────────────────────────────────────────────
        """

        var transcript = [
            AITranscriptMessage(
                role: "system",
                content: systemPrompt
            )
        ]

        for message in messages.dropLast() {
            let role = message.role == .assistant ? "assistant" : "user"
            transcript.append(AITranscriptMessage(role: role, content: message.text))
        }

        transcript.append(AITranscriptMessage(role: "user", content: latestUserText))
        return transcript
    }

    private func buildUserPrompt(text: String, attachment: AIAttachment?) -> String {
        guard let attachment else {
            return text
        }

        return """
        \(text)

        Attached document:
        Name: \(attachment.fileName)
        Type: \(attachment.fileType)

        Extracted content:
        \(attachment.extractedText)
        """
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }

            pendingAttachment = try AIDocumentExtractor.extractAttachment(from: url)
            fileImportError = nil
        } catch {
            fileImportError = error.localizedDescription
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Checklist Proposal Card

private struct ChecklistProposalCard: View {
    let items: [String]
    @Binding var selectedItems: Set<Int>
    let onApprove: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        LinearGradient(
                            colors: [Color.medoraBlue, Color(red: 0.38, green: 0.2, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Aura AI Suggestions")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Tap to deselect, then add to checklist")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss checklist suggestion")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 16)

            // Items
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            if selectedItems.contains(index) {
                                selectedItems.remove(index)
                            } else {
                                selectedItems.insert(index)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedItems.contains(index) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(selectedItems.contains(index) ? Color.medoraBlue : Color.secondary.opacity(0.4))
                                .animation(.easeOut(duration: 0.15), value: selectedItems.contains(index))

                            Text(item)
                                .font(.system(size: 15))
                                .foregroundStyle(selectedItems.contains(index) ? .primary : .secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }

            Divider().padding(.horizontal, 16)

            // Action buttons
            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onApprove) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text(selectedItems.isEmpty ? "Add None" : "Add \(selectedItems.count) to Checklist")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        selectedItems.isEmpty
                            ? AnyShapeStyle(Color.secondary.opacity(0.4))
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color.medoraBlue, Color(red: 0.38, green: 0.2, blue: 0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                              )),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedItems.isEmpty)
            }
            .padding(16)
        }
        .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.medoraBlue.opacity(0.5), Color(red: 0.38, green: 0.2, blue: 0.9).opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.medoraBlue.opacity(0.12), radius: 20, x: 0, y: 8)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Message Bubble

private struct AIMessageBubble: View {
    let message: AIChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 36)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let attachmentName = message.attachmentName {
                    Label(attachmentName, systemImage: "doc.text")
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(isUser ? .white.opacity(0.86) : .secondary)
                }

                if isUser {
                    Text(message.text)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    MarkdownText(text: message.text)
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isUser ? AnyShapeStyle(Color.medoraBlue.gradient) : AnyShapeStyle(Color(UIColor.systemBackground)))
            )
            .shadow(color: .black.opacity(isUser ? 0 : 0.05), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isUser ? .clear : Color.medoraHairline, lineWidth: 1)
            )
            .frame(maxWidth: 310, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Attachment chip

private struct AttachmentChip: View {
    let attachment: AIAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(Color.medoraBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(attachment.fileType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .padding(12)
        .background(Color.medoraSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.medoraHairline, lineWidth: 1)
        )
    }
}

// MARK: - Button styles

private struct AIIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.medoraBlue)
            .background(Color.medoraSurface, in: Circle())
            .overlay(
                Circle()
                    .stroke(Color.medoraHairline, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct AISendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Color.medoraBlue, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Data model

private struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
    var attachmentName: String?
}

private struct AIAttachment {
    let fileName: String
    let fileType: String
    let extractedText: String
}

// MARK: - Document extraction

private enum AIDocumentExtractor {
    static func extractAttachment(from url: URL) throws -> AIAttachment {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = url.lastPathComponent
        let fileType = UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? "Document"
        let extractedText = try extractText(from: url)

        return AIAttachment(
            fileName: fileName,
            fileType: fileType,
            extractedText: limitText(extractedText)
        )
    }

    private static func extractText(from url: URL) throws -> String {
        let type = UTType(filenameExtension: url.pathExtension)

        if type == .pdf {
            return try extractPDFText(from: url)
        }

        if type?.conforms(to: .text) == true || type == .json || type == .commaSeparatedText {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIDocumentError.emptyDocument
            }

            return text
        }

        throw AIDocumentError.unsupportedFile
    }

    private static func extractPDFText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw AIDocumentError.unreadableDocument
        }

        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIDocumentError.emptyDocument
        }

        return text
    }

    private static func limitText(_ text: String) -> String {
        let maxCharacters = 12_000

        guard text.count > maxCharacters else {
            return text
        }

        let endIndex = text.index(text.startIndex, offsetBy: maxCharacters)
        return String(text[..<endIndex]) + "\n\n[Document truncated for the demo chat context.]"
    }
}

private enum AIDocumentError: LocalizedError {
    case emptyDocument
    case unreadableDocument
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "I could not find readable text in that document."
        case .unreadableDocument:
            return "I could not read that document."
        case .unsupportedFile:
            return "Please attach a PDF, Markdown, text, JSON, or CSV file for this demo."
        }
    }
}

// MARK: - Markdown rendering

/// Lightweight Markdown renderer for assistant replies. Handles the subset that
/// chat models actually emit: headings, bullet/numbered lists, blockquotes,
/// fenced code, horizontal rules, and inline emphasis. Re-parses cheaply on every
/// streamed token, so partial Markdown renders gracefully as it arrives.
private struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownParser.blocks(from: text).enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func render(_ block: MarkdownParser.Block) -> some View {
        switch block {
        case .heading(let level, let content):
            inline(content)
                .font(.system(size: headingSize(level), weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let content):
            inline(content)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        inline(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).").fontWeight(.semibold)
                        inline(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .quote(let content):
            inline(content)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 3)
                }

        case .code(let content):
            Text(content)
                .font(.system(size: 14, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case .rule:
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    /// Renders inline emphasis (**bold**, *italic*, `code`, links) via AttributedString.
    private func inline(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(string)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 20
        case 3: return 18
        default: return 16
        }
    }
}

private enum MarkdownParser {
    enum Block {
        case heading(Int, String)
        case paragraph(String)
        case bullet([String])
        case numbered([String])
        case quote(String)
        case code(String)
        case rule
    }

    static func blocks(from text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if line.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1 // consume closing fence (if present)
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if line == "---" || line == "***" || line == "___" {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            if let heading = heading(from: line) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if isBullet(line) {
                flushParagraph()
                var items: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isBullet(candidate) else { break }
                    items.append(String(candidate.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.bullet(items))
                continue
            }

            if isNumbered(line) {
                flushParagraph()
                var items: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isNumbered(candidate) else { break }
                    items.append(numberedContent(candidate))
                    index += 1
                }
                blocks.append(.numbered(items))
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }

            paragraph.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func heading(from line: String) -> Block? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return .heading(level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func isNumbered(_ line: String) -> Bool {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return false }
        let after = line.dropFirst(digits.count)
        return after.hasPrefix(". ") || after.hasPrefix(") ")
    }

    private static func numberedContent(_ line: String) -> String {
        let digits = line.prefix(while: { $0.isNumber })
        return String(line.dropFirst(digits.count + 2)).trimmingCharacters(in: .whitespaces)
    }
}
