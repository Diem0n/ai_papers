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
}

private let logger = Logger(subsystem: "com.Diem0n.AIPapers", category: "PaperService")

@MainActor
final class PaperService {
    private let arxivService: ArxivService
    private let ollamaService: OllamaService
    private let embeddingService: EmbeddingService
    private let repository: PaperRepository

    init(
        repository: PaperRepository,
        arxivService: ArxivService = ArxivService(),
        ollamaService: OllamaService = OllamaService(),
        embeddingService: EmbeddingService = EmbeddingService()
    ) {
        self.repository = repository
        self.arxivService = arxivService
        self.ollamaService = ollamaService
        self.embeddingService = embeddingService
    }

    @discardableResult
    func refresh(onProgress: (String) -> Void = { _ in }) async throws -> RefreshResult {
        onProgress("Checking arXiv for new papers…")
        let incoming = try await arxivService.fetchRecentPapers(maxResults: AppSettings.maxPapersToFetch)
        let existingIDs = try repository.existingIDs()
        let newPapers = DeduplicationService.filterNewPapers(incoming, existingIDs: existingIDs)

        logger.notice("arXiv returned \(incoming.count, privacy: .public) papers, \(existingIDs.count, privacy: .public) already stored, \(newPapers.count, privacy: .public) new")

        let topics = AppSettings.topics
        for arxivPaper in newPapers {
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
        }

        if !newPapers.isEmpty {
            onProgress("Saving \(newPapers.count) papers…")
            try repository.save()
            logger.notice("Saved \(newPapers.count, privacy: .public) new papers")
            WidgetCenter.shared.reloadTimelines(ofKind: "AIPapersWidget")
        }

        return RefreshResult(papersAdded: newPapers.count)
    }

    /// Summarizes a single paper on demand — called when its detail view is opened.
    @discardableResult
    func summarize(_ paper: Paper) async -> Bool {
        do {
            let summary = try await ollamaService.summarize(title: paper.title, abstractText: paper.abstractText)
            paper.summary = summary.summary
            paper.whyItMatters = summary.whyItMatters
            paper.category = summary.topics.first ?? paper.category
            paper.relevanceScore = RelevanceService.score(
                title: paper.title,
                abstractText: paper.abstractText,
                publishedAt: paper.publishedAt,
                llmRelevance: summary.engineeringRelevance,
                topics: AppSettings.topics
            )
            try? repository.save()
            WidgetCenter.shared.reloadTimelines(ofKind: "AIPapersWidget")
            return true
        } catch let error as OllamaServiceError {
            logger.error("Ollama summarize failed for \(paper.id, privacy: .public): \(error.debugDescription, privacy: .public)")
            return false
        } catch {
            logger.error("Ollama summarize failed for \(paper.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Generates a semantic embedding on demand — called when a paper's detail
    /// view is opened, same trigger as summarize(). No-op if already embedded.
    func embedIfNeeded(_ paper: Paper) async {
        guard paper.embedding == nil else { return }
        do {
            let text = "\(paper.title)\n\(paper.abstractText)"
            paper.embedding = try await embeddingService.embed(text: text)
            try? repository.save()
        } catch {
            logger.error("Embedding failed for \(paper.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Papers most similar to `paper` among everything already embedded.
    func relatedPapers(to paper: Paper, limit: Int = 3) throws -> [(paper: Paper, score: Double)] {
        let allPapers = try repository.allPapers()
        return SimilarityService.mostSimilar(to: paper, among: allPapers, limit: limit)
    }
}
