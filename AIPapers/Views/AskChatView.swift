//
//  AskChatView.swift
//  AIPapers
//
//  The full Ask conversation, shown in the floating panel that opens from
//  the eye button on every page but the dashboard. Answers are written from
//  the local archive only, with numbered citations; retrieval and generation
//  both run on the local Ollama.
//

import SwiftUI
import SwiftData

struct AskChatView: View {
    @EnvironmentObject private var session: AskSession
    @Environment(\.modelContext) private var modelContext
    @Query private var papers: [Paper]

    let onOpenPaper: (Paper) -> Void

    @State private var input = ""
    @State private var blink = 0
    /// Picked once per panel so the suggestion doesn't change on every redraw.
    @State private var explainSuggestion = Taxonomy.all.flatMap(\.subtopics).map(\.name).filter { $0 != Taxonomy.otherSubtopic }.randomElement() ?? "attention"
    @FocusState private var inputFocused: Bool

    private var suggestions: [String] {
        AnalyticsService.topCategories(papers, limit: 3)
            .map(\.category)
            .filter { $0 != Taxonomy.uncategorized }
            .map { "What's new in \($0)?" }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if session.turns.isEmpty {
                emptyState
            } else {
                conversation
            }
            Divider()
            inputBar
        }
        .frame(width: 460, height: 600)
        .onAppear {
            inputFocused = true
            blink += 1
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PixelEyeLogo(size: 24, blinkTrigger: blink)
            Text("Ask your archive")
                .font(.headline)
            Spacer()
            Button {
                session.clear()
            } label: {
                Label("Clear", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(session.turns.isEmpty || session.isBusy)
            .help("Clear conversation")
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("Answers come only from the \(papers.count) papers you've saved, with citations. It all runs on your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Text("Learning something new? Type /explain and a concept.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("/explain \(explainSuggestion)") { send("/explain \(explainSuggestion)") }
                .buttonStyle(.bordered)
            ForEach(suggestions, id: \.self) { suggestion in
                Button(suggestion) { send(suggestion) }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(session.turns) { turn in
                        turnView(turn).id(turn.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: session.turns.count) { scrollToEnd(proxy) }
            .onChange(of: session.turns.last?.isWorking) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = session.turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
    }

    private func turnView(_ turn: AskSession.Turn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(turn.question)
                .font(.callout.weight(.semibold))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            if turn.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(turn.isExplain ? "Writing an explanation…" : "Searching your papers…").foregroundStyle(.secondary)
                }
            } else if let error = turn.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else if let answer = turn.answer {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle().fill(.tint).frame(width: 3)
                    Text(turn.isExplain ? AskSession.formatted(answer) : AttributedString(answer))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                }
                if let hidden = turn.hiddenAnswer {
                    DisclosureGroup("Show the answer") {
                        Text(AskSession.formatted(hidden))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .font(.callout)
                }
                if !turn.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(turn.sources.enumerated()), id: \.element.paper.id) { index, source in
                            Button { onOpenPaper(source.paper) } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("[\(index + 1)]")
                                        .font(.system(.caption, design: .monospaced, weight: .bold))
                                        .foregroundStyle(.tint)
                                    Text(source.paper.title)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about your papers, or /explain a concept…", text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit { send(input) }
                .disabled(session.isBusy)
            Button { send(input) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(session.isBusy || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    private func send(_ question: String) {
        session.ask(question, context: modelContext)
        input = ""
    }
}
