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
import WebKit

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

/// The explanation, drawn by KaTeX-enabled HTML (bundled, offline) so equations
/// typeset properly. It grows to its content; scrolling is left to the parent.
struct ExplanationView: View {
    let text: String
    @State private var height: CGFloat = 120

    var body: some View {
        ExplanationWebView(sections: ExplanationParser.sections(text), height: $height)
            .frame(height: height)
    }
}

private final class PassThroughWebView: WKWebView {
    /// The page never scrolls itself; hand wheel events to the surrounding ScrollView.
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
}

private struct ExplanationWebView: NSViewRepresentable {
    let sections: [ExplanationParser.Section]
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakHandler(context.coordinator), name: "height")
        let web = PassThroughWebView(frame: .zero, configuration: configuration)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        if let page = Bundle.main.url(forResource: "explanation", withExtension: "html") {
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.setHeight = { height = $0 }
        context.coordinator.update(sections)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var setHeight: (CGFloat) -> Void = { _ in }
        private var loaded = false
        private var pending: [ExplanationParser.Section] = []
        private var rendered: String?

        func update(_ sections: [ExplanationParser.Section]) {
            pending = sections
            if loaded { flush() }
        }

        private func flush() {
            let payload = pending.map { ["label": $0.label, "body": $0.body] }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8), json != rendered else { return }
            rendered = json
            web?.evaluateJavaScript("window.render(\(json))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            flush()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.isFileURL == true ? .allow : .cancel
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let value = message.body as? Double, value > 0 { setHeight(CGFloat(value)) }
        }
    }
}

private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
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
