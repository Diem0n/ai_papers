//
//  PaperReaderView.swift
//  AIPapers
//
//  The full paper in its own window, rendered by PDFKit from the locally
//  saved PDF — so reading never sends you to arXiv in a browser.
//

import SwiftUI
import PDFKit

/// What the reader window is opened with (a value type so `openWindow` can carry it).
struct ReaderTarget: Codable, Hashable {
    let id: String
    let title: String
}

struct PaperReaderView: View {
    let target: ReaderTarget

    @ObservedObject private var network = NetworkStatus.shared
    @State private var state: LoadState = .loading

    private enum LoadState {
        case loading
        case ready(URL)
        case failed(String)
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                VStack(spacing: 6) {
                    ProgressView()
                    Text("Downloading from arXiv…")
                    Text("It's saved on this Mac afterwards, so it opens instantly next time. arXiv can take up to a minute.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            case .ready(let url):
                PDFKitView(url: url)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't open the paper", systemImage: "doc.badge.ellipsis")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 500)
        .navigationTitle(target.title)
        .toolbar {
            if case .ready(let url) = state {
                ToolbarItem {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .help("Show the saved PDF in Finder")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .ready(try await PaperPDFService.fetch(target.id))
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? "Something went wrong.")
        }
    }
}

private struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
