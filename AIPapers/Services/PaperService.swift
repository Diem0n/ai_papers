//
//  PaperService.swift
//  AIPapers
//
//  Orchestrates the pipeline: arXiv -> dedup -> relevance -> SwiftData.
//  Summarization is on-demand (see summarize(_:)), not part of refresh —
//  views call refresh() to sync the archive and summarize() when a paper is opened.
//

import Foundation
import os
import WidgetKit

struct RefreshResult {
    let papersAdded: Int
    let wasPaused: Bool
}

private let logger = Logger(subsystem: "com.Diem0n.AIPapers", category: "PaperService")

@MainActor
final class PaperService {
    private let arxivService: ArxivService
    private let ollamaService: OllamaService
    private let embeddingService: EmbeddingService
    private let trendBriefService: TrendBriefService
    private let huggingFace = HuggingFaceService()
    private let repository: PaperRepository

    init(
        repository: PaperRepository,
        arxivService: ArxivService = ArxivService(),
        ollamaService: OllamaService = OllamaService(),
        embeddingService: EmbeddingService = EmbeddingService(),
        trendBriefService: TrendBriefService = TrendBriefService()
    ) {
        self.repository = repository
        self.arxivService = arxivService
        self.ollamaService = ollamaService
        self.embeddingService = embeddingService
        self.trendBriefService = trendBriefService
    }

    @discardableResult
    func refresh(onProgress: (String) -> Void = { _ in }) async throws -> RefreshResult {
        onProgress("Checking arXiv for new papers…")
        // Two sources; either can be down without failing the refresh, but not both.
        var arxivError: Error?
        var incoming: [ArxivPaper] = []
        do {
            incoming = try await arxivService.fetchRecentPapers(maxResults: AppSettings.maxPapersToFetch)
        } catch {
            arxivError = error
        }
        if AppSettings.includeHuggingFace {
            onProgress("Checking Hugging Face daily papers…")
            let daily = await huggingFaceDaily()
            let seen = Set(incoming.map(\.id))
            incoming += daily.map(\.paper).filter { !seen.contains($0.id) }
            for item in daily { CodeLinkStore.shared.set(item.links, for: item.paper.id) }
            if daily.isEmpty, let arxivError { throw arxivError }
        } else if let arxivError {
            throw arxivError
        }
        let existingIDs = try repository.existingIDs()
        let newPapers = DeduplicationService.filterNewPapers(incoming, existingIDs: existingIDs)

        logger.notice("arXiv returned \(incoming.count, privacy: .public) papers, \(existingIDs.count, privacy: .public) already stored, \(newPapers.count, privacy: .public) new")

        let topics = AppSettings.topics
        var insertedPapers: [Paper] = []
        var wasPaused = false
        for arxivPaper in newPapers {
            if Task.isCancelled { wasPaused = true; break }
            let relevance = RelevanceService.score(
                title: arxivPaper.title,
                abstractText: arxivPaper.abstractText,
                publishedAt: arxivPaper.publishedAt,
                topics: topics
            )
            let paper = Paper(
                id: arxivPaper.id,
                title: arxivPaper.title,
                authors: arxivPaper.authors,
                abstractText: arxivPaper.abstractText,
                url: arxivPaper.url,
                publishedAt: arxivPaper.publishedAt,
                category: arxivPaper.primaryCategory,
                relevanceScore: relevance
            )
            repository.insert(paper)
            insertedPapers.append(paper)
        }

        if !insertedPapers.isEmpty {
            onProgress("Saving \(insertedPapers.count) papers…")
            try repository.save()
            logger.notice("Saved \(insertedPapers.count, privacy: .public) new papers")
            WidgetCenter.shared.reloadTimelines(ofKind: "AIPapersWidget")
        }

        // Embeddings are cheap (well under 1s each) so, unlike summaries, they
        // run eagerly here — related papers and the graph need broad coverage
        // to be useful, not just whatever you happen to have opened.
        for (index, paper) in insertedPapers.enumerated() {
            if Task.isCancelled { wasPaused = true; break }
            onProgress("Finding connections \(index + 1) of \(insertedPapers.count)…")
            await embed(paper)
        }
        if !insertedPapers.isEmpty {
            try? repository.save()
            WidgetCenter.shared.reloadTimelines(ofKind: "AIPapersWidget")
        }

        // The daily trend brief is deliberately not awaited here: it's a ~40s
        // model call that used to hold the refresh spinner long after every
        // paper was already saved and usable. AppActivity runs it afterwards.
        return RefreshResult(papersAdded: insertedPapers.count, wasPaused: wasPaused)
    }

