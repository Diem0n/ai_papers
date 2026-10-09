//
//  LabView.swift
//  AIPapers
//
//  The engineering workbench: which papers apply to your stack, how the
//  claims line up across papers, the implementation plans in progress, what
//  you tried and how it went, and spaced review of what you've learned.
//

import SwiftUI
import SwiftData

private enum LabPane: String, CaseIterable, Identifiable {
    case fit = "Fit"
    case claims = "Claims"
    case plans = "Plans"
    case notebook = "Notebook"
    case review = "Review"
    var id: String { rawValue }
}

struct LabView: View {
    @Query(sort: \Paper.relevanceScore, order: .reverse) private var papers: [Paper]
    @ObservedObject private var insights = InsightStore.shared
    @ObservedObject private var reviews = ReviewStore.shared
    @ObservedObject private var batch = LabBatch.shared
    @AppStorage(AppSettingsKeys.stackProfile) private var stackProfile = ""
    @AppStorage("labPane") private var paneRaw = LabPane.fit.rawValue
    @Environment(\.openSettings) private var openSettings
    @State private var selectedPaper: Paper?

    private var pane: LabPane { LabPane(rawValue: paneRaw) ?? .fit }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Pane", selection: $paneRaw) {
                    ForEach(LabPane.allCases) { pane in
                        Text(pane == .review && !reviews.due.isEmpty ? "Review (\(reviews.due.count))" : pane.rawValue).tag(pane.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)
                Spacer()
                batchStatus
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Divider()
            Group {
                switch pane {
                case .fit: fitPane
                case .claims: claimsPane
                case .plans: plansPane
                case .notebook: notebookPane
                case .review: ReviewPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Lab")
        .paperInspector($selectedPaper)
    }

    @ViewBuilder
    private var batchStatus: some View {
        if let kind = batch.kind {
            HStack(spacing: 8) {
                ProgressView(value: Double(batch.done), total: Double(max(batch.total, 1)))
                    .frame(width: 120)
                Text("\(kind.rawValue) \(batch.done)/\(batch.total)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Stop") { batch.cancel() }.controlSize(.small)
            }
        } else if batch.failures > 0 {
            Text("\(batch.failures) couldn't be processed — is Ollama running?")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Fit

    private var assessed: [(Paper, StackFit)] {
        papers.compactMap { paper in insights.currentFit(paper.id).map { (paper, $0) } }
    }

    @ViewBuilder
    private var fitPane: some View {
        if stackProfile.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView {
                Label("Describe your stack", systemImage: "square.stack.3d.up")
            } description: {
                Text("Tell the Lab what you build and run. Every paper is then judged against it: does it apply, what would change, how much work.")
            } actions: {
                Button("Open Settings") { openSettings() }
            }
        } else {
            let unjudged = papers.filter { !$0.isRead || $0.isFavorite }.filter { insights.currentFit($0.id) == nil }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("\(assessed.count) papers judged against your stack")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Assess \(min(unjudged.count, 25)) More") {
                            batch.run(.fit, over: Array(unjudged.prefix(25)))
                        }
                        .disabled(unjudged.isEmpty || batch.isRunning)
                        .help("Most relevant unread papers first, about 2 seconds each")
                    }
                    ForEach([StackFit.Verdict.applies, .maybe], id: \.self) { verdict in
                        let rows = assessed.filter { $0.1.verdict == verdict }
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle(verdict == .applies ? "Applies to you" : "Maybe", count: rows.count, color: verdict.color)
                            if rows.isEmpty {
                                Text(verdict == .applies ? "Nothing yet — assess more papers." : "None.")
                                    .font(.callout).foregroundStyle(.tertiary)
                            }
                            ForEach(rows, id: \.0.id) { paper, fit in
                                fitRow(paper, fit)
                            }
                        }
                    }
                    let noCount = assessed.filter { $0.1.verdict == .no }.count
                    if noCount > 0 {
                        Text("\(noCount) judged not relevant to your stack.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func fitRow(_ paper: Paper, _ fit: StackFit) -> some View {
        Button { selectedPaper = paper } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(paper.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text(fit.change.isEmpty ? fit.why : fit.change)
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Badge(text: fit.effort.label, color: .secondary)
                    if let links = CodeLinkStore.shared.links[paper.id], links.hasCode {
                        Text("code").font(.system(.caption2, design: .monospaced)).foregroundStyle(.green)
                    }
                }
            }
            .padding(12)
            .background(selectedPaper?.id == paper.id ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8))
                .surfaceCard(radius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Claims

    @ViewBuilder
    private var claimsPane: some View {
        let ledger = EngineeringService.ledger(papers)
        let withClaims = papers.filter { insights.insights[$0.id]?.claims != nil }.count
        let pending = papers.filter { insights.insights[$0.id]?.claims == nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Claims from \(withClaims) papers, lined up by benchmark and metric. Newest first; ↑ marks a result that beat an earlier paper's best.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Extract from \(min(pending.count, 25)) More") {
                        batch.run(.claims, over: Array(pending.prefix(25)))
                    }
                    .disabled(pending.isEmpty || batch.isRunning)
                }
                if ledger.isEmpty {
                    ContentUnavailableView("No comparable results yet", systemImage: "tablecells",
                                           description: Text("Extract claims from more papers. Results show here once two claims share a benchmark and metric, or one has both."))
                }
                ForEach(ledger) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.benchmark).font(.headline).lineLimit(1)
                            Text(group.metric + (group.lowerIsBetter ? " (lower is better)" : ""))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.rows) { row in
                            Button { selectedPaper = row.paper } label: {
                                HStack(spacing: 12) {
                                    Text(row.claim.value ?? "—")
                                        .font(.system(.body, design: .monospaced, weight: row.isBest ? .bold : .regular))
                                        .foregroundStyle(row.isBest ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                        .frame(width: 90, alignment: .trailing)
                                    Image(systemName: row.beatsEarlier != nil ? "arrow.up" : "minus")
                                        .foregroundStyle(row.beatsEarlier != nil ? .green : .secondary.opacity(0.4))
                                        .help(row.beatsEarlier.map { "Beats “\($0.title)”" } ?? "")
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(row.paper.title).lineLimit(1)
                                        Text(row.claim.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(row.paper.publishedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .surfaceCard(radius: 10)
                }
                Text("Values come from each paper's own abstract; papers rarely use identical setups, so treat cross-paper comparisons as leads to check, not a leaderboard.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Plans

    @ViewBuilder
    private var plansPane: some View {
        let withPlans = papers.filter { insights.insights[$0.id]?.plan != nil }
        if withPlans.isEmpty {
            ContentUnavailableView("No implementation plans yet", systemImage: "list.bullet.clipboard",
                                   description: Text("Open a paper and choose “Write a Plan” under Implement this."))
        } else {
            List(withPlans) { paper in
                let plan = insights.insights[paper.id]!.plan!
                let done = insights.insights[paper.id]!.planDone.count
                Button { selectedPaper = paper } label: {
                    HStack(spacing: 14) {
                        Gauge(value: Double(done), in: 0...Double(max(plan.steps.count, 1))) {
                            EmptyView()
                        } currentValueLabel: {
                            Text("\(done)/\(plan.steps.count)").font(.system(.caption2, design: .monospaced))
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(done == plan.steps.count ? .green : .accentColor)
                        .scaleEffect(0.8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(paper.title).font(.headline).lineLimit(2)
                            let next = plan.steps.indices.first { !insights.insights[paper.id]!.planDone.contains($0) }
                            Text(next.map { "Next: \(plan.steps[$0].title)" } ?? "All steps done — record how it went in the notebook.")
                                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let trial = paper.trial { Badge(text: trial.rawValue, color: trial.color) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Notebook

    @ViewBuilder
    private var notebookPane: some View {
        let tried = papers.filter { $0.trial != nil }
        if tried.isEmpty {
            ContentUnavailableView("Your lab notebook is empty", systemImage: "book.closed",
                                   description: Text("Mark “Tried it?” on a paper — want to try, trying, worked, didn't work — and add a note. Over time this is your record of which ideas held up in your system."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        let worked = tried.filter { $0.trial == .worked }.count
                        let failed = tried.filter { $0.trial == .failed }.count
                        Text(worked + failed > 0 ? "\(worked) worked, \(failed) didn't — \(Int(Double(worked) / Double(worked + failed) * 100))% of what you finished trying held up." : "\(tried.count) papers in progress.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Export Notebook…") { ExportService.export(tried) }
                    }
                    ForEach(TrialOutcome.allCases) { outcome in
                        let rows = tried.filter { $0.trial == outcome }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionTitle(outcome.rawValue, count: rows.count, color: outcome.color)
                                ForEach(rows) { paper in
                                    Button { selectedPaper = paper } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(paper.title).font(.headline).lineLimit(1)
                                            Text(paper.notes?.isEmpty == false ? paper.notes! : "No notes yet.")
                                                .font(.callout)
                                                .foregroundStyle(paper.notes?.isEmpty == false ? .secondary : .tertiary)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .surfaceCard(radius: 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title.uppercased())
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .tracking(0.6)
            Text("\(count)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

extension TrialOutcome {
    var color: Color {
        switch self {
        case .planned: .secondary
        case .trying: .orange
        case .worked: .green
        case .failed: .red
        }
    }
}

/// One due card at a time: read the question, recall, reveal, grade yourself.
private struct ReviewPane: View {
    @ObservedObject private var reviews = ReviewStore.shared
    @State private var revealed = false

    var body: some View {
        if let card = reviews.due.first {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(reviews.due.count) due · \(reviews.cards.count) cards · box \(card.box + 1) of \(ReviewStore.intervals.count)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(card.topic.replacingOccurrences(of: "/explain ", with: "").uppercased())
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(card.question)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if revealed {
                    Text(card.answer)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                    HStack {
                        Button("Forgot") { grade(card, false) }
                            .keyboardShortcut("1", modifiers: [])
                        Button("Remembered") { grade(card, true) }
                            .keyboardShortcut("2", modifiers: [])
                            .buttonStyle(.borderedProminent)
                        Spacer()
                        Button("Remove Card", role: .destructive) { reviews.remove(card.id); revealed = false }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Text("1 forgot · 2 remembered — remembered cards come back later each time.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Button("Show Answer") { withAnimation { revealed = true } }
                        .keyboardShortcut(.space, modifiers: [])
                        .buttonStyle(.borderedProminent)
                    Text("Try to answer it in your head first — the effort of recalling is what makes it stick. Space shows the answer.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(40)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let next = reviews.cards.map(\.due).min()
            ContentUnavailableView(
                reviews.cards.isEmpty ? "No review cards yet" : "All caught up",
                systemImage: "rectangle.stack",
                description: Text(reviews.cards.isEmpty
                    ? "Ask “/explain <concept>” and choose “Save for review” — its check question comes back here after 1, 3, 7, 16 and 35 days."
                    : "Next card \(next.map { $0.formatted(.relative(presentation: .named)) } ?? "later").")
            )
        }
    }

    private func grade(_ card: ReviewCard, _ remembered: Bool) {
        reviews.grade(card.id, remembered: remembered)
        revealed = false
    }
}
