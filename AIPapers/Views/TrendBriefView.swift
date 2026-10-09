//
//  TrendBriefView.swift
//  AIPapers
//
//  The weekly digest, built to be scanned rather than read:
//
//    1. Bottom line up front — one sentence, then the action ("read these 3").
//       People remember the first and last things they read, so the two most
//       useful things go first.
//    2. Chunked themes: every theme card has the identical shape (headline,
//       takeaway, "so what", evidence), so after one card the rest read at a glance.
//    3. Numbers are drawn, not just written: momentum arrows, size bars, a
//       weighted chip cloud of rising terms.
//    4. Progressive disclosure: extra papers and the full long-form narrative
//       stay collapsed until asked for.
//
//  Themes, keywords and momentum are computed instantly and locally
//  (DigestService); only the short prose is model-written, and cached.
//

import SwiftUI
import SwiftData

struct TrendBriefView: View {
    @Query private var papers: [Paper]
    @EnvironmentObject private var appActivity: AppActivity

    @State private var digest: Digest?
    @State private var narrative: DigestNarrative?
    @State private var isWriting = false
    @State private var writeError: String?
    @State private var fullBrief: TrendBrief?
    @State private var expandedThemes: Set<Int> = []
    @State private var selectedPaper: Paper?
    @State private var inspectorShown = false

