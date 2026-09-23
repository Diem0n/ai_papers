//
//  DashboardView.swift
//  AIPapers
//
//  "What should I read today?" — a bento grid of small widgets, each a
//  window onto one of the app's pages with a "View all" that opens the
//  detailed page. The grid stretches to fill the window. Clicking a paper
//  opens its full detail in a side inspector, so you never leave the page.
//  Refresh status lives in AppActivity (shown by ContentView's persistent
//  banner) so it isn't tied to this view's lifecycle.
//

import SwiftUI
import SwiftData
import Charts
import os

private let logger = Logger(subsystem: "com.Diem0n.AIPapers", category: "DashboardView")

struct DashboardView: View {
    @EnvironmentObject private var appActivity: AppActivity
    @Query(sort: \Paper.relevanceScore, order: .reverse) private var allPapers: [Paper]

    let onOpenSection: (AppSection) -> Void

    @State private var brief: TrendBrief?
    @State private var selectedPaper: Paper?
    @State private var inspectorShown = false

    private let gap: CGFloat = 12
    private let pagePadding: CGFloat = 20

    var body: some View {
        Group {
            if allPapers.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        bento
                            .frame(height: max(proxy.size.height - pagePadding * 2, 660))
                            .padding(pagePadding)
                    }
                }
            }
        }
        .navigationTitle("Dashboard")
        .inspector(isPresented: $inspectorShown) {
            inspectorContent
                .inspectorColumnWidth(min: 380, ideal: 520, max: 760)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    inspectorShown.toggle()
                } label: {
                    Label("Paper Detail", systemImage: "sidebar.trailing")
                }
                .disabled(selectedPaper == nil)
                .help("Show or hide the selected paper's detail")
            }
            ToolbarItem {
                if appActivity.isRefreshing {
                    Button {
                        appActivity.pauseRefresh()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                } else {
                    Button {
                        appActivity.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            logger.notice("Dashboard loaded with \(allPapers.count, privacy: .public) stored papers")
            appActivity.autoRefreshIfNeeded()
        }
        .onAppear { brief = TrendBriefStore.loadLatest() }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if let selectedPaper {
            PaperDetailView(paper: selectedPaper, onSelectRelated: { self.selectedPaper = $0 })
        } else {
            ContentUnavailableView("Select a paper", systemImage: "doc.text")
        }
    }

    private func open(_ paper: Paper) {
        selectedPaper = paper
        inspectorShown = true
    }

    // MARK: Grid

    private var bento: some View {
        VStack(spacing: gap) {
            statsRow
            GeometryReader { proxy in
                mainGrid(height: proxy.size.height)
            }
        }
    }

    /// Splits a height into proportional parts, leaving room for the gaps between them.
    private func split(_ total: CGFloat, _ fractions: [CGFloat]) -> [CGFloat] {
        let usable = total - gap * CGFloat(fractions.count - 1)
        return fractions.map { usable * $0 }
    }

    private func mainGrid(height: CGFloat) -> some View {
        let left = split(height, [0.62, 0.38])
        let right = split(height, [0.28, 0.36, 0.36])
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                topPapersCard(rows: rowCount(fitting: left[0])).frame(height: left[0])
                recentCard(rows: rowCount(fitting: left[1])).frame(height: left[1])
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: gap) {
                pulledCard.frame(height: right[0])
                HStack(alignment: .top, spacing: gap) {
                    topicsCard.frame(height: right[1])
                    trendingCard.frame(height: right[1])
                }
                HStack(alignment: .top, spacing: gap) {
                    briefCard(lines: lineCount(fitting: right[2])).frame(height: right[2])
                    readingListCard(rows: rowCount(fitting: right[2])).frame(height: right[2])
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// How many paper rows fit in a card of this height (a row is ~62pt, the header ~56).
    private func rowCount(fitting height: CGFloat) -> Int {
        max(2, Int((height - 56) / 62))
    }

    private func lineCount(fitting height: CGFloat) -> Int {
        max(3, Int((height - 60) / 19))
    }

    private var statsRow: some View {
        HStack(spacing: gap) {
            statTile("\(allPapers.count)", "total papers")
            statTile("\(allPapers.filter { !$0.isRead }.count)", "unread")
            statTile("\(allPapers.filter { $0.summary != nil }.count)", "summarized")
            statTile("\(allPapers.filter { $0.isFavorite }.count)", "favorited")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        Button { onOpenSection(.archive) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title, design: .monospaced, weight: .bold))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .bentoBackground()
        }
        .buttonStyle(.plain)
    }

    // MARK: Cards

    private func topPapersCard(rows: Int) -> some View {
        let unread = allPapers.filter { !$0.isRead }
        let papers = Array((unread.isEmpty ? allPapers : unread).prefix(rows))
        return BentoCard(title: "Top unread", action: { onOpenSection(.archive) }) {
            paperList(papers)
        }
    }

    private func recentCard(rows: Int) -> some View {
        let recent = Array(allPapers.sorted { $0.discoveredAt > $1.discoveredAt }.prefix(rows))
        return BentoCard(title: "Recently pulled", action: { onOpenSection(.archive) }) {
            paperList(recent, showsDate: true)
        }
    }

    private func paperList(_ papers: [Paper], showsDate: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(papers.enumerated()), id: \.element.id) { index, paper in
                if index > 0 { Divider() }
                paperRow(paper, showsDate: showsDate)
            }
        }
    }

    private func paperRow(_ paper: Paper, showsDate: Bool) -> some View {
        Button { open(paper) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(paper.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text("\(Int(paper.relevanceScore * 100))%").foregroundStyle(.tint)
                    Text("·")
                    Text(AnalyticsService.fixedTopic(for: paper))
                    if showsDate {
                        Text("·")
                        Text(paper.discoveredAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(selectedPaper?.id == paper.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pulledCard: some View {
        BentoCard(title: "Papers pulled", action: { onOpenSection(.analytics) }) {
            Chart(AnalyticsService.papersPerDay(allPapers)) { day in
                BarMark(x: .value("Date", day.date, unit: .day), y: .value("Papers", day.count))
                    .foregroundStyle(.tint)
            }
            .chartYAxis(.hidden)
            .frame(maxHeight: .infinity)
        }
    }

    private var topicsCard: some View {
        BentoCard(title: "Top topics", action: { onOpenSection(.analytics) }) {
            Chart(AnalyticsService.topCategories(allPapers, limit: 5)) { item in
                BarMark(x: .value("Count", item.count), y: .value("Topic", item.category), height: .ratio(0.6))
                    .foregroundStyle(.tint)
            }
            .chartXAxis(.hidden)
            .frame(maxHeight: .infinity)
        }
    }

    private var trendingCard: some View {
        let trending = AnalyticsService.trendingTopics(allPapers, limit: 5)
        return BentoCard(title: "Trending", action: { onOpenSection(.analytics) }) {
            if trending.isEmpty {
                Text("Not enough history yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(trending) { topic in
                        HStack {
                            Text(topic.topic)
                                .font(.system(.callout, design: .monospaced))
                            Spacer()
                            Image(systemName: topic.delta > 0 ? "arrow.up.right" : "arrow.down.right")
                                .foregroundStyle(topic.delta > 0 ? .green : .red)
                            Text("\(topic.recentCount)")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func briefCard(lines: Int) -> some View {
        BentoCard(title: "Trend brief", action: { onOpenSection(.trend) }) {
            if let brief {
                Text(brief.content)
                    .font(.callout)
                    .lineLimit(lines)
            } else {
                Text("No brief yet — it's generated once a day after a refresh.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func readingListCard(rows: Int) -> some View {
        let queue = allPapers.filter { $0.status == .reading || $0.status == .toRead }
            .sorted { ($0.status == .reading ? 0 : 1) < ($1.status == .reading ? 0 : 1) }
        return BentoCard(title: "Reading list", action: { onOpenSection(.archive) }) {
            if queue.isEmpty {
                Text("Mark a paper To read or Reading in its detail view and it lands here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(queue.prefix(max(2, rows - 1)).enumerated()), id: \.element.id) { index, paper in
                        if index > 0 { Divider() }
                        Button { open(paper) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: paper.status?.systemImage ?? "bookmark")
                                    .foregroundStyle(paper.status == .reading ? Color.accentColor : .secondary)
                                Text(paper.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Empty state

    @ViewBuilder
    private var emptyState: some View {
        if appActivity.isRefreshing {
            VStack(spacing: 12) {
                ProgressView()
                Text(appActivity.refreshProgressText ?? "Refreshing…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No papers yet",
                systemImage: "tray",
                description: Text("Refresh to fetch today's AI engineering papers.")
            )
        }
    }
}

/// A titled bento tile with an optional "View all" link to its detail page.
private struct BentoCard<Content: View>: View {
    let title: String
    var action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                if let action {
                    Button(action: action) {
                        Text("View all \u{2192}").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            content
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .bentoBackground()
        .clipped()
    }
}

private extension View {
    func bentoBackground() -> some View {
        background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }
}
