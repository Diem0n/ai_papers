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
    @EnvironmentObject private var appActivity: AppActivity
    var onSelectRelated: (Paper) -> Void = { _ in }

    @State private var relatedPapers: [(paper: Paper, score: Double)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(paper.title)
                    .font(.title.bold())
                    .tracking(-0.3)

                Text(paper.authors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label {
                        Text(paper.publishedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(.caption, design: .monospaced))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    if let category = paper.category {
                        Label {
                            Text(category.uppercased())
                                .font(.system(.caption, design: .monospaced))
                        } icon: {
                            Image(systemName: "tag")
                        }
                    }
                    Label {
                        Text("\(Int(paper.relevanceScore * 100))% relevant")
                            .font(.system(.caption, design: .monospaced))
                    } icon: {
                        Image(systemName: "gauge.with.needle")
                    }
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
        } else if appActivity.summarizingPaperIDs.contains(paper.id) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Generating summary…").foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(appActivity.failedSummaryPaperIDs.contains(paper.id) ? "Couldn't generate a summary. Make sure Ollama is running." : "No summary yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Generate Summary") {
                    appActivity.summarize(paper)
                }
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Related Papers")
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
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
        }
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
            sectionHeader(title)
            Text(text)
                .lineSpacing(3)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption, design: .default, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}
