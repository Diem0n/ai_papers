//
//  TrendBriefStore.swift
//  AIPapers
//
//  A single JSON file in the shared App Group container — deliberately not a
//  second SwiftData model. Two independently-declared @Model types already
//  caused one schema-drift crash tonight (see SharedModelContainer); a plain
//  Codable file read/written by hand has no schema to drift.
//
//  Keeps a rolling history (not just the latest) so future features have
//  something to work with, not just today's brief.
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
    private static let maxHistory = 30

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupID)?
            .appendingPathComponent("TrendBriefHistory.json")
    }

    static func loadHistory() -> [TrendBrief] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TrendBrief].self, from: data)) ?? []
    }

    static func loadLatest() -> TrendBrief? {
        loadHistory().max { $0.day < $1.day }
    }

    static func save(_ brief: TrendBrief) {
        guard let url = fileURL else { return }
        var history = loadHistory()
        history.removeAll { Calendar.current.isDate($0.day, inSameDayAs: brief.day) }
        history.append(brief)
        history.sort { $0.day < $1.day }
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
