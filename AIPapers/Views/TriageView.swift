//
//  TriageView.swift
//  AIPapers
//
//  Clear the unread queue from the keyboard: one paper at a time, most
//  relevant first, no mouse.
//
//    J / →  skip (leave unread)        K / ←  back
//    R      mark read, next            Q      queue for later (To read), next
//    F      favorite                   S      generate summary
//    O      open on arXiv
//
//  The queue is fixed when the page opens so papers don't shuffle under
//  your hands as you mark them.
//

import SwiftUI
import SwiftData

struct TriageView: View {
    @Query(sort: \Paper.relevanceScore, order: .reverse) private var papers: [Paper]
    @EnvironmentObject private var appActivity: AppActivity
    @Environment(\.openURL) private var openURL

    @State private var queueIDs: [String] = []
    @State private var index = 0
    @State private var triaged = 0

    private var current: Paper? {
        queueIDs.indices.contains(index) ? papers.first { $0.id == queueIDs[index] } : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let paper = current {
                card(for: paper)
            } else {
                doneState
            }
            keyHints
        }
        .navigationTitle("Triage")
        .onAppear(perform: rebuildQueue)
        .background(shortcuts)
    }

    /// Plain-key shortcuts rather than focus-based key handling: they fire
    /// wherever the keyboard focus happens to be (unless a text field has it),
    /// so the page works the moment it opens. Zero-size and invisible, but
    /// still real buttons — `.hidden()` would disable the shortcuts.
    private var shortcuts: some View {
        ZStack {
            shortcut("j", .init("j")); shortcut("k", .init("k")); shortcut("r", .init("r"))
            shortcut("q", .init("q")); shortcut("f", .init("f")); shortcut("s", .init("s"))
            shortcut("o", .init("o"))
            Button("") { handle("j") }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { handle("k") }.keyboardShortcut(.leftArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func shortcut(_ key: Character, _ equivalent: KeyEquivalent) -> some View {
        Button("") { handle(key) }.keyboardShortcut(equivalent, modifiers: [])
    }

    // MARK: Card

    private func card(for paper: Paper) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                progress

                Text(paper.title)
                    .font(.system(size: 26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(paper.authors)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    chip("\(Int(paper.relevanceScore * 100))% relevant", tint: true)
                    chip(AnalyticsService.fixedTopic(for: paper))
                    if let sub = paper.subtopic, sub != Taxonomy.otherSubtopic { chip(sub) }
                    chip(paper.publishedAt.formatted(date: .abbreviated, time: .omitted))
                    if paper.isFavorite { chip("★ favorite", tint: true) }
                    if let status = paper.status { chip(status.rawValue, tint: true) }
                }

                if let summary = paper.summary {
                    labelled("Summary", summary, ai: true)
                    if let why = paper.whyItMatters { labelled("Why it matters", why, ai: true) }
                } else if appActivity.summarizingPaperIDs.contains(paper.id) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Generating summary…").foregroundStyle(.secondary)
                    }
                } else {
                    Text("No summary yet — press S to generate one.")
                        .foregroundStyle(.secondary)
                }

                labelled("Abstract", paper.abstractText, ai: false)
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(min(index + 1, queueIDs.count)) of \(queueIDs.count) unread · \(triaged) triaged this session")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(index), total: Double(max(queueIDs.count, 1)))
        }
    }

    private func chip(_ text: String, tint: Bool = false) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
            .foregroundStyle(tint ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }

    private func labelled(_ title: String, _ text: String, ai: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if ai { Rectangle().fill(.tint).frame(width: 3) }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title.uppercased())
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if ai {
                        Spacer()
                        Text("AI")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.tint)
                    }
                }
                Text(text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, ai ? 12 : 0)
        }
    }

    private var doneState: some View {
        ContentUnavailableView(
            queueIDs.isEmpty ? "Nothing unread" : "Inbox zero",
            systemImage: "checkmark.circle",
            description: Text(queueIDs.isEmpty
                ? "Every paper has been opened or triaged."
                : "You triaged \(triaged) papers. New ones will show up after the next refresh.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Keys

    private var keyHints: some View {
        HStack(spacing: 16) {
            hint("J", "skip")
            hint("K", "back")
            hint("R", "read")
            hint("Q", "queue")
            hint("F", "favorite")
            hint("S", "summarize")
            hint("O", "open")
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .frame(minWidth: 20)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func rebuildQueue() {
        queueIDs = papers.filter { !$0.isRead }.map(\.id)
        index = 0
    }

    private func handle(_ key: Character) {
        guard let paper = current else { return }
        switch key {
        case "j": advance()
        case "k": index = max(0, index - 1)
        case "r":
            paper.isRead = true
            triaged += 1
            advance()
        case "q":
            if paper.status == nil { paper.status = .toRead }
            paper.isRead = true
            triaged += 1
            advance()
        case "f": paper.isFavorite.toggle()
        case "s": appActivity.summarize(paper)
        case "o":
            if !NetworkStatus.shared.isOffline, let url = URL(string: paper.url) { openURL(url) }
        default: break
        }
    }

    private func advance() {
        if index < queueIDs.count { index += 1 }
    }
}
