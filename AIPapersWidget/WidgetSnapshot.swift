//
//  WidgetSnapshot.swift
//  AIPapersWidget
//
//  What the widget shows, prepared by the app and written to the App Group
//  as JSON — the widget never runs a model or touches the network. Keep in
//  sync with the app-target copy (AIPapers/Storage/WidgetSnapshot.swift).
//

import Foundation

struct WidgetSnapshot: Codable {
    struct Theme: Codable, Hashable {
        let label: String
        let count: Int
    }

    struct Item: Codable, Hashable, Identifiable {
        let id: String
        let title: String
        let topic: String
        let line: String?
        let fit: String?
        let hasCode: Bool
    }

    let generatedAt: Date
    let unread: Int
    let newToday: Int
    let tldr: String?
    let themes: [Theme]
    let papers: [Item]
    let reviewDue: Int

    static let fileName = "WidgetSnapshot.json"

    static func load() -> WidgetSnapshot? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.Diem0n.AIPapers")?
            .appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func paperURL(_ id: String) -> URL {
        URL(string: "aipapers://paper/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id))!
    }
}
