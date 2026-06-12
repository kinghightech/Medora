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
    static let model = "meta-llama/Meta-Llama-3.1-8B-Instruct"
}

struct AITranscriptMessage {
    let role: String
    let content: String
}

struct FeatherlessAIClient {
    func send(messages: [AITranscriptMessage]) async throws -> String {
        guard !FeatherlessAIConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FeatherlessAIError.missingAPIKey
        }

        var request = URLRequest(url: FeatherlessAIConfig.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(FeatherlessAIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            FeatherlessChatRequest(
                model: FeatherlessAIConfig.model,
                messages: messages.map { FeatherlessChatMessage(role: $0.role, content: $0.content) },
                temperature: 0.4,
                maxTokens: 900
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeatherlessAIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(FeatherlessErrorResponse.self, from: data)
            throw FeatherlessAIError.requestFailed(apiError?.error.message ?? "Request failed with status \(httpResponse.statusCode).")
        }

        let decodedResponse = try JSONDecoder().decode(FeatherlessChatResponse.self, from: data)
        guard let reply = decodedResponse.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !reply.isEmpty else {
            throw FeatherlessAIError.emptyResponse
        }

        return reply
    }
}

private struct FeatherlessChatRequest: Encodable {
    let model: String
    let messages: [FeatherlessChatMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct FeatherlessChatMessage: Codable {
    let role: String
    let content: String
}

private struct FeatherlessChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: FeatherlessChatMessage
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
