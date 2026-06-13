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
    func stream(messages: [AITranscriptMessage]) -> AsyncThrowingStream<String, Error> {
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
                            maxTokens: 1000,
                            stream: true
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

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }

                        if let data = payload.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(FeatherlessStreamChunk.self, from: data),
                           let delta = chunk.choices.first?.delta.content,
                           !delta.isEmpty {
                            continuation.yield(delta)
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
}

private struct FeatherlessChatRequest: Encodable {
    let model: String
    let messages: [FeatherlessChatMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
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
