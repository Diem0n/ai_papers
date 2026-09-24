//
//  Paper.swift
//  AIPapers
//

import Foundation
import SwiftData

@Model
final class Paper {
    @Attribute(.unique)
    var id: String

    var title: String
    var authors: String
    var abstractText: String
    var url: String

    var publishedAt: Date
    var discoveredAt: Date

    var summary: String?
    var whyItMatters: String?

    var category: String?
    var relevanceScore: Double

    var isRead: Bool
    var isFavorite: Bool

    /// Semantic embedding of title+abstract, generated on demand when the
    /// paper is first opened. Powers "Related Papers" via cosine similarity.
    var embedding: [Double]?

    /// Third taxonomy level under `category` (the fixed topic), assigned by
    /// the model. "Other" means it was classified and nothing on the list fit.
    var subtopic: String?

    /// The reader's own workflow state (see ReadingStatus) and free-text notes
    /// — distinct from `isRead`, which just means "has been opened".
    var readingStatus: String?
    var notes: String?

    /// Whether the reader tried the paper's idea and how it went (see TrialOutcome).
    var trialOutcome: String?

    init(
        id: String,
        title: String,
        authors: String,
        abstractText: String,
        url: String,
        publishedAt: Date,
        discoveredAt: Date = .now,
        summary: String? = nil,
        whyItMatters: String? = nil,
        category: String? = nil,
        relevanceScore: Double = 0,
        isRead: Bool = false,
        isFavorite: Bool = false,
        embedding: [Double]? = nil,
        subtopic: String? = nil,
        readingStatus: String? = nil,
        notes: String? = nil,
        trialOutcome: String? = nil
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.abstractText = abstractText
        self.url = url
        self.publishedAt = publishedAt
        self.discoveredAt = discoveredAt
        self.summary = summary
        self.whyItMatters = whyItMatters
        self.category = category
        self.relevanceScore = relevanceScore
        self.isRead = isRead
        self.isFavorite = isFavorite
        self.embedding = embedding
        self.subtopic = subtopic
        self.readingStatus = readingStatus
        self.notes = notes
        self.trialOutcome = trialOutcome
    }
}
