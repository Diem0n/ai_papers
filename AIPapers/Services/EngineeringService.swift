//
//  EngineeringService.swift
//  AIPapers
//
//  The practitioner's questions about a paper, answered by the local model and
//  validated before anything is stored:
//
//    fit    — does it apply to *my* stack, what would change, how much effort
//    claims — the headline results; a number is kept only if it literally
//             appears in the abstract, so the ledger never carries an invented one
//    plan   — prerequisites, ordered steps, how to know it worked, risks;
//             uses the full paper text when the PDF has been downloaded
//
//  Also the deterministic ledger logic: which later result beats an earlier
//  one on the same benchmark and metric.
//

import Foundation
import PDFKit

enum EngineeringError: LocalizedError {
    case noStack
    case unusable

    var errorDescription: String? {
        switch self {
        case .noStack: "Describe your stack in Settings first — the verdict is about your system."
        case .unusable: "The model's answer didn't hold up to validation. Try again, or pick a bigger model in Settings."
        }
    }
}

@MainActor
enum EngineeringService {
    private static var ollama: OllamaService { OllamaService(model: AppSettings.askModel) }

    static func stackSignature(_ stack: String = AppSettings.stackProfile) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in stack.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }

    /// Small models occasionally emit broken JSON. Ask again once (the second
    /// sample is usually fine) before giving up with `.unusable`.
    private static func generateValidated<T>(
        prompt: String, contextTokens: Int? = nil, feature: CloudFeature, parse: (String) -> T?
    ) async throws -> T {
        for attempt in 1...2 {
            let raw = try await ollama.generate(prompt: prompt, contextTokens: contextTokens, feature: feature)
            if let value = parse(raw) { return value }
            if attempt == 2 { break }
        }
        throw EngineeringError.unusable
    }

    // MARK: Fit

    static func assessFit(_ paper: Paper) async throws {
        let stack = AppSettings.stackProfile
        guard !stack.isEmpty else { throw EngineeringError.noStack }
        let store = InsightStore.shared
        let key = "fit:\(paper.id)"
        guard !store.working.contains(key) else { return }
        store.setWorking(key, true)
        defer { store.setWorking(key, false) }

        let signature = stackSignature(stack)
        let fit = try await generateValidated(prompt: fitPrompt(stack: stack, title: paper.title, abstract: paper.abstractText), feature: .stackFit) {
            parseFit($0, signature: signature)
        }
        store.update(paper.id) { $0.fit = fit }
    }

    nonisolated static func parseFit(_ raw: String, signature: String) -> StackFit? {
        struct R: Decodable { let verdict: String?; let why: String?; let change: String?; let effort: String? }
        guard let data = jsonData(raw), let r = try? JSONDecoder().decode(R.self, from: data),
              let verdict = r.verdict.flatMap({ StackFit.Verdict(rawValue: $0.lowercased().trimmingCharacters(in: .whitespaces)) }),
              let why = clean(r.why), !why.isEmpty else { return nil }
        let effort = r.effort.flatMap { StackFit.Effort(rawValue: $0.lowercased().trimmingCharacters(in: .whitespaces)) } ?? .code
        return StackFit(verdict: verdict, why: why, change: clean(r.change) ?? "", effort: effort, stackSignature: signature, generatedAt: .now)
    }

    private static func fitPrompt(stack: String, title: String, abstract: String) -> String {
        """
        You advise a practicing AI engineer on whether a research paper is relevant to the
        system they run. Their system, in their own words:
        \(stack)

        Paper title: \(title)
        Abstract: \(abstract)

        Decide from the abstract only. Be strict: "applies" means it addresses a component or
        constraint their system actually has; "maybe" means it's adjacent or needs a change
        they haven't described; "no" otherwise. Don't invent details the abstract doesn't give.

        Respond with ONLY a JSON object:
        {"verdict": "applies" | "maybe" | "no",
         "why": "<one sentence tying the paper to a specific part of their system, or saying why not>",
         "change": "<what they would concretely change or try, one sentence; empty if verdict is no>",
         "effort": "config" | "code" | "retrain" | "research"}
        effort: config = settings/flags of existing tools; code = new code in their pipeline;
        retrain = training or fine-tuning a model; research = no usable implementation, would need reproducing.
        """
    }

    // MARK: Claims

    static func extractClaims(_ paper: Paper) async throws {
        let store = InsightStore.shared
        let key = "claims:\(paper.id)"
        guard !store.working.contains(key) else { return }
        store.setWorking(key, true)
        defer { store.setWorking(key, false) }

        let claims = try await generateValidated(prompt: claimsPrompt(title: paper.title, abstract: paper.abstractText), feature: .claims) {
            parseClaims($0, abstract: paper.abstractText)
        }
        store.update(paper.id) { $0.claims = claims }
    }

    /// Keeps a claim only if every number it states appears in the abstract.
    nonisolated static func parseClaims(_ raw: String, abstract: String) -> [PaperClaim]? {
        struct Item: Decodable { let claim: String?; let benchmark: String?; let metric: String?; let value: String?; let baseline: String? }
        struct R: Decodable { let claims: [Item]? }
        guard let data = jsonData(raw), let r = try? JSONDecoder().decode(R.self, from: data) else { return nil }
        let source = numbers(in: abstract)
        let kept = (r.claims ?? []).compactMap { item -> PaperClaim? in
            guard let text = clean(item.claim), !text.isEmpty else { return nil }
            let stated = numbers(in: [text, item.value ?? "", item.baseline ?? ""].joined(separator: " "))
            guard stated.isSubset(of: source) else { return nil }
            return PaperClaim(text: text, benchmark: clean(item.benchmark), metric: clean(item.metric),
                              value: clean(item.value), baseline: clean(item.baseline))
        }
        return Array(kept.prefix(5))
    }

    /// Numbers as written ("66.2", "3", "1,024" → "1024"), ignoring a trailing % or x.
    nonisolated static func numbers(in text: String) -> Set<String> {
        let pattern = #"\d+(?:[.,]\d+)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]).replacingOccurrences(of: ",", with: "") }
        })
    }

    private static func claimsPrompt(title: String, abstract: String) -> String {
        """
        Extract the headline empirical claims from this paper's abstract, for a table that
        compares results across papers.

        Title: \(title)
        Abstract: \(abstract)

        Rules:
        - Only claims stated in the abstract. Copy numbers exactly as written; never compute,
          round or invent one. If the abstract gives no numbers, return qualitative claims
          with value null.
        - At most 5 claims, most important first.
        - Plain text only: no LaTeX or markdown.

        Respond with ONLY a JSON object:
        {"claims": [{"claim": "<one sentence>", "benchmark": "<dataset/benchmark name or null>",
                     "metric": "<metric name or null>", "value": "<the paper's number as written or null>",
                     "baseline": "<what it is compared against, or null>"}]}
        """
    }

    // MARK: Plan

    static func makePlan(_ paper: Paper) async throws {
        let store = InsightStore.shared
        let key = "plan:\(paper.id)"
        guard !store.working.contains(key) else { return }
        store.setWorking(key, true)
        defer { store.setWorking(key, false) }

        let fullText = fullText(of: paper)
        let links = CodeLinkStore.shared.links[paper.id]
        let stack = AppSettings.stackProfile
        let plan = try await generateValidated(
            prompt: planPrompt(paper: paper, fullText: fullText, repo: links?.githubRepo, stack: stack),
            contextTokens: fullText == nil ? nil : 12_288,
            feature: planFeature(stackIsEmpty: stack.isEmpty)
        ) { parsePlan($0, usedFullText: fullText != nil) }
        store.update(paper.id) {
            $0.plan = plan
            $0.planDone = []
        }
    }

    nonisolated static func parsePlan(_ raw: String, usedFullText: Bool) -> ImplementationPlan? {
        struct Step: Decodable { let title: String?; let detail: String? }
        struct R: Decodable { let prerequisites: [String]?; let steps: [Step]?; let success: String?; let risks: [String]? }
        guard let data = jsonData(raw), let r = try? JSONDecoder().decode(R.self, from: data) else { return nil }
        let steps = (r.steps ?? []).compactMap { step -> ImplementationPlan.Step? in
            guard let title = clean(step.title), !title.isEmpty else { return nil }
            return .init(title: title, detail: clean(step.detail) ?? "")
        }
        guard steps.count >= 2 else { return nil }
        return ImplementationPlan(
            prerequisites: (r.prerequisites ?? []).compactMap(clean).filter { !$0.isEmpty }.prefix(6).map { $0 },
            steps: Array(steps.prefix(10)),
            success: clean(r.success) ?? "",
            risks: (r.risks ?? []).compactMap(clean).filter { !$0.isEmpty }.prefix(4).map { $0 },
            usedFullText: usedFullText,
            generatedAt: .now
        )
    }

    /// The downloaded PDF's text up to the references, capped to fit the context window.
    static func fullText(of paper: Paper, limit: Int = 24_000) -> String? {
        guard PaperPDFService.isDownloaded(paper.id),
              let text = PDFDocument(url: PaperPDFService.localURL(for: paper.id))?.string, text.count > 1_000 else { return nil }
        var body = text
        if let references = body.range(of: "\nReferences\n", options: .backwards) ?? body.range(of: "\nREFERENCES\n", options: .backwards) {
            body = String(body[..<references.lowerBound])
        }
        return String(body.prefix(limit))
    }

    /// The prompt carries the reader's stack description when there is one —
    /// that makes the call as sensitive as stack fit, not plain paper content,
    /// so it needs the stronger tier before it's allowed to reach the cloud.
    nonisolated static func planFeature(stackIsEmpty: Bool) -> CloudFeature {
        stackIsEmpty ? .plan : .stackFit
    }

    private static func planPrompt(paper: Paper, fullText: String?, repo: String?, stack: String) -> String {
        let source = fullText.map { "Full paper text (may be cut off):\n\($0)" } ?? "Abstract: \(paper.abstractText)"
        let stackLine = stack.isEmpty ? "" : "\nThe engineer's system, in their words: \(stack)\nTailor the steps to it.\n"
        let repoLine = repo.map { "\nThe authors' code: \($0) — start from it where it makes sense.\n" } ?? "\nNo public code is known; the steps must work from the paper.\n"
        return """
        Write a practical plan for an AI engineer to implement and evaluate the method in this
        paper, in order, so they can decide within a day or two whether it's worth adopting.

        Title: \(paper.title)
        \(source)
        \(stackLine)\(repoLine)
        Rules:
        - Only use details the paper gives. Where the paper doesn't specify something (a
          hyperparameter, a dataset split), say "not specified in the paper — choose and record it".
        - Start with the smallest experiment that would show whether it works; scale later.
        - 4 to 8 steps, each an action someone can do and tick off.
        - Plain text only: no LaTeX, no markdown. Write math inline in words or ASCII (V = W_v x).

        Respond with ONLY a JSON object:
        {"prerequisites": ["<data, hardware, library or skill needed>"],
         "steps": [{"title": "<imperative, under 10 words>", "detail": "<1-3 sentences: exactly what to do>"}],
         "success": "<the measurement that tells them it worked, and against what baseline>",
         "risks": ["<a likely way this goes wrong in practice>"]}
        """
    }

    // MARK: Ledger

    struct LedgerRow: Identifiable {
        let paper: Paper
        let claim: PaperClaim
        let numeric: Double?
        /// This result beats the best earlier one on the same benchmark and metric.
        var beatsEarlier: Paper?
        var isBest = false
        var id: String { paper.id + claim.id }
    }

    struct LedgerGroup: Identifiable {
        let benchmark: String
        let metric: String
        let lowerIsBetter: Bool
        var rows: [LedgerRow]
        var id: String { benchmark + "|" + metric }
    }

    nonisolated static func lowerIsBetter(_ metric: String) -> Bool {
        let m = metric.lowercased()
        return ["error", "loss", "latency", "perplexity", "mae", "mse", "rmse", "wer", "cer", "time", "memory", "cost", "ppl", "fid"].contains { m.contains($0) }
    }

    /// Claims with a benchmark, metric and number, grouped so results line up
    /// across papers; each row knows whether it beat what came before.
    static func ledger(_ papers: [Paper]) -> [LedgerGroup] {
        let store = InsightStore.shared
        var groups: [String: LedgerGroup] = [:]
        for paper in papers {
            for claim in store.insights[paper.id]?.claims ?? [] {
                guard let bench = claim.benchmark, let metric = claim.metric, claim.value.flatMap(firstNumber) != nil else { continue }
                let key = bench.lowercased() + "|" + metric.lowercased()
                let row = LedgerRow(paper: paper, claim: claim, numeric: claim.value.flatMap(firstNumber))
                // One row per paper per value — the model often restates a result.
                if groups[key]?.rows.contains(where: { $0.paper.id == paper.id && $0.numeric == row.numeric }) == true { continue }
                if groups[key] == nil { groups[key] = LedgerGroup(benchmark: bench, metric: metric, lowerIsBetter: lowerIsBetter(metric), rows: []) }
                groups[key]?.rows.append(row)
            }
        }
        return groups.values.map { group in
            var g = group
            g.rows.sort { $0.paper.publishedAt < $1.paper.publishedAt }
            var best: LedgerRow?
            for i in g.rows.indices {
                guard let value = g.rows[i].numeric else { continue }
                // Only a *different, earlier* paper counts as beaten — not the paper's own baseline.
                if let current = best, let bestValue = current.numeric, current.paper.id != g.rows[i].paper.id,
                   g.lowerIsBetter ? value < bestValue : value > bestValue {
                    g.rows[i].beatsEarlier = current.paper
                }
                if best?.numeric == nil || (g.lowerIsBetter ? value < best!.numeric! : value > best!.numeric!) { best = g.rows[i] }
            }
            if let best, let index = g.rows.firstIndex(where: { $0.id == best.id }) { g.rows[index].isBest = true }
            g.rows.reverse() // newest first for reading
            return g
        }
        // Benchmarks that several papers report are the interesting ones.
        .sorted {
            let a = Set($0.rows.map(\.paper.id)).count, b = Set($1.rows.map(\.paper.id)).count
            return a != b ? a > b : $0.benchmark < $1.benchmark
        }
    }

    /// The first number in reading order ("66.2%" → 66.2).
    nonisolated static func firstNumber(_ text: String) -> Double? {
        guard let r = text.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(text[r])
    }

    /// Small models write LaTeX inside JSON strings with single backslashes, so
    /// "\\times" decodes as a tab + "imes" and "\\frac" as a form feed. Escape
    /// backslashes that start a LaTeX command before decoding.
    nonisolated static func jsonData(_ raw: String) -> Data? {
        let commands = "times|frac|text|textbf|mathbf|mathrm|beta|theta|tau|rho|right|left|rightarrow|leftarrow|sum|sqrt|cdot|alpha|lambda|sigma|nabla|neq|infty|approx|leq|geq|forall|epsilon|delta|mu|hat|bar|log|exp|max|min|in|odot|otimes|top|partial|prod|int|mid|ldots|dots|quad"
        let fixed = raw.replacingOccurrences(of: #"(?<!\\)\\(?=(\#(commands))\b)"#, with: #"\\\\"#, options: .regularExpression)
        return fixed.data(using: .utf8)
    }

    /// Trims, drops "null", and undoes LaTeX that slipped into JSON (where "\\times"
    /// arrives as a tab plus "imes"): math delimiters and control characters go.
    nonisolated private static func clean(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" })
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.lowercased() == "null" ? nil : String(t.prefix(400))
    }
}
