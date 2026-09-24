//
//  CodeLinkStore.swift
//  AIPapers
//
//  Code/weights availability per paper, kept in memory for the UI and in a
//  JSON file on disk. "Nothing found" is cached too, and re-checked after a
//  week — repositories often appear some days after a paper does.
//

import Foundation
import Combine

@MainActor
final class CodeLinkStore: ObservableObject {
    static let shared = CodeLinkStore()

    @Published private(set) var links: [String: CodeLinks]
    private let file = JSONFile<[String: CodeLinks]>(name: "CodeLinks.json")

    private init() {
        links = file.load() ?? [:]
    }

    func set(_ value: CodeLinks, for id: String) {
        links[id] = value
        file.save(links)
    }

    func needsCheck(_ id: String) -> Bool {
        guard let existing = links[id] else { return true }
        if existing.hasCode || existing.hasWeights { return false }
        return existing.fetchedAt < Date.now.addingTimeInterval(-7 * 86_400)
    }
}
