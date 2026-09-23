//
//  RelevanceService.swift
//  AIPapers
//
//  Deterministic relevance scoring. An LLM signal can nudge the score,
//  but the app never depends solely on an opaque LLM judgment.
//

import Foundation

enum RelevanceService {
    /// Score in 0...1. `llmRelevance` is the model's own engineeringRelevance
    /// estimate, folded in as a minority weight once a summary exists.
    static func score(
        title: String,
        abstractText: String,
        publishedAt: Date,
        llmRelevance: Double? = nil,
        topics: [String] = AppConstants.topics,
        referenceDate: Date = .now
    ) -> Double {
        let topic = topicMatchScore(title: title, abstractText: abstractText, topics: topics)
        let recency = recencyScore(publishedAt: publishedAt, referenceDate: referenceDate)

        let combined: Double
        if let llmRelevance {
            combined = (topic * 0.5) + (recency * 0.3) + (min(max(llmRelevance, 0), 1) * 0.2)
        } else {
            combined = (topic * 0.7) + (recency * 0.3)
        }
        return min(max(combined, 0), 1)
    }

    // ponytail: keyword matching only, no code/model-availability or user-history
    // signal yet — those need infra this MVP doesn't have. Fold in once
    // interaction tracking and GitHub-link detection exist.
    private static func topicMatchScore(title: String, abstractText: String, topics: [String]) -> Double {
        guard !topics.isEmpty else { return 0 }
        let matches = matchingTopics(title: title, abstractText: abstractText, topics: topics).count
        return min(Double(matches) / 3.0, 1.0)
    }

    /// Which of the fixed topics actually appear in this paper's text —
    /// also used to categorize papers that haven't been LLM-summarized
    /// (and thus have no model-assigned topic) yet.
    static func matchingTopics(title: String, abstractText: String, topics: [String] = AppConstants.topics) -> [String] {
        let haystack = (title + " " + abstractText).lowercased()
        return topics.filter { haystack.contains($0.lowercased()) }
    }

    private static func recencyScore(publishedAt: Date, referenceDate: Date) -> Double {
        let days = referenceDate.timeIntervalSince(publishedAt) / 86400
        guard days >= 0 else { return 1.0 }
        return max(0, 1 - (days / 30))
    }
}
