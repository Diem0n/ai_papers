//
//  AskView.swift
//  AIPapers
//
//  Ask a question, get an answer written from your own saved papers, with
//  numbered citations you can open. Retrieval and generation both run on
//  the local Ollama — nothing about the question or the papers leaves the Mac.
//  Conversations aren't persisted; the archive is the memory.
//

import SwiftUI
import SwiftData

private struct AskTurn: Identifiable {
    let id = UUID()
    let question: String
    var answer: String?
    var sources: [(paper: Paper, score: Double)] = []
    var error: String?
    var isWorking = true
}

struct AskView: View {
    @Query private var papers: [Paper]
    @Environment(\.modelContext) private var modelContext

    @State private var turns: [AskTurn] = []
    @State private var input = ""
    @State private var selectedPaper: Paper?
    @State private var inspectorShown = false
    @FocusState private var inputFocused: Bool

    private var suggestions: [String] {
        AnalyticsService.topCategories(papers, limit: 3)
            .map(\.category)
            .filter { $0 != Taxonomy.uncategorized }
            .map { "What's new in \($0)?" }
    }

    private var isBusy: Bool { turns.last?.isWorking == true }

    var body: some View {
        VStack(spacing: 0) {
            if turns.isEmpty {
                emptyState
            } else {
                conversation
            }
            inputBar
        }
        .navigationTitle("Ask your archive")
        .inspector(isPresented: $inspectorShown) {
            Group {
                if let selectedPaper {
                    PaperDetailView(paper: selectedPaper, onSelectRelated: { self.selectedPaper = $0 })
                } else {
                    ContentUnavailableView("Select a paper", systemImage: "doc.text")
                }
            }
            .inspectorColumnWidth(min: 380, ideal: 520, max: 760)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    turns.removeAll()
                } label: {
                    Label("Clear Conversation", systemImage: "trash")
                }
                .disabled(turns.isEmpty || isBusy)
            }
        }
        .onAppear { inputFocused = true }
    }

    // MARK: Pieces

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Ask your archive")
                .font(.title2.bold())
            Text("Answers come only from the \(papers.count) papers you've saved, with citations. Runs entirely on your Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { ask(suggestion) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(turns) { turn in
                        turnView(turn).id(turn.id)
                    }
                }
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: turns.count) {
                if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: turns.last?.answer) {
                if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private func turnView(_ turn: AskTurn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(turn.question)
                .font(.headline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            if turn.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching your papers and writing an answer…")
                        .foregroundStyle(.secondary)
                }
            } else if let error = turn.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else if let answer = turn.answer {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle().fill(.tint).frame(width: 3)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ANSWER")
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("AI")
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundStyle(.tint)
                        }
                        Text(answer)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 12)
                }

                if !turn.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SOURCES")
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(turn.sources.enumerated()), id: \.element.paper.id) { index, source in
                            Button {
                                selectedPaper = source.paper
                                inspectorShown = true
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("[\(index + 1)]")
                                        .font(.system(.callout, design: .monospaced, weight: .bold))
                                        .foregroundStyle(.tint)
                                    Text(source.paper.title)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    Text("\(Int(source.score * 100))%")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
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
        HStack(spacing: 10) {
            TextField("Ask about your papers…", text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit { ask(input) }
                .disabled(isBusy)
            Button {
                ask(input)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(isBusy || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
        .background(.bar)
    }

    // MARK: Asking

    private func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        input = ""
        turns.append(AskTurn(question: trimmed))
        let id = turns[turns.count - 1].id

        Task {
            let service = PaperService(repository: PaperRepository(context: modelContext))
            var finished: AskTurn?
            do {
                let result = try await service.ask(trimmed)
                finished = AskTurn(question: trimmed, answer: result.answer, sources: result.sources, error: nil, isWorking: false)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Couldn't answer that."
                finished = AskTurn(question: trimmed, answer: nil, sources: [], error: message, isWorking: false)
            }
            if let finished, let position = turns.firstIndex(where: { $0.id == id }) {
                turns[position].answer = finished.answer
                turns[position].sources = finished.sources
                turns[position].error = finished.error
                turns[position].isWorking = false
            }
            inputFocused = true
        }
    }
}
