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
    @State private var messages: [AIChatMessage] = [
        AIChatMessage(
            role: .assistant,
            text: "Ask me a question, or attach a document and I can help summarize or explain it."
        )
    ]
    @State private var inputText = ""
    @State private var pendingAttachment: AIAttachment?
    @State private var isSending = false
    @State private var isShowingFileImporter = false
    @State private var fileImportError: String?

    private let client = FeatherlessAIClient()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(messages) { message in
                            AIMessageBubble(message: message)
                                .id(message.id)
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
                .background(Color.medoraBackground)
                .onChange(of: messages.count) {
                    scrollToBottom(proxy)
                }
                .onChange(of: isSending) {
                    scrollToBottom(proxy)
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

                    TextField("Message Medora AI", text: $inputText, axis: .vertical)
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
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.pdf, .plainText, .text, .json, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private var canSend: Bool {
        !isSending && (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingAttachment != nil)
    }

    private func sendMessage() {
        guard canSend else { return }

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
            do {
                let reply = try await client.send(messages: transcriptMessages(addingLatestUserText: apiText))
                messages.append(AIChatMessage(role: .assistant, text: reply))
            } catch {
                messages.append(
                    AIChatMessage(
                        role: .assistant,
                        text: error.localizedDescription
                    )
                )
            }

            isSending = false
        }
    }

    private func transcriptMessages(addingLatestUserText latestUserText: String) -> [AITranscriptMessage] {
        var transcript = [
            AITranscriptMessage(
                role: "system",
                content: """
                You are Medora AI, a concise assistant inside a health demo app. Help with general questions and explain user-provided documents clearly. Do not claim to diagnose, prescribe, or replace a clinician.
                """
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

                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundStyle(isUser ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isUser ? Color.medoraBlue : Color.medoraSurface)
            )
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

private struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    var attachmentName: String?
}

private struct AIAttachment {
    let fileName: String
    let fileType: String
    let extractedText: String
}

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
            return "Please attach a PDF, text, JSON, or CSV file for this demo."
        }
    }
}
