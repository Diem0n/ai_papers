//
//  OllamaSetup.swift
//  AIPapers
//
//  First-run checks: is Ollama running, and are the models the app needs
//  installed? If not, download them through Ollama's own /api/pull, reporting
//  progress. The app never bundles a model — users pull them under Ollama's terms.
//

import Foundation
import Combine

@MainActor
final class OllamaSetup: ObservableObject {
    enum State: Equatable {
        case checking
        case notRunning
        case ready
        case missing([String])
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var pulling: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var pullError: String?

    var required: [String] { [AppSettings.ollamaModel, AppConstants.embeddingModel] }

    func check() async {
        state = .checking
        guard let installed = try? await OllamaService().listModels() else {
            state = .notRunning
            return
        }
        // "mxbai-embed-large" is installed as "mxbai-embed-large:latest".
        let names = Set(installed.flatMap { [$0, $0.replacingOccurrences(of: ":latest", with: "")] })
        let missing = required.filter { !names.contains($0) && !names.contains($0 + ":latest") }
        state = missing.isEmpty ? .ready : .missing(missing)
    }

    func pullMissing() async {
        guard case .missing(let models) = state else { return }
        pullError = nil
        for model in models {
            pulling = model
            progress = 0
            do {
                try await pull(model)
            } catch {
                pullError = "Couldn't download \(model). Check your connection and that Ollama is running."
                break
            }
        }
        pulling = nil
        await check()
    }

    private func pull(_ model: String) async throws {
        var request = URLRequest(url: AppConstants.ollamaBaseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.timeoutInterval = 3600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        struct Line: Decodable { let status: String?; let total: Double?; let completed: Double?; let error: String? }
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8), let item = try? JSONDecoder().decode(Line.self, from: data) else { continue }
            if item.error != nil { throw URLError(.badServerResponse) }
            if let total = item.total, total > 0, let done = item.completed { progress = done / total }
        }
    }
}
