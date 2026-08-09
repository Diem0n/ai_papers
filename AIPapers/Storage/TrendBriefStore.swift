//
//  TrendBriefStore.swift
//  AIPapers
//
//  A single JSON file in the shared App Group container — deliberately not a
//  second SwiftData model. Two independently-declared @Model types already
//  caused one schema-drift crash tonight (see SharedModelContainer); a plain
//  Codable file read/written by hand has no schema to drift.
//

import Foundation

struct TrendBrief: Codable {
    /// Start-of-day this brief covers — compare with Calendar.isDateInToday
    /// to decide whether a fresh one is needed.
    let day: Date
    let generatedAt: Date
    let content: String
    let paperCount: Int
}

enum TrendBriefStore {
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupID)?
            .appendingPathComponent("TrendBrief.json")
    }

    static func load() -> TrendBrief? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TrendBrief.self, from: data)
    }

    static func save(_ brief: TrendBrief) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(brief) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
