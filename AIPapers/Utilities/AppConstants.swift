//
//  AppConstants.swift
//  AIPapers
//

import Foundation

nonisolated enum AppConstants {
    /// arXiv categories relevant to AI engineering. Broad on purpose —
    /// topic relevance is filtered later, not at ingestion.
    static let arxivCategories = [
        "cs.AI", "cs.CL", "cs.LG", "cs.MA", "cs.NE", "cs.CV", "cs.IR"
    ]

    /// AI-engineering-relevant topics used for relevance scoring and tagging.
    /// Derived from the taxonomy so there's one list; the "Other" bucket is
    /// left out because it's a classification fallback, not something that
    /// should earn a paper relevance points.
    static let topics = Taxonomy.all.filter { $0.area != Taxonomy.otherArea }.map(\.name)

    static let ollamaBaseURL = URL(string: "http://localhost:11434")!
    static let ollamaModel = "gemma4:latest"
    static let embeddingModel = "mxbai-embed-large"
}
