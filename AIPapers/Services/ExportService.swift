//
//  ExportService.swift
//  AIPapers
//
//  Papers out as Markdown files — one per paper, with YAML front matter, so a
//  folder of them drops straight into Obsidian (or any notes app). Canonical
//  metadata comes from the paper record; model-written sections are labelled.
//

import Foundation
import AppKit

@MainActor
enum ExportService {
    static func markdown(for paper: Paper) -> String {
        let insights = InsightStore.shared.insights[paper.id]
        let links = CodeLinkStore.shared.links[paper.id]
        let arxivID = paper.id.replacingOccurrences(of: "arXiv:", with: "")
        var lines: [String] = [
            "---",
            "title: \"\(paper.title.replacingOccurrences(of: "\"", with: "'"))\"",
            "arxiv: \(arxivID)",
            "url: \(paper.url)",
            "authors: \"\(paper.authors.replacingOccurrences(of: "\"", with: "'"))\"",
            "published: \(paper.publishedAt.formatted(.iso8601.year().month().day()))",
            "topic: \(AnalyticsService.fixedTopic(for: paper))",
        ]
        if let sub = paper.subtopic { lines.append("subtopic: \(sub)") }
        if let status = paper.status { lines.append("status: \(status.rawValue)") }
        if let trial = paper.trial { lines.append("tried: \(trial.rawValue)") }
        if let repo = links?.githubRepo { lines.append("code: \(repo)") }
        lines.append("tags: [aipapers\(paper.isFavorite ? ", favorite" : "")]")
        lines += ["---", "", "# \(paper.title)", "", "\(paper.authors)", ""]

        if let notes = paper.notes, !notes.isEmpty { lines += ["## My notes", "", notes, ""] }
        if let summary = paper.summary { lines += ["## Summary (AI)", "", summary, ""] }
        if let why = paper.whyItMatters { lines += ["## Why it matters (AI)", "", why, ""] }
        if let fit = insights?.fit {
            lines += ["## For my stack (AI)", "", "**\(fit.verdict.rawValue.capitalized)** · effort: \(fit.effort.rawValue)", "", fit.why]
            if !fit.change.isEmpty { lines += ["", "Change: \(fit.change)"] }
            lines.append("")
        }
        if let claims = insights?.claims, !claims.isEmpty {
            lines += ["## Claims (from the abstract)", ""] + claims.map { "- \($0.text)" } + [""]
        }
        if let plan = insights?.plan {
            let done = insights?.planDone ?? []
            lines += ["## Implementation plan (AI)", ""]
            if !plan.prerequisites.isEmpty { lines += ["**Prerequisites:** " + plan.prerequisites.joined(separator: "; "), ""] }
            for (i, step) in plan.steps.enumerated() {
                lines.append("- [\(done.contains(i) ? "x" : " ")] **\(step.title)** — \(step.detail)")
            }
            if !plan.success.isEmpty { lines += ["", "**It worked if:** \(plan.success)"] }
            if !plan.risks.isEmpty { lines += ["", "**Risks:** " + plan.risks.joined(separator: "; ")] }
            lines.append("")
        }
        lines += ["## Abstract", "", paper.abstractText, ""]
        return lines.joined(separator: "\n")
    }

    static func fileName(for paper: Paper) -> String {
        let safe = paper.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n")).joined(separator: "-")
        return String(safe.prefix(90)).trimmingCharacters(in: .whitespaces) + ".md"
    }

    /// Asks for a folder and writes one file per paper. Returns how many were written.
    @discardableResult
    static func export(_ papers: [Paper]) -> Int {
        guard !papers.isEmpty else { return 0 }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export \(papers.count) Paper\(papers.count == 1 ? "" : "s")"
        panel.message = "Choose a folder — an Obsidian vault works."
        guard panel.runModal() == .OK, let folder = panel.url else { return 0 }
        var written = 0
        for paper in papers {
            let url = folder.appendingPathComponent(fileName(for: paper))
            if (try? markdown(for: paper).write(to: url, atomically: true, encoding: .utf8)) != nil { written += 1 }
        }
        return written
    }
}
