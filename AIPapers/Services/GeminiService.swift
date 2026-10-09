//
//  GeminiService.swift
//  AIPapers
//
//  Optional cloud fallback for per-paper summaries only — classification,
//  stack fit, claims, plans, /explain and Ask stay on the local Ollama model
//  no matter what. Opt-in: off until the reader adds a key in Settings.
//
//  Gemini's free tier (no card, ~1,500 requests/day on 2.5/3 Flash) is the
//  best fit among free-tier providers for this: generous daily quota, native
//  JSON-mode output (no "model wrote almost-JSON" parsing games), and the
//  volume a paper archive needs. See AppSettings.useCloudForSummaries.
//

import Foundation

nonisolated enum GeminiServiceError: LocalizedError {
    case noAPIKey
    case invalidKey
    case rateLimited
    case serverError(statusCode: Int)
    case malformedContent(raw: String)
    case connectionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "No Gemini API key set. Add one in Settings, or turn off cloud summaries."
        case .invalidKey: "Gemini rejected the API key. Check it in Settings."
        case .rateLimited: "Gemini's free-tier daily limit is used up. Try again later, or turn off cloud summaries."
        case .serverError(let code): "Gemini returned an error (HTTP \(code))."
        case .malformedContent: "Gemini returned a response that couldn't be understood."
        case .connectionFailed: "Couldn't reach Gemini. Check your connection."
        }
    }
}

nonisolated final class GeminiService {
    static let keychainAccount = "GeminiAPIKey"
    /// Google's alias for whichever current Flash model is live — avoids pinning
    /// to a dated model id that gets retired.
    private static let model = "gemini-flash-latest"

    private let session: URLSession
    private let apiKey: String

    /// nil when no key is configured — callers check before constructing one.
    init?(session: URLSession = .shared) {
        guard let key = KeychainService.get(account: Self.keychainAccount), !key.isEmpty else { return nil }
        self.session = session
        self.apiKey = key
    }

    func summarize(title: String, abstractText: String) async throws -> OllamaSummary {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONEncoder().encode(GenerateContentRequest(
            contents: [.init(parts: [.init(text: OllamaService.summaryPrompt(title: title, abstractText: abstractText))])],
            generationConfig: .init(responseMimeType: "application/json")
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GeminiServiceError.connectionFailed(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else { throw GeminiServiceError.serverError(statusCode: -1) }
        switch http.statusCode {
        case 200..<300: break
        case 400, 401, 403: throw GeminiServiceError.invalidKey
        case 429: throw GeminiServiceError.rateLimited
        default: throw GeminiServiceError.serverError(statusCode: http.statusCode)
        }

        guard let wrapped = try? JSONDecoder().decode(GenerateContentResponse.self, from: data),
              let text = wrapped.candidates?.first?.content?.parts?.first?.text,
              let summaryData = text.data(using: .utf8),
              let summary = try? JSONDecoder().decode(OllamaSummary.self, from: summaryData) else {
            throw GeminiServiceError.malformedContent(raw: String(data: data, encoding: .utf8) ?? "")
        }
        return summary
    }
}

// MARK: Gemini wire format (the handful of fields this call needs)

private nonisolated struct GenerateContentRequest: Encodable {
    struct Content: Encodable { let parts: [Part] }
    struct Part: Encodable { let text: String }
    struct GenerationConfig: Encodable { let responseMimeType: String }
    let contents: [Content]
    let generationConfig: GenerationConfig
}

private nonisolated struct GenerateContentResponse: Decodable {
    struct Candidate: Decodable { let content: Content? }
    struct Content: Decodable { let parts: [Part]? }
    struct Part: Decodable { let text: String? }
    let candidates: [Candidate]?
}
