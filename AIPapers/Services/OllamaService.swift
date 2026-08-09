//
//  OllamaService.swift
//  AIPapers
//
//  Talks to a locally running Ollama instance over its HTTP API.
//  No paper content ever leaves the machine.
//

import Foundation

nonisolated struct OllamaSummary: Codable, Sendable, Equatable {
    let summary: String
    let keyContribution: String
    let whyItMatters: String
    let engineeringRelevance: Double
    let topics: [String]
}

enum OllamaServiceError: LocalizedError {
    case connectionFailed(underlying: Error)
    case serverError(statusCode: Int)
    case invalidResponse
    case malformedContent(raw: String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Ollama isn't running. Start Ollama and try again."
        case .serverError(let statusCode):
            return "Ollama returned an error (HTTP \(statusCode))."
        case .invalidResponse:
            return "Ollama returned an unexpected response."
        case .malformedContent:
            return "Ollama returned a response that couldn't be understood."
        }
    }

    /// Full diagnostic detail, for logs — errorDescription stays user-facing and terse.
    var debugDescription: String {
        switch self {
        case .connectionFailed(let underlying):
            return "connectionFailed: \(underlying)"
        case .serverError(let statusCode):
            return "serverError: HTTP \(statusCode)"
        case .invalidResponse:
            return "invalidResponse"
        case .malformedContent(let raw):
            return "malformedContent: \(raw.prefix(300))"
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
        model: String = AppSettings.ollamaModel
    ) {
        self.session = session
        self.baseURL = baseURL
        self.model = model
    }

    /// Locally installed model names, for populating a picker. Empty if Ollama isn't running.
    func listModels() async throws -> [String] {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("api/tags"))
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaServiceError.invalidResponse
        }
        let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
        return tags.models.map(\.name)
    }

    func summarize(title: String, abstractText: String) async throws -> OllamaSummary {
        let request = try makeRequest(title: title, abstractText: abstractText)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // ponytail: single retry on a fresh connection — URLSession's keep-alive
            // connection to local Ollama occasionally gets closed between requests;
            // a real outage still fails on the retry.
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw OllamaServiceError.connectionFailed(underlying: error)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaServiceError.serverError(statusCode: httpResponse.statusCode)
        }

        guard let generateResponse = try? JSONDecoder().decode(GenerateResponse.self, from: data) else {
            throw OllamaServiceError.invalidResponse
        }

        guard let contentData = generateResponse.response.data(using: .utf8),
              let summary = try? JSONDecoder().decode(OllamaSummary.self, from: contentData) else {
            throw OllamaServiceError.malformedContent(raw: generateResponse.response)
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

nonisolated private struct GenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let format: String
}

nonisolated private struct GenerateResponse: Decodable {
    let response: String
}

nonisolated private struct TagsResponse: Decodable {
    struct ModelTag: Decodable {
        let name: String
    }
    let models: [ModelTag]
}
