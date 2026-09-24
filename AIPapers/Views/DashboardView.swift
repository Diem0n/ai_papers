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
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: AskSession
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Paper.relevanceScore, order: .reverse) private var allPapers: [Paper]

    let onOpenSection: (AppSection) -> Void

    @State private var digest: Digest?
    @State private var narrative: DigestNarrative?
    @State private var selectedPaper: Paper?
    @State private var inspectorShown = false
    @State private var picks: [Pick] = []
    @State private var isPicking = false
    @State private var picksPersonalized = true
    @State private var askInput = ""
    @State private var askBlink = 0
    @FocusState private var askFocused: Bool

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
        .task(id: allPapers.count) {
            let built = DigestService.build(allPapers)
            digest = built
            // Only text written for exactly these papers; otherwise the card
            // shows the deterministic summary (the Trend Brief page writes the prose).
            narrative = DigestStore.load().flatMap { $0.signature == built?.signature ? $0 : nil }
        }
        .onChange(of: router.askTick) { askFocused = true }
        .task(id: picksKey) { await refreshPicks(force: false) }
    }

    /// Cheap stand-in for "did what you've read/favorited change" — recomputing
    /// the picks costs a pass over every embedding, so it's keyed on counts.
    private var picksKey: String {
        "\(allPapers.count)-\(allPapers.filter(\.isRead).count)-\(allPapers.filter(\.isFavorite).count)-\(allPapers.filter { $0.readingStatus != nil }.count)"
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
        let left = split(height, [0.42, 0.58])
        let right = split(height, [0.34, 0.66])
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                topPapersCard(rows: rowCount(fitting: left[0])).frame(height: left[0])
                picksCard.frame(height: left[1])
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: gap) {
                HStack(alignment: .top, spacing: gap) {
                    topicsCard.frame(height: right[0])
                    trendingCard.frame(height: right[0])
                }
                HStack(alignment: .top, spacing: gap) {
                    briefCard(lines: lineCount(fitting: right[1])).frame(height: right[1])
                    askCard.frame(height: right[1])
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
        // The picks card already features some unread papers; don't show the same ones twice.
        let picked = Set(picks.map(\.id))
        let unread = allPapers.filter { !$0.isRead && !picked.contains($0.id) }
        let papers = Array((unread.isEmpty ? allPapers : unread).prefix(rows))
        return BentoCard(title: "Top unread", action: { onOpenSection(.archive) }) {
            paperList(papers)
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

    /// The digest at card size: one bottom-line sentence and the top themes.
    /// The full narrative lives on the Trend Brief page.
    private func briefCard(lines: Int) -> some View {
        BentoCard(title: "Trend brief", action: { onOpenSection(.trend) }) {
            if let digest {
                VStack(alignment: .leading, spacing: 10) {
                    Text(narrative?.tldr ?? briefFallback(digest))
                        .font(.callout.weight(.semibold))
                        .lineLimit(3)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(digest.themes.prefix(max(1, lines / 3))) { theme in
                            HStack(spacing: 8) {
                                Text("\(theme.papers.count)")
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    .foregroundStyle(.tint)
                                    .frame(minWidth: 22, alignment: .trailing)
                                Text(narrative?.themes.first { $0.index == theme.id }?.headline ?? theme.label)
                                    .font(.callout)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } else {
                Text("No brief yet — it appears once papers have been pulled and embedded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func briefFallback(_ digest: Digest) -> String {
        guard let lead = digest.themes.first else { return "\(digest.paperCount) new papers this week." }
        return "\(digest.paperCount) new papers in \(digest.themes.count) themes, led by \(lead.label)."
    }

    // MARK: Picks

    /// Five unread papers chosen from what you've favorited and read. Every
    /// thin case still resolves to something sensible: with no history it's
    /// the most relevant unread papers (and says so), with under five unread
    /// it shows what there is, and if the model is unavailable the picks are
    /// the same shortlist with reasons taken from the data.
    private var picksCard: some View {
        BentoCard(title: "Picks for you", action: { onOpenSection(.archive) }) {
            if picks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30))
                        .foregroundStyle(.tint)
                    Text("You're all caught up.")
                        .font(.callout.weight(.semibold))
                    Text("Nothing unread right now — new picks appear after the next refresh.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(picks.enumerated()), id: \.element.id) { index, pick in
                                if index > 0 { Divider() }
                                pickRow(pick)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        if isPicking {
                            ProgressView().controlSize(.small)
                            Text("Choosing for you…").font(.caption).foregroundStyle(.secondary)
                        } else if !picksPersonalized {
                            Text("Favorite or finish a few papers and these picks get personal.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                Task { await refreshPicks(force: true) }
                            } label: {
                                Label("Re-pick", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                        }
                        Spacer()
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private func pickRow(_ pick: Pick) -> some View {
        Button { open(pick.paper) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(pick.paper.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(pick.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(selectedPaper?.id == pick.paper.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refreshPicks(force: Bool) async {
        let pool = PicksService.pool(from: allPapers)
        picksPersonalized = pool.isPersonalized
        // Instant, model-free picks first; the model's choice replaces them when it lands.
        picks = PicksService.fallbackPicks(pool)
        guard pool.isPersonalized, pool.candidates.count > 1 else { return }

        if !force, let cached = PicksStore.load(), cached.signature == pool.signature {
            picks = PicksService.restore(cached.picks.map { (id: $0.id, why: $0.why) }, in: pool)
            return
        }

        isPicking = true
        defer { isPicking = false }
        let liked = pool.liked.prefix(8).map(\.title)
        let candidates = pool.candidates.enumerated().map { offset, candidate in
            let synopsis = (candidate.paper.summary ?? candidate.paper.abstractText)
                .replacingOccurrences(of: "\n", with: " ")
            return "\(offset + 1). \(candidate.paper.title) — \(String(synopsis.prefix(160)))"
        }
        do {
            let chosen = try await OllamaService().pickPapers(liked: Array(liked), candidates: candidates)
            let result = PicksService.resolve(chosen, in: pool)
            PicksStore.save(PicksCache(
                signature: pool.signature,
                model: AppSettings.ollamaModel,
                generatedAt: .now,
                picks: result.map { PicksCache.Entry(id: $0.paper.id, why: $0.reason) }
            ))
            picks = result
        } catch {
            // Ollama down or a malformed answer: the model-free picks above stay.
        }
    }

    // MARK: Ask

    private var askSuggestions: [String] {
        AnalyticsService.topCategories(allPapers, limit: 2)
            .map(\.category)
            .filter { $0 != Taxonomy.uncategorized }
            .map { "What's new in \($0)?" }
    }

    /// Ask lives here, right on the dashboard: the answer is written in the
    /// card, and the input line at the bottom is the whole interface.
    private var askCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PixelEyeLogo(size: 22, blinkTrigger: askBlink)
                Text("ASK YOUR ARCHIVE")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                if !session.turns.isEmpty && !session.isBusy {
                    Button("Clear") { session.clear() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }

            askBody

            Divider()
            HStack(spacing: 8) {
                TextField("Ask about your papers…", text: $askInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($askFocused)
                    .onSubmit(sendAsk)
                    .disabled(session.isBusy)
                Button(action: sendAsk) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(session.isBusy || askInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .bentoBackground()
        .clipped()
        .onHover { if $0 { askBlink += 1 } }
        .onChange(of: session.turns.last?.isWorking) { _, working in
            if working == false { askBlink += 1 }
        }
    }

    @ViewBuilder
    private var askBody: some View {
        if let turn = session.turns.last {
            VStack(alignment: .leading, spacing: 8) {
                Text(turn.question)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if turn.isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching your papers…").font(.callout).foregroundStyle(.secondary)
                    }
                } else if let error = turn.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let answer = turn.answer {
                    ScrollView {
                        Text(answer)
                            .font(.callout)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 6) {
                        Text("SOURCES")
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(turn.sources.enumerated()), id: \.element.paper.id) { index, source in
                            Button("[\(index + 1)]") { open(source.paper) }
                                .buttonStyle(.plain)
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundStyle(.tint)
                                .help(source.paper.title)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ask about anything you've saved. Answers come only from your papers, with citations.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(askSuggestions, id: \.self) { suggestion in
                    Button(suggestion) { session.ask(suggestion, context: modelContext) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func sendAsk() {
        session.ask(askInput, context: modelContext)
        askInput = ""
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
