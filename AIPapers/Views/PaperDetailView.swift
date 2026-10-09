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
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appActivity: AppActivity
    var onSelectRelated: (Paper) -> Void = { _ in }

    @State private var relatedPapers: [(paper: Paper, score: Double)] = []
    @ObservedObject private var codeLinks = CodeLinkStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(paper.title)
                    .font(.title.bold())

                Text(paper.authors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                metaRow

                availabilityRow

                Divider()

                workspaceSection

                summarySection

                PaperEngineeringView(paper: paper)

                section("Abstract", text: paper.abstractText)

                relatedSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Pinned, so the primary actions (read the full paper) never scroll out of reach.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
                .padding(.leading, 24)
                .padding(.trailing, 84) // clear of the floating Ask button
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
        }
        .navigationTitle(paper.title)
        .task(id: paper.id) {
            paper.isRead = true
            // Detached so navigating to another paper before this finishes
            // doesn't cancel it — .task(id:) cancellation only applies to
            // work awaited directly in this closure.
            let target = paper
            Task { await updateRelatedPapers(for: target) }
            if CodeLinkStore.shared.needsCheck(target.id), !network.isOffline {
                Task { await PaperService(repository: PaperRepository(context: modelContext)).updateCodeLinks(for: [target]) }
            }
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

    /// Can I actually try this? Code, weights and datasets, via Hugging Face
    /// (which absorbed Papers with Code's links) and the abstract itself.
    @ViewBuilder
    private var availabilityRow: some View {
        let links = codeLinks.links[paper.id]
        HStack(spacing: 8) {
            if let repo = links?.githubRepo, let url = URL(string: repo) {
                Link(destination: url) {
                    Label("Code" + (links?.githubStars.map { " · ★ \($0)" } ?? ""), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
            if let links, links.models > 0, let url = URL(string: "https://huggingface.co/papers/\(paper.id.replacingOccurrences(of: "arXiv:", with: ""))") {
                Link(destination: url) {
                    Label("\(links.models) model\(links.models == 1 ? "" : "s")" + (links.datasets > 0 ? " · \(links.datasets) dataset\(links.datasets == 1 ? "" : "s")" : ""), systemImage: "cube.box")
                }
                .buttonStyle(.bordered)
            }
            if let votes = links?.upvotes, votes > 0 {
                Label("\(votes) on Hugging Face", systemImage: "hand.thumbsup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if links == nil {
                Text("Checking for code…").font(.caption).foregroundStyle(.tertiary)
            } else if links?.hasCode == false && links?.hasWeights == false {
                Label("No public code or weights found yet", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
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

            HStack(spacing: 8) {
                Text("Tried it?")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("Tried it?", selection: Binding(
                    get: { paper.trial },
                    set: { paper.trial = $0 }
                )) {
                    Text("—").tag(TrialOutcome?.none)
                    ForEach(TrialOutcome.allCases) { outcome in
                        Label(outcome.rawValue, systemImage: outcome.systemImage).tag(TrialOutcome?.some(outcome))
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { paper.notes ?? "" },
                    set: { paper.notes = $0.isEmpty ? nil : $0 }
                ))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 90)
                .surfaceCard(radius: 8)
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
                Text(appActivity.summaryErrors[paper.id] ?? "No summary yet.")
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

    /// One primary action with its label; the rest icon-only (with tooltips),
    /// so the bar fits the narrow inspector without truncating.
    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                openWindow(id: "reader", value: ReaderTarget(id: paper.id, title: paper.title))
            } label: {
                Label(PaperPDFService.isDownloaded(paper.id) ? "Read paper" : "Read full paper", systemImage: "doc.richtext")
                    .fixedSize()
            }
            .buttonStyle(.borderedProminent)
            .disabled(network.isOffline && !PaperPDFService.isDownloaded(paper.id))
            .help(network.isOffline && !PaperPDFService.isDownloaded(paper.id)
                  ? "Offline — this paper hasn't been downloaded yet"
                  : "Read the full paper here (saved locally after the first open)")
            Spacer(minLength: 0)
            Group {
                if let url = URL(string: paper.url) {
                    Link(destination: url) {
                        Label("Open on arXiv", systemImage: "arrow.up.right.square")
                    }
                    .disabled(network.isOffline)
                    .help("Open on arXiv")
                }
                Button {
                    ExportService.export([paper])
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export as Markdown (works with Obsidian)")
                Toggle(isOn: $paper.isFavorite) {
                    Label("Favorite", systemImage: paper.isFavorite ? "star.fill" : "star")
                }
                .toggleStyle(.button)
                .help(paper.isFavorite ? "Remove from favorites" : "Favorite")
                Toggle(isOn: $paper.isRead) {
                    Label("Read", systemImage: paper.isRead ? "checkmark.circle.fill" : "circle")
                }
                .toggleStyle(.button)
                .help(paper.isRead ? "Mark as unread" : "Mark as read")
            }
            .labelStyle(.iconOnly)
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
