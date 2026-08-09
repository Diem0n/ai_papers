//
//  PaperService.swift
//  AIPapers
//
//  Orchestrates the pipeline: arXiv -> dedup -> Ollama -> relevance -> SwiftData.
//  Views call refresh() and render the result; they don't touch the stages directly.
//

import Foundation

struct RefreshResult {
    let papersAdded: Int
    let summariesFailed: Int
}

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
    func refresh() async throws -> RefreshResult {
        let incoming = try await arxivService.fetchRecentPapers()
        let existingIDs = try repository.existingIDs()
        let newPapers = DeduplicationService.filterNewPapers(incoming, existingIDs: existingIDs)

        var summariesFailed = 0

        for arxivPaper in newPapers {
            let summary = try? await ollamaService.summarize(
                title: arxivPaper.title,
                abstractText: arxivPaper.abstractText
            )
            if summary == nil {
                summariesFailed += 1
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
            try repository.save()
        }

        return RefreshResult(papersAdded: newPapers.count, summariesFailed: summariesFailed)
    }
}
