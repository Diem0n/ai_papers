//
//  SharedModelContainer.swift
//  AIPapersWidget
//
//  Points at the same SQLite store as the main app via the shared App Group
//  container, so the widget reads real data instead of its own empty store.
//

import Foundation
import SwiftData
import SQLite3

enum SharedModelContainer {
    static let appGroupID = "group.com.Diem0n.AIPapers"

    static func make() -> ModelContainer? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let storeURL = groupURL.appendingPathComponent("AIPapers.sqlite")
        StoreMigration.addColumnsIfNeeded(at: storeURL)
        let config = ModelConfiguration(schema: Schema([Paper.self]), url: storeURL)
        return try? ModelContainer(for: Paper.self, configurations: config)
    }
}

/// See the app-target SharedModelContainer for why this exists.
enum StoreMigration {
    static func addColumnsIfNeeded(at storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "ALTER TABLE ZPAPER ADD COLUMN ZEMBEDDING BLOB", nil, nil, nil)
    }
}
