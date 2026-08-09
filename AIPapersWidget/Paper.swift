//
//  Paper.swift
//  AIPapersWidget
//
//  Mirrors AIPapers/Models/Paper.swift. Widget extensions build as a
//  separate binary from the main app, so this can't be a shared source
//  file across a file-system-synchronized target without manual per-file
//  target membership in Xcode. SwiftData matches by type name against the
//  shared App Group store, so this must stay in sync with the app's model.
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
    var embedding: [Double]?

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
        embedding: [Double]? = nil
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
    }
}
