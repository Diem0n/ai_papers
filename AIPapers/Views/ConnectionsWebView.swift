//
//  ConnectionsWebView.swift
//  AIPapers
//
//  Hosts the D3 visualization (Resources/connections.html + a bundled d3.min.js)
//  in a WKWebView. Everything is loaded from the app bundle — no network — and
//  Swift only hands it JSON and listens for a click on a paper.
//

import SwiftUI
import WebKit

struct ConnectionsWebView: NSViewRepresentable {
    let data: ConnectionsData
    let selectedID: String?
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakScriptHandler(context.coordinator), name: "select")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.setValue(false, forKey: "drawsBackground") // let the window material show through
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        if let page = Bundle.main.url(forResource: "connections", withExtension: "html") {
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.update(data: data, selectedID: selectedID)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var onSelect: (String) -> Void = { _ in }

        private var loaded = false
        private var data: ConnectionsData?
        private var renderedSignature: String?
        private var selectedID: String?

        func update(data: ConnectionsData, selectedID: String?) {
            self.data = data
            self.selectedID = selectedID
            if loaded { flush() }
        }

        private func flush() {
            guard let web, let data else { return }
            if renderedSignature != data.signature {
                renderedSignature = data.signature
                if let json = try? JSONEncoder().encode(data), let text = String(data: json, encoding: .utf8) {
                    web.evaluateJavaScript("window.render(\(text))")
                }
            }
            let id = selectedID.map { "\"\($0)\"" } ?? "null"
            web.evaluateJavaScript("window.setSelected(\(id))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            flush()
        }

        /// The page is local; never let it navigate anywhere else.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.isFileURL == true ? .allow : .cancel
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let id = message.body as? String { onSelect(id) }
        }
    }
}

/// WKUserContentController retains its handlers; this keeps that from retaining the coordinator.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
