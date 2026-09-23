//
//  PicksStore.swift
//  AIPapers
//
//  The model's last "picks for you", cached against a signature of the
//  favorites/reads and the shortlist they were made from, so the dashboard
//  doesn't re-ask the model every time it's opened. Same approach as
//  DigestStore: one Codable JSON file in the App Group container.
//

import Foundation

struct PicksCache: Codable {
    struct Entry: Codable {
        let id: String
        let why: String
    }

    let signature: String
    let model: String
    let generatedAt: Date
    let picks: [Entry]
}

enum PicksStore {
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupID)?
            .appendingPathComponent("PicksCache.json")
    }

    static func load() -> PicksCache? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PicksCache.self, from: data)
    }

    static func save(_ cache: PicksCache) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
