//
//  CloudScope.swift
//  AIPapers
//
//  How much is allowed to leave the Mac, reader's choice. Off by default —
//  every tier above "Local only" needs an OpenRouter key before anything
//  actually routes to the cloud (see OpenRouterService).
//

import Foundation

/// Which call a prompt is for — gates it against the current CloudScope.
nonisolated enum CloudFeature {
    case summaries, claims, plan, explainAsk, stackFit

    /// True once this tier allows the feature to use the cloud model.
    func isEligible(at scope: CloudScope) -> Bool {
        switch scope {
        case .local: return false
        case .papers: return self == .summaries || self == .claims || self == .plan
        case .everything: return true
        }
    }
}

enum CloudScope: String, CaseIterable, Identifiable {
    /// Nothing ever leaves the Mac. Ollama only.
    case local
    /// Paper content (title/abstract/claims) may go to the cloud model;
    /// your own writing — Ask questions, /explain, your stack — never does.
    case papers
    /// Everything may use the cloud model, including your stack description
    /// and what you ask.
    case everything

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: "Local only"
        case .papers: "Cloud for paper analysis"
        case .everything: "Cloud for everything"
        }
    }

    var detail: String {
        switch self {
        case .local: "Nothing leaves this Mac. Summaries, claims, plans, Ask and /explain all run on your local Ollama model."
        case .papers: "Summaries, claims and implementation plans may use the cloud model (paper titles/abstracts only). Ask, /explain and your stack description stay local."
        case .everything: "Everything may use the cloud model — including Ask questions, /explain topics, and your stack description in Settings."
        }
    }
}
