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

nonisolated private struct PickResponse: Decodable {
    struct Choice: Decodable {
        let n: Int
        let why: String
    }
    let picks: [Choice]
}

/// A retrieved paper as the model sees it when answering a question.
nonisolated struct AskPromptSource: Sendable {
    let index: Int
    let title: String
    let text: String
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
        let summary: OllamaSummary
        // Cloud summaries are opt-in (Settings) and scoped to this one call —
        // classification, stack fit, claims, plans, /explain and Ask always
        // stay on the local model regardless of this setting.
        if AppSettings.useCloudForSummaries, let gemini = GeminiService() {
            summary = try await gemini.summarize(title: title, abstractText: abstractText)
        } else {
            let raw = try await generate(prompt: Self.summaryPrompt(title: title, abstractText: abstractText))
            guard let contentData = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(OllamaSummary.self, from: contentData) else {
                throw OllamaServiceError.malformedContent(raw: raw)
            }
            summary = decoded
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

    /// Answers a question from the given papers only, with [n] citations.
    func answer(question: String, sources: [AskPromptSource]) async throws -> String {
        let text = try await generate(prompt: Self.askPrompt(question: question, sources: sources), json: false)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OllamaServiceError.invalidResponse }
        return trimmed
    }

    /// Teaches one concept from general knowledge: core idea, analogy (and where
    /// it breaks), worked example, misconception, and a check question.
    func explain(concept: String) async throws -> String {
        let text = try await generate(prompt: Self.explainPrompt(concept: concept), json: false)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OllamaServiceError.invalidResponse }
        return trimmed
    }

    /// Chooses the papers most worth reading next from a numbered shortlist,
    /// given papers the reader engaged with. Returns 1-based shortlist numbers
    /// with a short reason; the caller validates them against the shortlist.
    func pickPapers(liked: [String], candidates: [String], count: Int = 5) async throws -> [(number: Int, why: String)] {
        let raw = try await generate(prompt: Self.picksPrompt(liked: liked, candidates: candidates, count: count))
        guard let data = raw.data(using: .utf8),
              let response = try? JSONDecoder().decode(PickResponse.self, from: data) else {
            throw OllamaServiceError.malformedContent(raw: raw)
        }
        return response.picks.map { (number: $0.n, why: $0.why) }
    }

    /// Sends a prompt to /api/generate and returns the model's raw text.
    /// `contextTokens` raises the model's context window for long inputs
    /// (e.g. a paper's full text); nil keeps Ollama's default.
    func generate(prompt: String, json: Bool = true, contextTokens: Int? = nil) async throws -> String {
        let request = try makeRequest(prompt: prompt, json: json, contextTokens: contextTokens)

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

    private func makeRequest(prompt: String, json: Bool, contextTokens: Int? = nil) throws -> URLRequest {
        let body = GenerateRequest(
            model: model,
            prompt: prompt,
            stream: false,
            format: json ? "json" : nil,
            // Free-text answers don't need hidden reasoning tokens first.
            think: json ? nil : false,
            options: contextTokens.map { ["num_ctx": $0] }
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        // Local generation of a long answer can legitimately take minutes.
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Shared with GeminiService — the summary prompt is identical regardless of which model answers it.
    nonisolated static func summaryPrompt(title: String, abstractText: String) -> String {
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

    private static func picksPrompt(liked: [String], candidates: [String], count: Int) -> String {
        """
        You recommend what a busy AI engineer should read next.

        Papers they favorited, finished or opened (their taste):
        \(liked.map { "- \($0)" }.joined(separator: "\n"))

        Candidate papers, numbered:
        \(candidates.joined(separator: "\n"))

        Choose the \(count) candidates most worth their time given that taste. Prefer
        variety over five near-duplicates. For each, give a reason of at most 14 words
        that points to what they liked. Use only the information above; invent nothing.

        Respond with ONLY a JSON object in exactly this shape:
        {"picks": [{"n": <candidate number>, "why": "<short reason>"}]}
        """
    }

    private static func askPrompt(question: String, sources: [AskPromptSource]) -> String {
        let papers = sources.map { "[\($0.index)] \($0.title)\n\($0.text)" }.joined(separator: "\n\n")
        return """
        You answer questions about a personal library of AI research papers.
        Use ONLY the numbered papers below. If they don't contain the answer, say
        so plainly instead of guessing. Cite the papers you rely on like [1] or
        [2][3]. Be concise: at most 150 words, plain language, no hype. Do not
        invent numbers, results, or claims.

        Papers:
        \(papers)

        Question: \(question)
        """
    }

    /// Built from learning-science findings: anchor on what the reader already knows
    /// and skip basics (the expertise-reversal effect), one concrete worked example
    /// before abstraction, an analogy plus where it fails, a named misconception, no
    /// extraneous material (Mayer's coherence principle), and a retrieval-practice
    /// question whose answer is withheld.
    private static func explainPrompt(concept: String) -> String {
        """
        You are a patient technical tutor teaching ONE concept to an AI engineer with a
        data-science degree: fluent in machine-learning fundamentals, statistics and
        Python, but not necessarily familiar with this specific concept. Do not re-teach
        basics they already know; spend the words on what is new.

        Request: \(concept)

        Write exactly these eight sections, in this order, each on its own line starting with
        its bold label written exactly as shown (do not rename or skip any). No headings, tables
        or code fences. Write any mathematics in LaTeX: $...$ for inline symbols and $$...$$ on
        its own line for a displayed equation (e.g. $\\text{softmax}(z_i)=e^{z_i}/\\sum_j e^{z_j}$).
        Use math only where it genuinely helps; never put math inside backticks.

        **In one line** — the core idea in at most 25 words: plain language first, then the precise term.
        **Why it exists** — the problem it solves or the limitation it removes, in one or two sentences.
        **Intuition** — one analogy drawn from something an ML practitioner already knows. Then one sentence starting "Where it breaks:" saying where the analogy stops being true.
        **How it works** — three to five short numbered steps, each on its own line.
        **Worked example** — a tiny concrete example with small numbers, or a few lines of pseudocode, that the reader could trace by hand. Show the steps and the result.
        **Common misconception** — one thing people usually get wrong, and the correct view.
        **Check yourself** — one question that makes the reader apply the idea, not recite it.
        **Answer** — the answer to that question, in one or two sentences. This must be the last section.

        Rules:
        - Only state what you are confident is correct. If you don't reliably know this concept, or the exact formula, say "I'm not certain about this" in the first section instead of inventing details.
        - Never invent citations, benchmark numbers, links or authors.
        - Under 350 words in total. Short sentences. No filler, no praise, no restating the request.
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
    let format: String?
    let think: Bool?
    var options: [String: Int]?
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