    /// Today's and yesterday's Hugging Face daily papers (the list for "today"
    /// is often still empty in the morning, UTC). Failures just mean none.
    private func huggingFaceDaily() async -> [HFDailyPaper] {
        var result: [HFDailyPaper] = []
        for offset in [0, -1] {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: .now),
                  let papers = try? await huggingFace.dailyPapers(on: day) else { continue }
            result += papers
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.paper.id).inserted }
    }

    /// Looks up code, weights and datasets for papers not checked recently.
    /// Throttled — it's a background courtesy pass, not a blocking step.
    func updateCodeLinks(for papers: [Paper], limit: Int = 60) async {
        let store = CodeLinkStore.shared
        let pending = papers.filter { store.needsCheck($0.id) }.prefix(limit)
        for paper in pending {
            if Task.isCancelled || NetworkStatus.shared.isOffline { return }
            var links = (try? await huggingFace.links(for: paper.id)) ?? store.links[paper.id] ?? .none()
            if links.githubRepo == nil, let fromAbstract = HuggingFaceService.githubLink(in: paper.abstractText) {
                links.githubRepo = fromAbstract
            }
            store.set(links, for: paper.id)
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    /// Synthesizes a cross-paper "where the field is heading" brief, once per
    /// day — this reasons over ~15 papers of context, much heavier than a
    /// per-paper call, so it shouldn't re-run on every manual refresh click.
    /// Public: this is a separate daily concern from fetching new papers, so
    /// callers can trigger it even when a full arXiv refresh isn't needed.
    func generateTrendBriefIfNeeded(onProgress: (String) -> Void = { _ in }) async {
        if let existing = TrendBriefStore.loadLatest(), Calendar.current.isDateInToday(existing.day) {
            return
        }
        guard let allPapers = try? repository.allPapers(), !allPapers.isEmpty else { return }

        let topPapers = allPapers
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(15)
        let digests = topPapers.map {
            TrendBriefService.PaperDigest(title: $0.title, synopsis: $0.summary ?? $0.abstractText)
        }

        onProgress("Synthesizing today's trend brief…")
        do {
            let content = try await trendBriefService.generateBrief(papers: digests)
            let brief = TrendBrief(
                day: Calendar.current.startOfDay(for: .now),
                generatedAt: .now,
                content: content,
                paperCount: digests.count
            )
            TrendBriefStore.save(brief)
            WidgetCenter.shared.reloadTimelines(ofKind: "AIPapersWidget")
        } catch {
            logger.error("Trend brief generation failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Summarizes a single paper on demand — called when its detail view is opened.
    /// Returns the failure message on error, nil on success — callers that only
    /// care about pass/fail can still just check `== nil`.
    @discardableResult
    func summarize(_ paper: Paper) async -> String? {
        do {
            let summary = try await ollamaService.summarize(title: paper.title, abstractText: paper.abstractText)
            paper.summary = summary.summary
            paper.whyItMatters = summary.whyItMatters
            // Don't let a summary re-decide a topic the classifier already set —
            // the stored subtopic belongs to that topic.
            if AnalyticsService.storedTopic(paper) == nil {
                paper.category = summary.topics.first ?? paper.category
            }
            paper.relevanceScore = RelevanceService.score(
                title: paper.title,
                abstractText: paper.abstractText,
                publishedAt: paper.publishedAt,
                llmRelevance: summary.engineeringRelevance,
                topics: AppSettings.topics
            )
            try? repository.save()
            WidgetCenter.shared.reloadTimelines(ofKind: "AIPapersWidget")
            return nil
        } catch let error as LocalizedError {
            logger.error("Summarize failed for \(paper.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return error.errorDescription ?? "Couldn't generate a summary."
        } catch {
            logger.error("Summarize failed for \(paper.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return "Couldn't generate a summary."
        }
    }

    /// Assigns a topic and subtopic from the fixed taxonomy via the model,
    /// without generating a full summary. A stored topic is kept and only the
    /// subtopic is asked, unless `reclassify` asks for both again. Only throws when Ollama itself is unreachable, so a
    /// batch caller can stop instead of grinding through dozens of failures.
    func categorize(_ paper: Paper, reclassify: Bool = false) async throws {
        do {
            let known = reclassify ? nil : AnalyticsService.storedTopic(paper)
            guard let result = try await ollamaService.classify(title: paper.title, abstractText: paper.abstractText, knownTopic: known) else { return }
            paper.category = result.topic
            paper.subtopic = result.subtopic
            try? repository.save()
        } catch let error as OllamaServiceError {
            if case .connectionFailed = error { throw error }
            logger.error("Ollama classify failed for \(paper.id, privacy: .public): \(error.debugDescription, privacy: .public)")
        }
    }

    /// Fallback for papers that don't have an embedding yet (an older paper
    /// from before this existed, or a failed attempt during refresh).
    func embedIfNeeded(_ paper: Paper) async {
        guard paper.embedding == nil else { return }
        await embed(paper)
        try? repository.save()
    }

    private func embed(_ paper: Paper) async {
        do {
            let text = "\(paper.title)\n\(paper.abstractText)"
            paper.embedding = try await embeddingService.embed(text: text)
        } catch {
            logger.error("Embedding failed for \(paper.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// mxbai-embed-large is trained to embed *queries* with this prefix so they
    /// land near the passages that answer them.
    static let queryPrefix = "Represent this sentence for searching relevant passages: "

    /// Search by meaning: embed the query and rank stored papers by similarity.
    func semanticSearch(_ query: String, limit: Int = 30) async throws -> [(paper: Paper, score: Double)] {
        let vector = try await embeddingService.embed(text: Self.queryPrefix + query)
        return SimilarityService.hybridRank(queryVector: vector, queryText: query, among: try repository.allPapers(), limit: limit)
    }

    /// Retrieval-augmented answer over the local archive: find the papers
    /// closest to the question, then have the model answer from those alone.
    func ask(_ question: String) async throws -> (answer: String, sources: [(paper: Paper, score: Double)]) {
        let vector = try await embeddingService.embed(text: Self.queryPrefix + question)
        let hits = SimilarityService.hybridRank(queryVector: vector, queryText: question, among: try repository.allPapers(), limit: 6)
        let sources = hits.enumerated().map { offset, hit in
            AskPromptSource(
                index: offset + 1,
                title: hit.paper.title,
                text: String((hit.paper.summary ?? hit.paper.abstractText).replacingOccurrences(of: "\n", with: " ").prefix(900))
            )
        }
        let answer = try await ollamaService.answer(question: question, sources: sources)
        return (answer, hits)
    }

    /// Papers most similar to `paper` among everything already embedded.
    func relatedPapers(to paper: Paper, limit: Int = 3) throws -> [(paper: Paper, score: Double)] {
        let allPapers = try repository.allPapers()
        return SimilarityService.mostSimilar(to: paper, among: allPapers, limit: limit)
    }
}
