//
//  ContentView.swift
//  AIPapers
//

import SwiftUI
import SwiftData

private enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case archive = "Archive"
    case graph = "Graph"
    case trend = "Trend Brief"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .dashboard: "sparkles"
        case .archive: "archivebox"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .trend: "text.book.closed"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var appActivity: AppActivity
    @State private var selection: SidebarItem? = .dashboard
    @State private var selectedPaper: Paper?
    // Graph wants the canvas, not the nav rail — collapsed automatically when
    // it's open. The system sidebar-toggle button still brings it back.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        VStack(spacing: 0) {
            statusBanner

            NavigationSplitView(columnVisibility: $columnVisibility) {
                List(SidebarItem.allCases, selection: $selection) { item in
                    Label(item.rawValue, systemImage: item.systemImage)
                        .tag(item)
                        .padding(.vertical, 4)
                }
                .navigationTitle("AI Papers")
                .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            } content: {
                switch selection {
                case .dashboard:
                    DashboardView(selectedPaper: $selectedPaper)
                case .archive:
                    ArchiveView(selectedPaper: $selectedPaper)
                case .graph:
                    KnowledgeGraphView(selectedPaper: $selectedPaper)
                        .navigationSplitViewColumnWidth(min: 420, ideal: 700)
                case .trend:
                    TrendBriefView()
                        .navigationSplitViewColumnWidth(min: 420, ideal: 600)
                case .none:
                    ContentUnavailableView("Select a section", systemImage: "sidebar.left")
                }
            } detail: {
                if let selectedPaper {
                    PaperDetailView(paper: selectedPaper, onSelectRelated: { self.selectedPaper = $0 })
                } else {
                    ContentUnavailableView("Select a paper", systemImage: "doc.text")
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
        .onChange(of: selection) { _, newValue in
            columnVisibility = newValue == .graph ? .doubleColumn : .automatic
        }
        .onChange(of: router.pendingPaperID) { _, paperID in
            guard let paperID else { return }
            openPaper(id: paperID)
            router.pendingPaperID = nil
        }
        .onChange(of: router.pendingTrendOpen) { _, shouldOpen in
            guard shouldOpen else { return }
            selection = .trend
            router.pendingTrendOpen = false
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let error = appActivity.refreshErrorMessage {
            BannerView(text: error, isError: true)
        } else if appActivity.isSummarizingAll, let startedAt = appActivity.summarizeStartedAt {
            SummarizeAllBanner(
                completed: appActivity.summarizeCompleted,
                total: appActivity.summarizeTotal,
                startedAt: startedAt
            )
        } else if appActivity.isRefreshing, let progress = appActivity.refreshProgressText {
            BannerView(text: progress, isError: false)
        } else if let status = appActivity.refreshStatusMessage {
            BannerView(text: status, isError: false)
        }
    }

    private func openPaper(id: String) {
        let descriptor = FetchDescriptor<Paper>(predicate: #Predicate { $0.id == id })
        selectedPaper = try? modelContext.fetch(descriptor).first
    }
}

struct BannerView: View {
    let text: String
    let isError: Bool

    var body: some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isError ? Color.red.opacity(0.12) : Color.primary.opacity(0.06))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(.separator), alignment: .bottom)
    }
}

private struct SummarizeAllBanner: View {
    let completed: Int
    let total: Int
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startedAt))
            BannerView(
                text: "Generating summaries: \(completed) of \(total) · \(elapsed)s elapsed",
                isError: false
            )
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Paper.self, inMemory: true)
        .environmentObject(AppRouter())
        .environmentObject(AppActivity(modelContainer: try! ModelContainer(for: Paper.self)))
}
