//
//  WidgetSnapshot.swift
//  AIPapers
//
//  Prepares what the widget shows and writes it to the App Group, then asks
//  WidgetKit to reload. The widget-target copy of these types
//  (AIPapersWidget/WidgetSnapshot.swift) only reads it; keep the two in sync.
//

import Foundation
import WidgetKit
import SwiftData

nonisolated struct WidgetSnapshot: Codable, Equatable {
    struct Theme: Codable, Equatable {
        let label: String
        let count: Int
    }

    struct Item: Codable, Equatable {
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
}

@MainActor
enum WidgetSnapshotWriter {
    private static let file = JSONFile<WidgetSnapshot>(name: "WidgetSnapshot.json")

    /// Rebuilds the snapshot from the store — for callers that don't already have the digest.
    static func refresh(_ container: ModelContainer) {
        guard let papers = try? PaperRepository(context: ModelContext(container)).allPapers() else { return }
        let digest = DigestService.build(papers)
        let narrative = DigestStore.load().flatMap { $0.signature == digest?.signature ? $0 : nil }
        write(papers: papers, digest: digest, narrative: narrative)
    }

    /// Unread papers that apply to your stack first, then by relevance.
    static func write(papers: [Paper], digest: Digest?, narrative: DigestNarrative?) {
        let insights = InsightStore.shared
        let links = CodeLinkStore.shared.links
        let unread = papers.filter { !$0.isRead }
        func rank(_ p: Paper) -> Double {
            let fit = insights.currentFit(p.id)?.verdict
            return p.relevanceScore + (fit == .applies ? 1 : fit == .maybe ? 0.3 : fit == .no ? -1 : 0)
        }
        let top = unread.sorted { rank($0) > rank($1) }.prefix(6)
        let items = top.map { paper in
            WidgetSnapshot.Item(
                id: paper.id,
                title: paper.title,
                topic: AnalyticsService.fixedTopic(for: paper),
                line: insights.currentFit(paper.id).flatMap { $0.change.isEmpty ? nil : $0.change } ?? paper.whyItMatters ?? paper.summary,
                fit: insights.currentFit(paper.id).map { $0.verdict.label },
                hasCode: links[paper.id]?.hasCode ?? false
            )
        }
        let tldr = narrative?.tldr ?? digest.flatMap { d in d.themes.first.map { "\(d.paperCount) new papers, led by \($0.label)." } }
        let themes = (digest?.themes ?? []).prefix(4).map { theme in
            WidgetSnapshot.Theme(label: narrative?.themes.first { $0.index == theme.id }?.headline ?? theme.label, count: theme.papers.count)
        }
        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            unread: unread.count,
            newToday: papers.filter { Calendar.current.isDateInToday($0.discoveredAt) }.count,
            tldr: tldr,
            themes: themes,
            papers: Array(items),
            reviewDue: ReviewStore.shared.due.count
        )
        // Only touch WidgetKit when the picture actually changed (ignoring the timestamp).
        if let old = file.load(), old.papers == snapshot.papers, old.unread == snapshot.unread,
           old.tldr == snapshot.tldr, old.themes == snapshot.themes, old.reviewDue == snapshot.reviewDue { return }
        file.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "AIPapersWidget")
    }
}
