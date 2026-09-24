//
//  PaperEngineeringView.swift
//  AIPapers
//
//  The practitioner's half of a paper's detail page: does it fit my stack,
//  what exactly does it claim, and a step-by-step plan to implement it (with
//  progress). Each block generates on request (fit: automatically once a stack
//  is described) and is cached in InsightStore.
//

import SwiftUI

struct PaperEngineeringView: View {
    let paper: Paper
    @ObservedObject private var store = InsightStore.shared
    @AppStorage(AppSettingsKeys.stackProfile) private var stackProfile = ""
    @Environment(\.openSettings) private var openSettings
    @State private var errors: [String: String] = [:]

    private var insights: PaperInsights? { store.insights[paper.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            fitCard
            claimsBlock
            planBlock
        }
        .task(id: paper.id + stackProfile) {
            // The verdict is cheap and the point of the app — judge on open.
            guard !stackProfile.trimmingCharacters(in: .whitespaces).isEmpty,
                  store.currentFit(paper.id) == nil else { return }
            await run("fit") { try await EngineeringService.assessFit(paper) }
        }
    }

    // MARK: Fit

    @ViewBuilder
    private var fitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("For your stack", kind: "fit", redo: store.currentFit(paper.id) != nil) {
                await run("fit") { try await EngineeringService.assessFit(paper) }
            }
            if stackProfile.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack {
                    Text("Describe the system you run and every paper gets a verdict: does it apply, what would change, how much work.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Describe Your Stack…") { openSettings() }
                }
            } else if let fit = store.currentFit(paper.id) {
                HStack(spacing: 8) {
                    Badge(text: fit.verdict.label, color: fit.verdict.color)
                    Badge(text: fit.effort.label, color: .secondary)
                }
                Text(fit.why).lineSpacing(3)
                if !fit.change.isEmpty {
                    Label(fit.change, systemImage: "arrow.turn.down.right")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                status("fit", idle: "Not assessed yet.")
            }
        }
        .padding(14)
        .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.tint.opacity(0.25)))
    }

    // MARK: Claims

    @ViewBuilder
    private var claimsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Claims", kind: "claims", redo: insights?.claims != nil) {
                await run("claims") { try await EngineeringService.extractClaims(paper) }
            }
            if let claims = insights?.claims {
                if claims.isEmpty {
                    Text("No checkable claims in the abstract.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(claims) { claim in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle").foregroundStyle(.tint).font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(claim.text)
                            if let bench = claim.benchmark {
                                Text([bench, claim.metric, claim.value].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text("Numbers are kept only if they appear in the abstract.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                status("claims", idle: "Pull out the headline results to compare them across papers in the Lab.") {
                    Button("Extract Claims") { Task { await run("claims") { try await EngineeringService.extractClaims(paper) } } }
                }
            }
        }
    }

    // MARK: Plan

    @ViewBuilder
    private var planBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Implement this", kind: "plan", redo: insights?.plan != nil) {
                await run("plan") { try await EngineeringService.makePlan(paper) }
            }
            if let plan = insights?.plan {
                let done = insights?.planDone ?? []
                ProgressView(value: Double(done.count), total: Double(plan.steps.count)) {
                    Text("\(done.count) of \(plan.steps.count) steps")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !plan.prerequisites.isEmpty {
                    labelled("You'll need", plan.prerequisites.joined(separator: " · "))
                }
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    Button {
                        store.update(paper.id) {
                            if $0.planDone.contains(index) { $0.planDone.remove(index) } else { $0.planDone.insert(index) }
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: done.contains(index) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(done.contains(index) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .font(.body)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). \(step.title)")
                                    .fontWeight(.semibold)
                                    .strikethrough(done.contains(index), color: .secondary)
                                if !step.detail.isEmpty {
                                    Text(step.detail).font(.callout).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !plan.success.isEmpty { labelled("It worked if", plan.success) }
                if !plan.risks.isEmpty { labelled("Watch out for", plan.risks.joined(separator: " · ")) }
                Text(plan.usedFullText ? "Written from the full paper text." : "Written from the abstract — open the full paper once and rewrite for a more specific plan.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                status("plan", idle: PaperPDFService.isDownloaded(paper.id)
                       ? "A step-by-step plan from the full paper: prerequisites, the smallest experiment first, how to tell it worked."
                       : "A step-by-step plan: prerequisites, the smallest experiment first, how to tell it worked. Open the full paper first for a more specific one.") {
                    Button("Write a Plan") { Task { await run("plan") { try await EngineeringService.makePlan(paper) } } }
                }
            }
        }
    }

    // MARK: Pieces

    private func header(_ title: String, kind: String, redo: Bool, action: @escaping () async -> Void) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text("AI")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(.tint)
            Spacer()
            if store.isWorking(kind, paper.id) {
                ProgressView().controlSize(.small)
            } else if redo {
                Button { Task { await action() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Generate again")
            }
        }
    }

    @ViewBuilder
    private func status(_ kind: String, idle: String, @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        if store.isWorking(kind, paper.id) {
            Text(kind == "plan" ? "Writing the plan… (up to a minute)" : "Thinking…").font(.callout).foregroundStyle(.secondary)
        } else if let error = errors[kind] {
            VStack(alignment: .leading, spacing: 6) {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                action()
            }
        } else {
            HStack(alignment: .top) {
                Text(idle).font(.callout).foregroundStyle(.secondary)
                Spacer()
                action()
            }
        }
    }

    private func labelled(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func run(_ kind: String, _ work: () async throws -> Void) async {
        errors[kind] = nil
        do { try await work() } catch {
            errors[kind] = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

extension StackFit.Verdict {
    var label: String {
        switch self {
        case .applies: "Applies to you"
        case .maybe: "Maybe"
        case .no: "Not for your stack"
        }
    }

    var color: Color {
        switch self {
        case .applies: .green
        case .maybe: .orange
        case .no: .secondary
        }
    }
}

extension StackFit.Effort {
    var label: String {
        switch self {
        case .config: "Config change"
        case .code: "Code change"
        case .retrain: "Retraining"
        case .research: "Research effort"
        }
    }
}
