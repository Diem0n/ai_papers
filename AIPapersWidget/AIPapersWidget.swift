//
//  AIPapersWidget.swift
//  AIPapersWidget
//
//  The daily digest on the desktop. Reads a snapshot the app prepares
//  (WidgetSnapshot.json) — no networking or models here. Every paper links
//  straight to it in the app.
//
//    small   the count, and the one paper to read next
//    medium  the bottom line and the top three papers
//    large   the bottom line, this week's themes, five papers with why they matter
//

import WidgetKit
import SwiftUI

struct DigestEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    static let sample = DigestEntry(date: .now, snapshot: WidgetSnapshot(
        generatedAt: .now, unread: 38, newToday: 12,
        tldr: "Agent reliability and cheaper inference dominate: harness design over bigger context.",
        themes: [.init(label: "RAG · Grounding", count: 28), .init(label: "Agents · Multi-agent", count: 15), .init(label: "Inference · KV cache", count: 9)],
        papers: [
            .init(id: "a", title: "Grow the Harness, Not the Context", topic: "Agents", line: "Swap your prompt scaffolds for reusable specialist agents.", fit: "Applies to you", hasCode: true),
            .init(id: "b", title: "Beyond Top-K: Interpretable Agentic Retrieval", topic: "RAG", line: "Replace fixed top-k with retrieval operations you can inspect.", fit: "Maybe", hasCode: false),
            .init(id: "c", title: "PagedKV-2: Cheaper Long-Context Serving", topic: "Inference", line: "Cuts KV memory 40% in vLLM-style servers.", fit: nil, hasCode: true),
            .init(id: "d", title: "Calibration as a First-Class Criterion", topic: "Evaluation", line: "Report calibration next to accuracy in your evals.", fit: nil, hasCode: false),
            .init(id: "e", title: "FLEET: Entropy-Guided Sampling", topic: "Reasoning", line: "Same accuracy as repeated sampling at a third of the cost.", fit: nil, hasCode: true),
        ],
        reviewDue: 2))
}

struct DigestProvider: TimelineProvider {
    func placeholder(in context: Context) -> DigestEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (DigestEntry) -> Void) {
        completion(context.isPreview ? .sample : DigestEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DigestEntry>) -> Void) {
        // The app reloads timelines whenever it writes a new snapshot; this is only a fallback.
        let next = Calendar.current.date(byAdding: .hour, value: 3, to: .now) ?? .now.addingTimeInterval(3 * 3600)
        completion(Timeline(entries: [DigestEntry(date: .now, snapshot: WidgetSnapshot.load())], policy: .after(next)))
    }
}

struct AIPapersWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DigestEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.papers.isEmpty {
                switch family {
                case .systemSmall: SmallView(snapshot: snapshot)
                case .systemMedium: MediumView(snapshot: snapshot)
                default: LargeView(snapshot: snapshot)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Header(snapshot: entry.snapshot)
                    Spacer()
                    Text(entry.snapshot == nil ? "Open AI Papers to prepare your digest." : "You're all caught up.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color.accentColor.opacity(0.16), Color.clear], startPoint: .topLeading, endPoint: .center)
                .background(.background)
        }
        .widgetURL(URL(string: "aipapers://trend"))
    }
}

private struct Header: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.text.magnifyingglass")
            Text("AI PAPERS")
                .tracking(0.6)
            Spacer(minLength: 4)
            if let snapshot {
                Text("\(snapshot.unread) unread")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.tint)
    }
}

private struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let paper = snapshot.papers[0]
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.newToday)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                Text("new\ntoday")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(-2)
            }
            Spacer(minLength: 2)
            Text("READ NEXT")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(paper.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(3)
            Chips(paper: paper)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetSnapshot.paperURL(paper.id))
    }
}

private struct MediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(snapshot: snapshot)
            if let tldr = snapshot.tldr {
                Text(tldr)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ForEach(snapshot.papers.prefix(3), id: \.id) { paper in
                Link(destination: WidgetSnapshot.paperURL(paper.id)) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(paper.fit == "Applies to you" ? Color.green : Color.accentColor)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(paper.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Chips(paper: paper)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LargeView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(snapshot: snapshot)
            if let tldr = snapshot.tldr {
                Text(tldr)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }
            if !snapshot.themes.isEmpty {
                HStack(spacing: 5) {
                    ForEach(snapshot.themes.prefix(3), id: \.self) { theme in
                        Text("\(theme.count) \(theme.label)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                }
            }
            Divider()
            ForEach(snapshot.papers.prefix(5), id: \.id) { paper in
                Link(destination: WidgetSnapshot.paperURL(paper.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(paper.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if let line = paper.line {
                            Text(line)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Chips(paper: paper)
                    }
                }
            }
            Spacer(minLength: 0)
            if snapshot.reviewDue > 0 {
                Label("\(snapshot.reviewDue) review card\(snapshot.reviewDue == 1 ? "" : "s") due", systemImage: "rectangle.stack")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct Chips: View {
    let paper: WidgetSnapshot.Item

    var body: some View {
        HStack(spacing: 5) {
            Text(paper.topic.uppercased())
            if let fit = paper.fit, fit != "Not for your stack" {
                Text("·")
                Text(fit == "Applies to you" ? "FOR YOU" : "MAYBE")
                    .foregroundStyle(fit == "Applies to you" ? .green : .orange)
            }
            if paper.hasCode {
                Text("·")
                Text("CODE").foregroundStyle(.green)
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct AIPapersWidget: Widget {
    let kind: String = "AIPapersWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DigestProvider()) { entry in
            AIPapersWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AI Papers Digest")
        .description("What to read next, ranked for your stack, with this week's themes.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) { AIPapersWidget() } timeline: { DigestEntry.sample }
#Preview(as: .systemMedium) { AIPapersWidget() } timeline: { DigestEntry.sample }
#Preview(as: .systemLarge) { AIPapersWidget() } timeline: { DigestEntry.sample }
