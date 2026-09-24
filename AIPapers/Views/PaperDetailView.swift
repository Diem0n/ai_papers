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
    @ObservedObject private var network = NetworkStatus.shared
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

                Text(paper.authors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                metaRow

                Divider()

                workspaceSection

                summarySection

                section("Abstract", text: paper.abstractText)

                relatedSection

                actionBar
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

    private var metaRow: some View {
        HStack(spacing: 16) {
            Label(paper.publishedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            Label("Pulled \(paper.discoveredAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "tray.and.arrow.down")
            Label(AnalyticsService.fixedTopic(for: paper).uppercased(), systemImage: "tag")
            Label("\(Int(paper.relevanceScore * 100))% relevant", systemImage: "gauge.with.needle")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    /// The reader's own layer: where this paper is in their queue, and what they thought.
    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Your reading")
            Picker("Status", selection: Binding(
                get: { paper.status },
                set: { paper.status = $0 }
            )) {
                Text("None").tag(ReadingStatus?.none)
                ForEach(ReadingStatus.allCases) { status in
                    Label(status.rawValue, systemImage: status.systemImage).tag(ReadingStatus?.some(status))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { paper.notes ?? "" },
                    set: { paper.notes = $0.isEmpty ? nil : $0 }
                ))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 90)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                if (paper.notes ?? "").isEmpty {
                    Text("Notes — what's worth remembering, what to try…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = paper.summary {
            callout(title: "Summary", text: summary)
            if let whyItMatters = paper.whyItMatters {
                callout(title: "Why it matters", text: whyItMatters)
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

    /// A left-accent callout, like a technical doc's admonition block —
    /// distinguishes model-generated interpretation from the paper's own
    /// text without dressing it up as something it isn't.
    private func callout(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(.tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    sectionHeader(title)
                    Spacer()
                    Text("AI")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.tint)
                }
                Text(text)
                    .lineSpacing(3)
            }
            .padding(.leading, 12)
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                                .foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if let url = URL(string: paper.url) {
                Link(destination: url) {
                    Label("Open on arXiv", systemImage: "arrow.up.right.square")
                }
                .disabled(network.isOffline)
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
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}
