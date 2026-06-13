//
//  FeatherlessAIClient.swift
//  Medora
//
//  Created by Aahish Abbani on 6/11/26.
//

import Foundation

enum FeatherlessAIConfig {
    static let apiKey = "rc_fac6687b5c8a91cce27b924c01c1712248de446f80bc2f762940f446e3ac85f0"
    static let baseURL = URL(string: "https://api.featherless.ai/v1/chat/completions")!
    static let model = "Qwen/Qwen3-4B-Instruct-2507"
}

struct AITranscriptMessage {
    let role: String
    let content: String
}

struct FeatherlessAIClient {
    /// Streams the assistant reply token-by-token as it is generated, so the UI can
    /// render text the moment it arrives instead of waiting for the full completion.
    ///
    /// - Parameters:
    ///   - messages: The conversation transcript to send.
    ///   - maxTokens: Maximum response tokens (default 2000 for chat; use more for long reports).
    func stream(messages: [AITranscriptMessage], maxTokens: Int = 2000) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !FeatherlessAIConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw FeatherlessAIError.missingAPIKey
                    }

                    var request = URLRequest(url: FeatherlessAIConfig.baseURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(FeatherlessAIConfig.apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONEncoder().encode(
                        FeatherlessChatRequest(
                            model: FeatherlessAIConfig.model,
                            messages: messages.map { FeatherlessChatMessage(role: $0.role, content: $0.content) },
                            temperature: 0.4,
                            maxTokens: maxTokens,
                            stream: true,
                            // Disable Qwen3's extended "thinking" mode so thinking tokens
                            // don't eat the response budget or leak <think> tags into the UI.
                            thinkingBudget: 0
                        )
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw FeatherlessAIError.invalidResponse
                    }

                    guard (200..<300).contains(httpResponse.statusCode) else {
                        // On error the server returns a single JSON body, not an SSE stream.
                        var body = Data()
                        for try await line in bytes.lines {
                            body.append(Data(line.utf8))
                        }
                        let apiError = try? JSONDecoder().decode(FeatherlessErrorResponse.self, from: body)
                        throw FeatherlessAIError.requestFailed(apiError?.error.message ?? "Request failed with status \(httpResponse.statusCode).")
                    }

                    // Buffer used to strip <think>…</think> blocks that Qwen3 may still emit.
                    var thinkBuffer = ""
                    var insideThink = false

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }

                        if let data = payload.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(FeatherlessStreamChunk.self, from: data),
                           let delta = chunk.choices.first?.delta.content,
                           !delta.isEmpty {

                            // Strip <think>…</think> blocks on the fly.
                            let cleaned = filterThinkingTokens(delta, buffer: &thinkBuffer, inThink: &insideThink)
                            if !cleaned.isEmpty {
                                continuation.yield(cleaned)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Thinking-token filter

    /// Removes `<think>…</think>` spans that Qwen3 emits during chain-of-thought.
    /// Called incrementally on each streamed delta; carries mutable state across calls
    /// via `buffer` and `inThink`.
    private func filterThinkingTokens(_ delta: String, buffer: inout String, inThink: inout Bool) -> String {
        buffer += delta
        var output = ""

        while !buffer.isEmpty {
            if inThink {
                // We're inside a think block — consume until we find the closing tag.
                if let closeRange = buffer.range(of: "</think>") {
                    buffer.removeSubrange(buffer.startIndex..<closeRange.upperBound)
                    inThink = false
                    // Add a single newline after a think block so the visible text flows correctly.
                    output += "\n"
                } else {
                    // Closing tag hasn't arrived yet — keep buffering.
                    break
                }
            } else {
                // Not inside a think block — look for an opening tag.
                if let openRange = buffer.range(of: "<think>") {
                    // Emit everything before the tag.
                    output += String(buffer[buffer.startIndex..<openRange.lowerBound])
                    buffer.removeSubrange(buffer.startIndex..<openRange.upperBound)
                    inThink = true
                } else if buffer.hasSuffix("<") || buffer.hasSuffix("<t") ||
                          buffer.hasSuffix("<th") || buffer.hasSuffix("<thi") ||
                          buffer.hasSuffix("<thin") || buffer.hasSuffix("<think") ||
                          buffer.hasSuffix("<think>".prefix(buffer.count)) {
                    // Partial opening tag — hold the buffer in case next delta completes it.
                    // Emit everything except the potential partial tag.
                    let safeEnd = buffer.index(buffer.endIndex, offsetBy: -min(buffer.count, 7))
                    output += String(buffer[buffer.startIndex..<safeEnd])
                    buffer = String(buffer[safeEnd...])
                    break
                } else {
                    // No think tags anywhere — emit the whole buffer.
                    output += buffer
                    buffer = ""
                }
            }
        }

        return output
    }
}

// MARK: - Request / Response models

private struct FeatherlessChatRequest: Encodable {
    let model: String
    let messages: [FeatherlessChatMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    /// chat.enable_thinking=false equivalent via extra_body on Featherless.
    /// Sending budget_tokens=0 disables extended thinking for Qwen3.
    let thinkingBudget: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case thinkingBudget = "thinking_budget_tokens"
    }
}

private struct FeatherlessChatMessage: Codable {
    let role: String
    let content: String
}

private struct FeatherlessStreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private struct FeatherlessErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

enum FeatherlessAIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Featherless API key in FeatherlessAIConfig.apiKey, then try again."
        case .invalidResponse:
            return "The AI service returned an invalid response."
        case .emptyResponse:
            return "The AI service did not return a message."
        case .requestFailed(let message):
            return message
        }
    }
}
