//
//  ExplanationView.swift
//  AIPapers
//
//  Renders a /explain answer as labeled sections with breathing room — the raw
//  text is one dense block of "**Label** — body" lines. The final "Answer"
//  section is held behind a disclosure so the reader can try the check
//  question first. Also home to the small Copy button used on every answer.
//

import SwiftUI
import AppKit

enum ExplanationParser {
    struct Section: Identifiable {
        let label: String
        let body: String
        var id: String { label }
    }

    /// Splits "**Label** — body" lines into sections; inline "2. " steps go on their own lines.
    static func sections(_ text: String) -> [Section] {
        var result: [Section] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("**"), let close = trimmed.range(of: "**", range: trimmed.index(trimmed.startIndex, offsetBy: 2)..<trimmed.endIndex) {
                let label = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
                let body = String(trimmed[close.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " :—–-"))
                result.append(Section(label: label, body: body))
            } else if !trimmed.isEmpty, let last = result.popLast() {
                result.append(Section(label: last.label, body: last.body + "\n" + trimmed))
            } else if !trimmed.isEmpty {
                result.append(Section(label: "", body: trimmed))
            }
        }
        return result.map { Section(label: $0.label, body: spreadSteps($0.body)) }
    }

    /// "1. a 2. b 3. c" on one line → one step per line.
    private static func spreadSteps(_ body: String) -> String {
        guard body.contains("1.") else { return body }
        return body.replacingOccurrences(of: #"\s+(?=\d\.\s)"#, with: "\n", options: .regularExpression)
    }
}

struct ExplanationView: View {
    let text: String
    var font: Font = .callout

    var body: some View {
        let sections = ExplanationParser.sections(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sections) { section in
                if section.label.lowercased() == "answer" {
                    DisclosureGroup("Show the answer") {
                        Text(section.body)
                            .font(font)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .font(font)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        if !section.label.isEmpty {
                            Text(section.label.uppercased())
                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(section.label.lowercased().hasPrefix("check") ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                        Text(section.body)
                            .font(section.label.lowercased() == "in one line" ? font.weight(.semibold) : font)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// Copies text to the pasteboard and confirms with a checkmark for a moment.
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
        .help("Copy the answer")
    }
}
