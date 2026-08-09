//
//  PaperDetailView.swift
//  AIPapers
//
//  Summaries and embeddings are generated on demand — refresh() only ingests
//  metadata, so Ollama is called here, the first time a paper is opened.
//

import SwiftUI
import SwiftData

struct PaperDetailView: View {
    @Bindable var paper: Paper
    @Environment(\.modelContext) private var modelContext
    var onSelectRelated: (Paper) -> Void = { _ in }

    @State private var isSummarizing = false
    @State private var summarizeFailed = false
    @State private var relatedPapers: [(paper: Paper, score: Double)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(paper.title)
                    .font(.title2)
                    .bold()

                Text(paper.authors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label(paper.publishedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    if let category = paper.category {
                        Label(category, systemImage: "tag")
                    }
                    Label("\(Int(paper.relevanceScore * 100))% relevant", systemImage: "gauge.with.needle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                summarySection

                section("Abstract", text: paper.abstractText)

                relatedSection

                HStack {
                    if let url = URL(string: paper.url) {
                        Link(destination: url) {
                            Label("Open on arXiv", systemImage: "arrow.up.right.square")
                        }
                    }
                    Spacer()
                    Toggle(isOn: $paper.isFavorite) {
                        Label("Favorite", systemImage: paper.isFavorite ? "star.fill" : "star")
                    }
                    .toggleStyle(.button)
                    Toggle(isOn: $paper.isRead) {
                        Label("Read", systemImage: paper.isRead ? "checkmark.circle.fill" : "circle")
                    }
                    .toggleStyle(.button)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(paper.title)
        .task(id: paper.id) {
            paper.isRead = true
            // Detached so navigating to another paper before this finishes
            // doesn't cancel it — .task(id:) cancellation only applies to
            // work awaited directly in this closure.
            let target = paper
            Task { await updateRelatedPapers(for: target) }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = paper.summary {
            section("Summary", text: summary)
            if let whyItMatters = paper.whyItMatters {
                section("Why it matters", text: whyItMatters)
            }
        } else if isSummarizing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Generating summary…").foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(summarizeFailed ? "Couldn't generate a summary. Make sure Ollama is running." : "No summary yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Generate Summary") {
                    Task { await generateSummary() }
                }
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Related Papers").font(.headline)
            if relatedPapers.isEmpty {
                Text("None yet — open a few more papers to build up connections between them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(relatedPapers, id: \.paper.id) { related in
                    Button {
                        onSelectRelated(related.paper)
                    } label: {
                        HStack {
                            Text(related.paper.title)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(related.score * 100))%")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
        }
    }

    private func generateSummary() async {
        isSummarizing = true
        summarizeFailed = false
        let service = PaperService(repository: PaperRepository(context: modelContext))
        let success = await service.summarize(paper)
        summarizeFailed = !success
        isSummarizing = false
    }

    private func updateRelatedPapers(for target: Paper) async {
        let service = PaperService(repository: PaperRepository(context: modelContext))
        await service.embedIfNeeded(target)
        let results = (try? service.relatedPapers(to: target)) ?? []
        if target.id == paper.id {
            relatedPapers = results
        }
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text)
                .lineSpacing(3)
        }
    }
}
