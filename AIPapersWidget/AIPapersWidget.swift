//
//  AIPapersWidget.swift
//  AIPapersWidget
//
//  Reads from the same App Group store the main app writes to — refresh()
//  never runs inside the widget, it only ever renders data prepared elsewhere.
//

import WidgetKit
import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.Diem0n.AIPapers", category: "Widget")

struct PaperSummaryInfo: Identifiable {
    let id: String
    let title: String
    let category: String?
    let summary: String?
    let whyItMatters: String?

    init(_ paper: Paper) {
        id = paper.id
        title = paper.title
        category = paper.category
        summary = paper.summary
        whyItMatters = paper.whyItMatters
    }

    init(id: String, title: String, category: String?, summary: String?, whyItMatters: String?) {
        self.id = id
        self.title = title
        self.category = category
        self.summary = summary
        self.whyItMatters = whyItMatters
    }
}

struct PapersEntry: TimelineEntry {
    let date: Date
    let papers: [PaperSummaryInfo]
    let newTodayCount: Int

    static let sample = PapersEntry(
        date: .now,
        papers: [
            PaperSummaryInfo(id: "1", title: "Efficient Sparse Attention via Dynamic Routing", category: "LLM", summary: "A routing mechanism that cuts attention cost to near-linear for long contexts.", whyItMatters: "Cheaper long-context inference without a quality hit."),
            PaperSummaryInfo(id: "2", title: "Retrieval-Augmented Agents for Tool Use", category: "Agents", summary: "Agents that retrieve tool specs on demand instead of holding them all in context.", whyItMatters: "Scales tool-use agents past small, fixed toolkits."),
        ],
        newTodayCount: 5
    )
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PapersEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (PapersEntry) -> Void) {
        completion(context.isPreview ? .sample : fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PapersEntry>) -> Void) {
        let entry = fetchEntry()
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 4, to: .now) ?? .now.addingTimeInterval(4 * 3600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func fetchEntry() -> PapersEntry {
        guard let container = SharedModelContainer.make() else {
            logger.error("Could not open the shared App Group container — check the App Group entitlement.")
            return PapersEntry(date: .now, papers: [], newTodayCount: 0)
        }
        let context = ModelContext(container)
        let startOfDay = Calendar.current.startOfDay(for: .now)

        let todayDescriptor = FetchDescriptor<Paper>(
            predicate: #Predicate { $0.discoveredAt >= startOfDay },
            sortBy: [SortDescriptor(\.relevanceScore, order: .reverse)]
        )
        let todaysPapers: [Paper]
        do {
            todaysPapers = try context.fetch(todayDescriptor)
        } catch {
            logger.error("Widget fetch failed: \(String(describing: error), privacy: .public)")
            todaysPapers = []
        }

        let papersToShow: [Paper]
        if todaysPapers.isEmpty {
            var fallback = FetchDescriptor<Paper>(sortBy: [SortDescriptor(\.relevanceScore, order: .reverse)])
            fallback.fetchLimit = 5
            papersToShow = (try? context.fetch(fallback)) ?? []
        } else {
            papersToShow = todaysPapers
        }

        logger.notice("Widget timeline: \(todaysPapers.count, privacy: .public) today, \(papersToShow.count, privacy: .public) shown")

        return PapersEntry(
            date: .now,
            papers: papersToShow.prefix(5).map(PaperSummaryInfo.init),
            newTodayCount: todaysPapers.count
        )
    }
}

func paperURL(_ id: String) -> URL {
    URL(string: "aipapers://paper/\(id)")!
}

struct AIPapersWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PapersEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge, .systemExtraLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

private struct SmallWidgetView: View {
    let entry: PapersEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(entry.newTodayCount) new today")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let top = entry.papers.first {
                Text(top.title)
                    .font(.headline)
                    .lineLimit(3)
                if let summary = top.summary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else {
                Spacer()
                Text("No papers yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(entry.papers.first.map { paperURL($0.id) })
    }
}

private struct MediumWidgetView: View {
    let entry: PapersEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(entry.newTodayCount) new papers today")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.papers.isEmpty {
                Spacer()
                Text("No papers yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.papers.prefix(3)) { paper in
                    Link(destination: paperURL(paper.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(paper.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                if let category = paper.category {
                                    Text(category)
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.tertiary, in: Capsule())
                                }
                            }
                            if let summary = paper.summary {
                                Text(summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct LargeWidgetView: View {
    let entry: PapersEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's AI Digest — \(entry.newTodayCount) new")
                .font(.headline)
            if entry.papers.isEmpty {
                Spacer()
                Text("No papers yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.papers.prefix(4).enumerated()), id: \.element.id) { index, paper in
                    Link(destination: paperURL(paper.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(paper.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                if let category = paper.category {
                                    Text(category)
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.tertiary, in: Capsule())
                                }
                            }
                            if let summary = paper.summary {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if let whyItMatters = paper.whyItMatters {
                                Text("Why it matters: \(whyItMatters)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    if index < min(entry.papers.count, 4) - 1 {
                        Divider()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct AIPapersWidget: Widget {
    let kind: String = "AIPapersWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AIPapersWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AI Papers Digest")
        .description("Today's top AI engineering papers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    AIPapersWidget()
} timeline: {
    PapersEntry.sample
}

#Preview(as: .systemMedium) {
    AIPapersWidget()
} timeline: {
    PapersEntry.sample
}

#Preview(as: .systemLarge) {
    AIPapersWidget()
} timeline: {
    PapersEntry.sample
}
