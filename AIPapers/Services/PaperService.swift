//
//  PaperService.swift
//  AIPapers
//
//  Orchestrates the pipeline: arXiv -> dedup -> Ollama -> relevance -> SwiftData.
//  Views call refresh() and render the result; they don't touch the stages directly.
//

import Foundation
import os

struct RefreshResult {
    let papersAdded: Int
    let summariesFailed: Int
}

private let logger = Logger(subsystem: "com.Diem0n.AIPapers", category: "PaperService")

@MainActor
final class PaperService {
    private let arxivService: ArxivService
    private let ollamaService: OllamaService
    private let repository: PaperRepository

    init(
        repository: PaperRepository,
        arxivService: ArxivService = ArxivService(),
        ollamaService: OllamaService = OllamaService()
    ) {
        self.repository = repository
        self.arxivService = arxivService
        self.ollamaService = ollamaService
    }

    @discardableResult
    func refresh(onProgress: (String) -> Void = { _ in }) async throws -> RefreshResult {
        onProgress("Checking arXiv for new papers…")
        let incoming = try await arxivService.fetchRecentPapers()
        let existingIDs = try repository.existingIDs()
        let newPapers = DeduplicationService.filterNewPapers(incoming, existingIDs: existingIDs)

        logger.notice("arXiv returned \(incoming.count, privacy: .public) papers, \(existingIDs.count, privacy: .public) already stored, \(newPapers.count, privacy: .public) new")

        var summariesFailed = 0

        for (index, arxivPaper) in newPapers.enumerated() {
            onProgress("Summarizing paper \(index + 1) of \(newPapers.count)…")
            var summary: OllamaSummary?
            do {
                summary = try await ollamaService.summarize(
                    title: arxivPaper.title,
                    abstractText: arxivPaper.abstractText
                )
            } catch {
                summariesFailed += 1
                logger.error("Ollama summarize failed for \(arxivPaper.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            let relevance = RelevanceService.score(
                title: arxivPaper.title,
                abstractText: arxivPaper.abstractText,
                publishedAt: arxivPaper.publishedAt,
                llmRelevance: summary?.engineeringRelevance
            )

            let paper = Paper(
                id: arxivPaper.id,
                title: arxivPaper.title,
                authors: arxivPaper.authors,
                abstractText: arxivPaper.abstractText,
                url: arxivPaper.url,
                publishedAt: arxivPaper.publishedAt,
                summary: summary?.summary,
                whyItMatters: summary?.whyItMatters,
                category: summary?.topics.first ?? arxivPaper.primaryCategory,
                relevanceScore: relevance
            )
            repository.insert(paper)
        }

        if !newPapers.isEmpty {
            onProgress("Saving \(newPapers.count) papers…")
            try repository.save()
            logger.notice("Saved \(newPapers.count, privacy: .public) new papers (\(summariesFailed, privacy: .public) summaries failed)")
        }

        return RefreshResult(papersAdded: newPapers.count, summariesFailed: summariesFailed)
    }
}
