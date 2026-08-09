//
//  SharedModelContainer.swift
//  AIPapersWidget
//
//  Points at the same SQLite store as the main app via the shared App Group
//  container, so the widget reads real data instead of its own empty store.
//

import Foundation
import SwiftData

enum SharedModelContainer {
    static let appGroupID = "group.com.Diem0n.AIPapers"

    static func make() -> ModelContainer? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let storeURL = groupURL.appendingPathComponent("AIPapers.sqlite")
        let config = ModelConfiguration(schema: Schema([Paper.self]), url: storeURL)
        return try? ModelContainer(for: Paper.self, configurations: config)
    }
}
