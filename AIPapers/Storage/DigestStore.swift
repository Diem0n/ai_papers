//
//  DigestStore.swift
//  AIPapers
//
//  The model-written text for the weekly digest, cached so it is generated
//  once per set of papers. Same approach as TrendBriefStore: one Codable
//  JSON file in the App Group container, no second SwiftData schema.
//

import Foundation

struct DigestNarrative: Codable {
    struct ThemeText: Codable {
        let index: Int
        let headline: String
        let takeaway: String
        let soWhat: String
    }

    /// Ties this text to the exact set of papers it was written about.
    let signature: String
    let model: String
    let generatedAt: Date
    let tldr: String
    let themes: [ThemeText]
}

enum DigestStore {
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupID)?
            .appendingPathComponent("DigestNarrative.json")
    }

    static func load() -> DigestNarrative? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DigestNarrative.self, from: data)
    }

    static func save(_ narrative: DigestNarrative) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(narrative) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