    var body: some View {
        Group {
            if let digest {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header(digest)
                        bottomLine(digest)
                        readFirst(digest)
                        themesSection(digest)
                        risingTermsSection(digest)
                        wildcardsSection(digest)
                        fullNarrativeSection
                    }
                    .padding(28)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView(
                    "Not enough to digest yet",
                    systemImage: "text.book.closed",
                    description: Text("The digest needs a batch of papers with embeddings — refresh to pull some.")
                )
            }
        }
        .navigationTitle("Weekly Digest")
        .inspector(isPresented: $inspectorShown) {
            inspectorContent.inspectorColumnWidth(min: 380, ideal: 520, max: 760)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    inspectorShown.toggle()
                } label: {
                    Label("Paper Detail", systemImage: "sidebar.trailing")
                }
                .disabled(selectedPaper == nil)
            }
            ToolbarItem {
                Button {
                    if let digest { Task { await writeNarrative(for: digest, force: true) } }
                } label: {
                    Label("Rewrite Summaries", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(digest == nil || isWriting)
                .help("Ask the model to write the digest text again")
            }
        }
        .task(id: papers.count) {
            digest = DigestService.build(papers)
            fullBrief = TrendBriefStore.loadLatest()
        }
        .task(id: digest?.signature) {
            guard let digest else { return }
            await writeNarrative(for: digest, force: false)
        }
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

    // MARK: Sections

    private func header(_ digest: Digest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly Digest")
                .font(.largeTitle.bold())
            Text("\(dateRange(digest)) · \(digest.paperCount) new papers · ≈ \(readMinutes) min read")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func dateRange(_ digest: Digest) -> String {
        let start = digest.windowStart.formatted(.dateTime.day().month())
        let end = digest.windowEnd.formatted(.dateTime.day().month())
        return start == end ? start : "\(start) – \(end)"
    }

    /// Roughly how long the visible prose takes at 200 words a minute.
    private var readMinutes: Int {
        guard let narrative else { return 1 }
        let text = ([narrative.tldr] + narrative.themes.flatMap { [$0.headline, $0.takeaway, $0.soWhat] }).joined(separator: " ")
        return max(1, Int((Double(text.split(separator: " ").count) / 200).rounded(.up)))
    }

    private func bottomLine(_ digest: Digest) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(.tint).frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("The bottom line")
                if let narrative {
                    Text(narrative.tldr)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(fallbackBottomLine(digest))
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if isWriting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Writing plain-language summaries…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else if let writeError {
                        Text(writeError)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, 16)
        }
    }

    /// What's shown before (or without) the model: the same shape, from the numbers alone.
    private func fallbackBottomLine(_ digest: Digest) -> String {
        guard let lead = digest.themes.first else { return "\(digest.paperCount) new papers this week." }
        return "\(digest.paperCount) new papers fall into \(digest.themes.count) themes, led by \(lead.label) (\(lead.papers.count) papers)."
    }

    private func readFirst(_ digest: Digest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Read these first")
            ForEach(Array(digest.readingPlan.enumerated()), id: \.element.id) { index, paper in
                Button { open(paper) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .foregroundStyle(.tint)
                            .frame(width: 22)
                        paperLine(paper)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func themesSection(_ digest: Digest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("This week's themes")
            let largest = digest.themes.map { $0.papers.count }.max() ?? 1
            ForEach(digest.themes) { theme in
                themeCard(theme, largest: largest)
            }
        }
    }

    private func themeCard(_ theme: DigestTheme, largest: Int) -> some View {
        let text = narrative?.themes.first { $0.index == theme.id }
        let momentum = momentum(for: theme)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(theme.topic.uppercased())
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
                if let momentum {
                    Label(momentum.text, systemImage: momentum.icon)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(momentum.color)
                }
                Spacer()
                HStack(spacing: 6) {
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(6, 54 * CGFloat(theme.papers.count) / CGFloat(largest)), height: 6)
                    Text("\(theme.papers.count) papers")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Text(text?.headline ?? theme.label)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let text {
                Text(text.takeaway)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.tint)
                    Text(text.soWhat)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !theme.keywords.isEmpty {
                HStack(spacing: 6) {
                    ForEach(theme.keywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("START WITH")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
                Button { open(theme.representative) } label: {
                    paperLine(theme.representative).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if theme.papers.count > 1 {
                DisclosureGroup(isExpanded: expansion(for: theme.id)) {
                    VStack(spacing: 0) {
                        ForEach(theme.papers.dropFirst(), id: \.id) { paper in
                            Divider()
                            Button { open(paper) } label: {
                                paperLine(paper)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } label: {
                    Text("\(theme.papers.count - 1) more in this theme")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func risingTermsSection(_ digest: Digest) -> some View {
        Group {
            if !digest.risingTerms.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Rising terms")
                    Text("Phrases showing up far more often than in earlier papers — bigger means a bigger jump.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
                        let top = digest.risingTerms.first?.lift ?? 1
                        ForEach(digest.risingTerms) { term in
                            HStack(spacing: 6) {
                                Text(term.term)
                                    .font(.system(size: 11 + 6 * term.lift / top, weight: .medium, design: .monospaced))
                                Text("\(term.recentCount)×")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.tint.opacity(0.10 + 0.15 * term.lift / top), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func wildcardsSection(_ digest: Digest) -> some View {
        Group {
            if !digest.wildcards.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Off the beaten path")
                    Text("Papers unlike anything else this week — the odd ones out.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(digest.wildcards, id: \.id) { paper in
                        Button { open(paper) } label: {
                            paperLine(paper)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var fullNarrativeSection: some View {
        Group {
            if let fullBrief {
                DisclosureGroup {
                    Text(fullBrief.content)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                } label: {
                    Text("Full narrative · \(fullBrief.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Pieces

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private func paperLine(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(paper.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                Text("\(Int(paper.relevanceScore * 100))%").foregroundStyle(.tint)
                Text("·")
                Text(AnalyticsService.fixedTopic(for: paper))
                if !paper.isRead {
                    Text("·")
                    Text("unread")
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    /// Nil until there's an earlier week to compare against — a badge that
    /// says "new" on every card carries no information.
    private func momentum(for theme: DigestTheme) -> (text: String, icon: String, color: Color)? {
        guard let prior = theme.priorCount else { return nil }
        let delta = theme.papers.count - prior
        if delta > 0 { return ("+\(delta) vs. last week", "arrow.up.right", .green) }
        if delta < 0 { return ("\(delta) vs. last week", "arrow.down.right", .red) }
        return ("steady", "arrow.right", .secondary)
    }

    private func expansion(for id: Int) -> Binding<Bool> {
        Binding(
            get: { expandedThemes.contains(id) },
            set: { isOpen in
                if isOpen { expandedThemes.insert(id) } else { expandedThemes.remove(id) }
            }
        )
    }

    // MARK: Writing

    private func synopsis(_ paper: Paper) -> String {
        (paper.summary ?? String(paper.abstractText.prefix(240)))
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func writeNarrative(for digest: Digest, force: Bool) async {
        if !force, let cached = DigestStore.load(), cached.signature == digest.signature {
            narrative = cached
            return
        }
        isWriting = true
        writeError = nil
        defer { isWriting = false }

        let themes = digest.themes.map { theme in
            DigestPromptTheme(
                index: theme.id,
                label: theme.label,
                keywords: theme.keywords,
                papers: theme.papers.prefix(4).map { "\($0.title) — \(synopsis($0))" }
            )
        }
        do {
            let result = try await OllamaService().synthesizeDigest(themes: themes)
            let written = DigestNarrative(
                signature: digest.signature,
                model: AppSettings.ollamaModel,
                generatedAt: .now,
                tldr: result.tldr,
                themes: result.themes.map { .init(index: $0.index, headline: $0.headline, takeaway: $0.takeaway, soWhat: $0.soWhat) }
            )
            DigestStore.save(written)
            narrative = written
        } catch {
            writeError = (error as? LocalizedError)?.errorDescription ?? "Couldn't write the summaries — showing the numbers only."
        }
    }
}

private extension View {
    func card() -> some View {
        surfaceCard()
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }
}
