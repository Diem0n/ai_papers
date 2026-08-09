//
//  AIPapersTrendWidget.swift
//  AIPapersWidget
//
//  A dedicated widget for the trend brief, separate from the papers digest
//  widget. WidgetKit has no scrolling — this shows as much text as the
//  largest available size fits, and taps through to TrendBriefView for the
//  full, actually-scrollable read.
//

import WidgetKit
import SwiftUI

struct TrendEntry: TimelineEntry {
    let date: Date
    let brief: TrendBrief?

    static let sample = TrendEntry(
        date: .now,
        brief: TrendBrief(
            day: .now,
            generatedAt: .now,
            content: "Efficiency and tool-use agents dominate this week, with multiple papers tackling long-context inference cost through sparse attention and dynamic routing. A second cluster focuses on retrieval-augmented agents that fetch tool specifications on demand rather than holding them all in context, suggesting the field is moving toward more composable, memory-efficient agent architectures rather than simply scaling context windows.",
            paperCount: 15
        )
    )
}

struct TrendProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrendEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (TrendEntry) -> Void) {
        completion(context.isPreview ? .sample : fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrendEntry>) -> Void) {
        let entry = fetchEntry()
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 4, to: .now) ?? .now.addingTimeInterval(4 * 3600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func fetchEntry() -> TrendEntry {
        let latest = TrendBriefStore.loadLatest()
        let todaysBrief = latest.flatMap { Calendar.current.isDateInToday($0.day) ? $0 : nil }
        return TrendEntry(date: .now, brief: todaysBrief)
    }
}

struct TrendWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrendEntry

    var body: some View {
        Link(destination: trendURL) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Industry Trend", systemImage: "text.book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let brief = entry.brief {
                    Text(brief.content)
                        .font(.caption)
                        .lineLimit(lineLimit)
                    Spacer(minLength: 0)
                    Text("Based on \(brief.paperCount) papers — tap to read in full")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Spacer()
                    Text("No brief yet today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .buttonStyle(.plain)
    }

    private var lineLimit: Int {
        switch family {
        case .systemSmall: 5
        case .systemMedium: 5
        case .systemLarge: 15
        case .systemExtraLarge: 24
        default: 5
        }
    }
}

struct AIPapersTrendWidget: Widget {
    let kind = "AIPapersTrendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrendProvider()) { entry in
            TrendWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Industry Trend Brief")
        .description("Where AI engineering is heading, synthesized daily from your papers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

#Preview(as: .systemLarge) {
    AIPapersTrendWidget()
} timeline: {
    TrendEntry.sample
}

#Preview(as: .systemExtraLarge) {
    AIPapersTrendWidget()
} timeline: {
    TrendEntry.sample
}
