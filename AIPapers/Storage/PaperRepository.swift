//
//  PaperRepository.swift
//  AIPapers
//
//  SwiftData access for Paper. Views and services go through this rather
//  than touching ModelContext directly.
//

import Foundation
import SwiftData

@MainActor
final class PaperRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func existingIDs() throws -> Set<String> {
        let descriptor = FetchDescriptor<Paper>()
        let papers = try context.fetch(descriptor)
        return Set(papers.map(\.id))
    }

    func insert(_ paper: Paper) {
        context.insert(paper)
    }

    func save() throws {
        try context.save()
    }
}
