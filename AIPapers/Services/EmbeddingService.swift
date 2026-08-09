//
//  EmbeddingService.swift
//  AIPapers
//
//  Generates semantic embeddings via a dedicated Ollama embedding model.
//  Chat models like gemma3 don't support /api/embed — this needs its own model.
//

import Foundation

enum EmbeddingServiceError: LocalizedError {
    case connectionFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Ollama isn't running. Start Ollama and try again."
        case .invalidResponse:
            return "Ollama returned an unexpected response."
        }
    }
}

nonisolated final class EmbeddingService {
    private let session: URLSession
    private let baseURL: URL
    private let model: String

    init(
        session: URLSession = .shared,
        baseURL: URL = AppConstants.ollamaBaseURL,
        model: String = AppConstants.embeddingModel
    ) {
        self.session = session
        self.baseURL = baseURL
        self.model = model
    }

    func embed(text: String) async throws -> [Double] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/embed"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(EmbedRequest(model: model, input: text))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw EmbeddingServiceError.connectionFailed
        }

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode),
              let decoded = try? JSONDecoder().decode(EmbedResponse.self, from: data),
              let embedding = decoded.embeddings.first else {
            throw EmbeddingServiceError.invalidResponse
        }
        return embedding
    }
}

nonisolated private struct EmbedRequest: Encodable {
    let model: String
    let input: String
}

nonisolated private struct EmbedResponse: Decodable {
    let embeddings: [[Double]]
}
