//
//  DashboardView.swift
//  AIPapers
//
//  "What should I read today?" — top-ranked papers, not just recent ones.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Paper.relevanceScore, order: .reverse) private var allPapers: [Paper]
    @Binding var selectedPaper: Paper?

    @State private var isRefreshing = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var topPapers: [Paper] {
        Array(allPapers.prefix(30))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                banner(errorMessage, isError: true)
            } else if let statusMessage {
                banner(statusMessage, isError: false)
            }

            if allPapers.isEmpty {
                ContentUnavailableView(
                    "No papers yet",
                    systemImage: "tray",
                    description: Text("Refresh to fetch today's AI engineering papers.")
                )
            } else {
                List(selection: $selectedPaper) {
                    ForEach(topPapers) { paper in
                        PaperRowView(paper: paper).tag(paper)
                    }
                }
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .task {
            await autoRefreshIfNeeded()
        }
    }

    private func autoRefreshIfNeeded() async {
        let refreshedToday = allPapers.contains { Calendar.current.isDateInToday($0.discoveredAt) }
        guard !refreshedToday else { return }
        await refresh()
    }

    private func banner(_ text: String, isError: Bool) -> some View {
        Text(text)
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isError ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.12))
    }

    private func refresh() async {
        isRefreshing = true
        errorMessage = nil
        statusMessage = nil
        defer { isRefreshing = false }

        let service = PaperService(repository: PaperRepository(context: modelContext))
        do {
            let result = try await service.refresh()
            if result.papersAdded == 0 {
                statusMessage = "No new papers found. Your archive is already up to date."
            } else if result.summariesFailed > 0 {
                statusMessage = "Added \(result.papersAdded) papers. \(result.summariesFailed) summaries unavailable — Ollama isn't running. Start Ollama and try again."
            } else {
                statusMessage = "Added \(result.papersAdded) new papers."
            }
        } catch let error as ArxivServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "arXiv is unavailable. Check your connection and try again."
        }
    }
}
