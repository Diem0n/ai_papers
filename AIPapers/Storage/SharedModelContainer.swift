//
//  SharedModelContainer.swift
//  AIPapers
//
//  Stores data in the shared App Group container instead of the app's
//  private container, so AIPapersWidget can read the same papers.
//

import Foundation
import SwiftData
import SQLite3

enum SharedModelContainer {
    static let appGroupID = "group.com.Diem0n.AIPapers"

    static func make() -> ModelContainer {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            // ponytail: falls back to a private, non-shared store if the App Group
            // is ever misconfigured, so the app still launches — the widget just
            // won't see data until the group container is reachable again.
            return try! ModelContainer(for: Paper.self)
        }
        let storeURL = groupURL.appendingPathComponent("AIPapers.sqlite")
        StoreMigration.addColumnsIfNeeded(at: storeURL)
        let config = ModelConfiguration(schema: Schema([Paper.self]), url: storeURL)
        return try! ModelContainer(for: Paper.self, configurations: config)
    }
}

/// SwiftData doesn't auto-migrate a custom-URL store when a stored property is
/// added — it crashes with an uncaught NSException Swift can't catch. Add any
/// missing columns via raw SQLite (ALTER TABLE preserves existing rows) before
/// SwiftData ever opens the file, so the crash path is never reached.
enum StoreMigration {
    static func addColumnsIfNeeded(at storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        // Fails harmlessly (and is ignored) if the column already exists.
        sqlite3_exec(db, "ALTER TABLE ZPAPER ADD COLUMN ZEMBEDDING BLOB", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE ZPAPER ADD COLUMN ZSUBTOPIC VARCHAR", nil, nil, nil)
    }
}
