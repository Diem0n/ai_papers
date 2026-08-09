//
//  OllamaService.swift
//  AIPapers
//
//  Talks to a locally running Ollama instance over its HTTP API.
//  No paper content ever leaves the machine.
//

import Foundation

struct OllamaSummary: Codable, Sendable, Equatable {
    let summary: String
    let keyContribution: String
    let whyItMatters: String
    let engineeringRelevance: Double
    let topics: [String]
}

enum OllamaServiceError: LocalizedError {
    case unavailable
    case invalidResponse
    case malformedContent

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Ollama isn't running. Start Ollama and try again."
        case .invalidResponse:
            return "Ollama returned an unexpected response."
        case .malformedContent:
            return "Ollama returned a response that couldn't be understood."
        }
    }
}

nonisolated final class OllamaService {
    private let session: URLSession
    private let baseURL: URL
    private let model: String

    init(
        session: URLSession = .shared,
        baseURL: URL = AppConstants.ollamaBaseURL,
        model: String = AppConstants.ollamaModel
    ) {
        self.session = session
        self.baseURL = baseURL
        self.model = model
    }

    func summarize(title: String, abstractText: String) async throws -> OllamaSummary {
        let request = try makeRequest(title: title, abstractText: abstractText)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OllamaServiceError.unavailable
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaServiceError.unavailable
        }

        guard let generateResponse = try? JSONDecoder().decode(GenerateResponse.self, from: data) else {
            throw OllamaServiceError.invalidResponse
        }

        guard let contentData = generateResponse.response.data(using: .utf8),
              let summary = try? JSONDecoder().decode(OllamaSummary.self, from: contentData) else {
            throw OllamaServiceError.malformedContent
        }

        return summary
    }

    private func makeRequest(title: String, abstractText: String) throws -> URLRequest {
        let body = GenerateRequest(
            model: model,
            prompt: Self.prompt(title: title, abstractText: abstractText),
            stream: false,
            format: "json"
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func prompt(title: String, abstractText: String) -> String {
        """
        You summarize AI research papers for a practicing AI engineer.
        Use only the information given below. Do not invent benchmark numbers,
        GitHub links, citations, or implementation details. If something isn't
        available from the text given, say so explicitly instead of guessing.

        Title: \(title)
        Abstract: \(abstractText)

        Respond with ONLY a JSON object in exactly this shape:
        {
          "summary": "short technical summary",
          "keyContribution": "the main contribution",
          "whyItMatters": "why an AI engineer should care",
          "engineeringRelevance": 0.0,
          "topics": ["topic1", "topic2"]
        }
        """
    }
}

private struct GenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let format: String
}

private struct GenerateResponse: Decodable {
    let response: String
}
