//
//  TrendBriefService.swift
//  AIPapers
//
//  Synthesizes a cross-paper "where is the field heading" narrative — unlike
//  OllamaService.summarize(), this reasons over a batch of papers at once,
//  not a single one.
//

import Foundation

enum TrendBriefServiceError: LocalizedError {
    case connectionFailed
    case invalidResponse
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .connectionFailed: "Ollama isn't running. Start Ollama and try again."
        case .invalidResponse: "Ollama returned an unexpected response."
        case .emptyContent: "Ollama returned an empty brief."
        }
    }
}

nonisolated final class TrendBriefService {
    struct PaperDigest {
        let title: String
        let synopsis: String
    }

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

    func generateBrief(papers: [PaperDigest]) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateRequest(model: model, prompt: Self.prompt(papers: papers), stream: false)
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Same keep-alive flakiness fix as OllamaService — one retry on a fresh attempt.
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw TrendBriefServiceError.connectionFailed
            }
        }

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode),
              let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: data) else {
            throw TrendBriefServiceError.invalidResponse
        }

        let content = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw TrendBriefServiceError.emptyContent
        }
        return content
    }

    private static func prompt(papers: [PaperDigest]) -> String {
        let list = papers.enumerated()
            .map { "\($0.offset + 1). \($0.element.title) — \($0.element.synopsis)" }
            .joined(separator: "\n")

        return """
        You are an AI engineering analyst. Based ONLY on the \(papers.count) recent papers listed \
        below, write a concise brief (about 450 words, a 2-3 minute read) synthesizing the core \
        trends and where the field appears to be heading. Reference specific papers by name where \
        relevant. Do not invent findings, benchmark numbers, or claims not present in the summaries \
        below. If the papers don't show a clear unifying trend, say so honestly instead of forcing one.

        Papers:
        \(list)

        Write the brief now as plain prose — no headers, no bullet points, no JSON.
        """
    }
}

nonisolated private struct GenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

nonisolated private struct GenerateResponse: Decodable {
    let response: String
}
