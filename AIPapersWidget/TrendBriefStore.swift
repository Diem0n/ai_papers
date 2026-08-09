//
//  TrendBriefStore.swift
//  AIPapersWidget
//
//  See the app-target TrendBriefStore for why this is a plain JSON file
//  rather than a second SwiftData model.
//

import Foundation

struct TrendBrief: Codable {
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
}
