//
//  OpenRouterService.swift
//  AIPapers
//
//  The opt-in cloud path. OpenRouter over a single provider (Gemini, Groq,
//  etc) because it fronts hundreds of models — including free ones — behind
//  one OpenAI-compatible endpoint and one key, so the privacy/model choice is
//  the reader's, not ours. Off by default; see AppSettings.cloudScope for
//  which features are even allowed to reach here.
//

import Foundation

nonisolated enum OpenRouterError: LocalizedError {
    case noAPIKey
    case invalidKey
    case rateLimited
    case serverError(statusCode: Int)
    case malformedContent(raw: String)
    case connectionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "No OpenRouter API key set. Add one in Settings, or turn off cloud for this."
        case .invalidKey: "OpenRouter rejected the API key. Check it in Settings."
        case .rateLimited: "Rate limited — the free model is busy. Try again shortly, or turn off cloud for this."
        case .serverError(let code): "OpenRouter returned an error (HTTP \(code))."
        case .malformedContent: "The cloud model returned a response that couldn't be understood."
        case .connectionFailed: "Couldn't reach OpenRouter. Check your connection."
        }
    }
}

nonisolated final class OpenRouterService {
    static let keychainAccount = "OpenRouterAPIKey"
    private static let base = URL(string: "https://openrouter.ai/api/v1")!

    private let session: URLSession
    private let apiKey: String
    private let model: String

    /// nil when no key or no model is configured — callers check before constructing one.
    init?(session: URLSession = .shared) {
        guard let key = KeychainService.get(account: Self.keychainAccount), !key.isEmpty,
              !AppSettings.cloudModel.isEmpty else { return nil }
        self.session = session
        self.apiKey = key
        self.model = AppSettings.cloudModel
    }

    func complete(prompt: String, json: Bool) async throws -> String {
        var request = URLRequest(url: Self.base.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: model,
            messages: [.init(role: "user", content: prompt)],
            response_format: json ? .init(type: "json_object") : nil
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenRouterError.connectionFailed(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else { throw OpenRouterError.serverError(statusCode: -1) }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw OpenRouterError.invalidKey
        case 429: throw OpenRouterError.rateLimited
        default: throw OpenRouterError.serverError(statusCode: http.statusCode)
        }

        guard let wrapped = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let text = wrapped.choices?.first?.message?.content, !text.isEmpty else {
            throw OpenRouterError.malformedContent(raw: String(data: data, encoding: .utf8) ?? "")
        }
        return text
    }

    /// Free-tier models (":free" ids, zero prompt/completion cost) for the Settings picker.
    /// Public endpoint — no key needed, so this works before one is saved.
    static func listFreeModels(session: URLSession = .shared) async throws -> [String] {
        let (data, response) = try await session.data(from: base.appendingPathComponent("models"))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OpenRouterError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let list = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            throw OpenRouterError.malformedContent(raw: "")
        }
        return list.data
            .filter { $0.id.hasSuffix(":free") || ($0.pricing?.prompt == "0" && $0.pricing?.completion == "0") }
            .map(\.id)
            .sorted()
    }
}

// MARK: Wire format

private nonisolated struct ChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    struct ResponseFormat: Encodable { let type: String }
    let model: String
    let messages: [Message]
    let response_format: ResponseFormat?
}

private nonisolated struct ChatResponse: Decodable {
    struct Choice: Decodable { let message: Message? }
    struct Message: Decodable { let content: String? }
    let choices: [Choice]?
}

private nonisolated struct ModelsResponse: Decodable {
    struct Model: Decodable {
        struct Pricing: Decodable { let prompt: String?; let completion: String? }
        let id: String
        let pricing: Pricing?
    }
    let data: [Model]
}
