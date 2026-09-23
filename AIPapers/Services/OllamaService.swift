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

/// One digest theme as the model sees it: what it is, and the papers in it.
nonisolated struct DigestPromptTheme: Sendable {
    let index: Int
    let label: String
    let keywords: [String]
    let papers: [String]   // "Title — synopsis"
}

nonisolated struct DigestNarrativeResult: Decodable, Sendable {
    struct Theme: Decodable, Sendable {
        let index: Int
        let headline: String
        let takeaway: String
        let soWhat: String
    }
    let tldr: String
    let themes: [Theme]
}

nonisolated struct OllamaClassification: Sendable, Equatable {
    let topic: String
    let subtopic: String
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
        let raw = try await generate(prompt: Self.prompt(title: title, abstractText: abstractText))

        guard let contentData = raw.data(using: .utf8),
              let summary = try? JSONDecoder().decode(OllamaSummary.self, from: contentData) else {
            throw OllamaServiceError.malformedContent(raw: raw)
        }

        // The model should not be trusted for canonical metadata: coerce
        // whatever topic strings it invented back onto the fixed list we
        // asked for, dropping anything that doesn't match.
        return OllamaSummary(
            summary: summary.summary,
            keyContribution: summary.keyContribution,
            whyItMatters: summary.whyItMatters,
            engineeringRelevance: summary.engineeringRelevance,
            topics: Self.canonicalTopics(from: summary.topics)
        )
    }

    /// One short call that picks a topic and subtopic from the fixed taxonomy —
    /// far cheaper than a full summary, so it can backfill a whole archive.
    /// If the topic is already known only the subtopic is asked, which is
    /// both faster and means the stored topic is never re-decided.
    /// Returns nil if no valid topic comes back.
    func classify(title: String, abstractText: String, knownTopic: String? = nil) async throws -> OllamaClassification? {
        let known = knownTopic.flatMap(Taxonomy.topic(named:))
        let prompt = known.map { Self.subtopicPrompt(title: title, abstractText: abstractText, topic: $0) }
            ?? Self.classifyPrompt(title: title, abstractText: abstractText)
        let raw = try await generate(prompt: prompt)

        guard let contentData = raw.data(using: .utf8),
              let result = try? JSONDecoder().decode(ClassifyResult.self, from: contentData) else {
            throw OllamaServiceError.malformedContent(raw: raw)
        }

        // Never trust the model for canonical labels: snap both onto the
        // taxonomy, and record "Other" rather than nothing when no subtopic fits.
        guard let topic = known ?? result.topic.flatMap(Taxonomy.topic(named:)) else { return nil }
        let subtopic = result.subtopic.flatMap { Taxonomy.canonicalSubtopic($0, in: topic.name) } ?? Taxonomy.otherSubtopic
        return OllamaClassification(topic: topic.name, subtopic: subtopic)
    }

    /// Short plain-language text for each already-found theme. The model
    /// describes; it does not decide what the themes are.
    func synthesizeDigest(themes: [DigestPromptTheme]) async throws -> DigestNarrativeResult {
        let raw = try await generate(prompt: Self.digestPrompt(themes: themes))
        guard let data = raw.data(using: .utf8),
              let result = try? JSONDecoder().decode(DigestNarrativeResult.self, from: data) else {
            throw OllamaServiceError.malformedContent(raw: raw)
        }
        return result
    }

    /// Sends a prompt to /api/generate and returns the model's raw text.
    private func generate(prompt: String) async throws -> String {
        let request = try makeRequest(prompt: prompt)

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
        return generateResponse.response
    }

    private static func canonicalTopics(from rawTopics: [String]) -> [String] {
        rawTopics.compactMap { raw in
            Taxonomy.names.first { $0.caseInsensitiveCompare(raw) == .orderedSame }
        }
    }

    private func makeRequest(prompt: String) throws -> URLRequest {
        let body = GenerateRequest(
            model: model,
            prompt: prompt,
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

        "topics" must contain only values from this exact list, spelled exactly
        as shown (1 to 3 of them, most relevant first). Prefer the most specific topic:
        \(Taxonomy.promptList)
        Do not invent topics outside this list.
        """
    }

    private static func digestPrompt(themes: [DigestPromptTheme]) -> String {
        let blocks = themes.map { theme in
            """
            Theme \(theme.index): \(theme.label)
            Distinctive terms: \(theme.keywords.joined(separator: ", "))
            Papers:
            \(theme.papers.map { "- \($0)" }.joined(separator: "\n"))
            """
        }.joined(separator: "\n\n")

        return """
        You write a fast-to-scan weekly digest of new AI research for a busy AI engineer.
        Below are themes that were already found by clustering the papers; describe them,
        do not invent new ones. Use only the titles and synopses given. Do not invent
        numbers, results, or claims. Plain words, no hype, no jargon you can avoid.

        \(blocks)

        Respond with ONLY a JSON object in exactly this shape:
        {
          "tldr": "ONE sentence, at most 30 words: the single most important shift across all themes",
          "themes": [
            {
              "index": 0,
              "headline": "at most 8 words, a plain-language title for the theme",
              "takeaway": "one or two short sentences: what these papers are doing",
              "soWhat": "one sentence: what an AI engineer should do or watch because of it"
            }
          ]
        }
        Include one entry per theme, using the theme's index number.
        """
    }

    private static func classifyPrompt(title: String, abstractText: String) -> String {
        """
        Classify this research paper into exactly one topic and one subtopic
        from the taxonomy below. Choose the most specific topic that fits; use
        "LLM" only for general language-model work that fits nothing more
        specific, and "Classical ML" for statistics/classical machine learning
        that isn't about AI systems. The subtopic must belong to the chosen topic.

        Taxonomy (topic, with its subtopics indented beneath):
        \(Taxonomy.nestedPromptList)

        Title: \(title)
        Abstract: \(abstractText)

        Respond with ONLY a JSON object: {"topic": "<topic name>", "subtopic": "<subtopic name>"}
        Spell names exactly as shown.
        """
    }

    private static func subtopicPrompt(title: String, abstractText: String, topic: Taxonomy.Topic) -> String {
        """
        This research paper belongs to the topic "\(topic.name)". Choose the one
        subtopic below that fits it best. If none fits, answer "Other".

        Subtopics:
        \(Taxonomy.subtopicPromptList(for: topic))

        Title: \(title)
        Abstract: \(abstractText)

        Respond with ONLY a JSON object: {"subtopic": "<subtopic name, spelled exactly as shown>"}
        """
    }
}

nonisolated private struct ClassifyResult: Decodable {
    let topic: String?
    let subtopic: String?
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
