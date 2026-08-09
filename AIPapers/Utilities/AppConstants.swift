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
    static let topics = [
        "LLM", "Agents", "RAG", "Retrieval", "Inference", "Fine-tuning",
        "Training", "Multimodal", "Computer Vision", "AI Systems",
        "Evaluation", "MLOps", "Generative AI", "Reasoning",
        "Model Optimization", "AI Infrastructure"
    ]

    static let ollamaBaseURL = URL(string: "http://localhost:11434")!
    static let ollamaModel = "llama3.1"
}
