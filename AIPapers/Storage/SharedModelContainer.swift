//
//  SharedModelContainer.swift
//  AIPapers
//
//  Stores data in the shared App Group container instead of the app's
//  private container, so AIPapersWidget can read the same papers.
//

import Foundation
import SwiftData

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
        let config = ModelConfiguration(schema: Schema([Paper.self]), url: storeURL)
        return try! ModelContainer(for: Paper.self, configurations: config)
    }
}
