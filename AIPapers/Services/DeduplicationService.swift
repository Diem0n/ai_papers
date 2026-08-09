//
//  DeduplicationService.swift
//  AIPapers
//
//  Exact-match duplicate detection. A pure function so it's testable
//  without touching SwiftData: given what's already stored, decide what's new.
//

import Foundation

enum DeduplicationService {
    /// Returns only the papers whose `id` isn't already present locally.
    static func filterNewPapers(_ incoming: [ArxivPaper], existingIDs: Set<String>) -> [ArxivPaper] {
        incoming.filter { !existingIDs.contains($0.id) }
    }
}
