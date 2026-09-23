//
//  ContentView.swift
//  AIPapers
//
//  Two navigation layouts, chosen in Settings: a sidebar (the default), or
//  top tabs — a segmented switcher in the toolbar for people who'd rather
//  give the sidebar's width to the content.
//

import SwiftUI
import SwiftData

private struct SidebarRow: View {
    let item: AppSection
    let count: Int?

    var body: some View {
        Label {
            HStack {
                Text(item.rawValue)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: item.systemImage)
        }
    }
}

/// The segmented section switcher used when the sidebar is turned off.
private struct SectionSwitcher: ViewModifier {
    let isActive: Bool
    let sections: [AppSection]
    @Binding var selection: AppSection?

    func body(content: Content) -> some View {
        content.toolbar {
            if isActive {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: Binding(
                        get: { selection ?? sections.first ?? .dashboard },
                        set: { selection = $0 }
                    )) {
                        ForEach(sections) { section in
                            Label(section.rawValue, systemImage: section.systemImage).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.titleAndIcon)
                }
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var appActivity: AppActivity
    @Query private var allPapers: [Paper]

    @AppStorage(AppSettingsKeys.navigationStyle) private var navigationStyleRaw = NavigationStyle.sidebar.rawValue
    @AppStorage(AppSettingsKeys.sidebarVisibleByDefault) private var sidebarVisibleByDefault = true
    @AppStorage(AppSettingsKeys.hiddenSections) private var hiddenSectionsCSV = ""

    @State private var selection: AppSection? = .dashboard
    @State private var selectedPaper: Paper?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var navigationStyle: NavigationStyle {
        NavigationStyle(rawValue: navigationStyleRaw) ?? .sidebar
    }

    /// Never empty: if every section were hidden there'd be nowhere to go.
    private var visibleSections: [AppSection] {
        let hidden = AppSection.hidden(fromCSV: hiddenSectionsCSV)
        let visible = AppSection.allCases.filter { !hidden.contains($0) }
        return visible.isEmpty ? AppSection.allCases : visible
    }

    private var unreadCount: Int {
        allPapers.filter { !$0.isRead }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            layout
        }
        .onAppear(perform: syncSidebarVisibility)
        .onChange(of: selection, updateColumnVisibility)
        .onChange(of: sidebarVisibleByDefault) { syncSidebarVisibility() }
        .onChange(of: hiddenSectionsCSV) { ensureSelectionVisible() }
        .onChange(of: router.pendingPaperID, handlePendingPaperID)
        .onChange(of: router.pendingTrendOpen, handlePendingTrendOpen)
        .onChange(of: router.pendingSection, handlePendingSection)
    }

    // MARK: Layout

    @ViewBuilder
    private var layout: some View {
        switch navigationStyle {
        case .sidebar: sidebarLayout
        case .tabs: tabsLayout
        }
    }

    @ViewBuilder
    private var sidebarLayout: some View {
        if selection?.isFullWidth == true {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarColumn
            } detail: {
                fullWidthPage
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarColumn
            } content: {
                contentColumn
            } detail: {
                detailColumn
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    @ViewBuilder
    private var tabsLayout: some View {
        if selection?.isFullWidth == true {
            NavigationStack {
                fullWidthPage
            }
        } else {
            NavigationSplitView {
                contentColumn
            } detail: {
                detailColumn
            }
        }
    }

    private var sidebarColumn: some View {
        List(visibleSections, selection: $selection) { item in
            SidebarRow(item: item, count: sidebarCount(for: item))
                .tag(item)
                .padding(.vertical, 4)
        }
        .navigationTitle("AI Papers")
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
    }

    /// Dashboard, Analytics and Trend Brief: whole-window pages with no paper detail pane.
    @ViewBuilder
    private var fullWidthPage: some View {
        Group {
            switch selection {
            case .analytics:
                AnalyticsView()
            case .trend:
                TrendBriefView()
            case .triage:
                TriageView()
            case .ask:
                AskView()
            default:
                DashboardView(onOpenSection: { selection = $0 })
            }
        }
        .modifier(SectionSwitcher(isActive: navigationStyle == .tabs, sections: visibleSections, selection: $selection))
    }

    @ViewBuilder
    private var contentColumn: some View {
        Group {
            switch selection {
            case .archive:
                ArchiveView(selectedPaper: $selectedPaper)
            case .graph:
                KnowledgeGraphView(selectedPaper: $selectedPaper)
                    .navigationSplitViewColumnWidth(min: 420, ideal: 700)
            default:
                EmptyView() // dashboard, analytics and trend brief are handled by fullWidthPage
            }
        }
        .modifier(SectionSwitcher(isActive: navigationStyle == .tabs, sections: visibleSections, selection: $selection))
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let selectedPaper {
            PaperDetailView(paper: selectedPaper, onSelectRelated: { self.selectedPaper = $0 })
        } else {
            ContentUnavailableView("Select a paper", systemImage: "doc.text")
        }
    }

    // MARK: Status

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
        } else if appActivity.isCategorizing {
            BannerView(
                text: "Categorizing papers: \(appActivity.categorizeCompleted) of \(appActivity.categorizeTotal)",
                isError: false
            )
        } else if appActivity.isRefreshing, let progress = appActivity.refreshProgressText {
            BannerView(text: progress, isError: false)
        } else if let status = appActivity.refreshStatusMessage {
            BannerView(text: status, isError: false)
        }
    }

    private func sidebarCount(for item: AppSection) -> Int? {
        switch item {
        case .dashboard, .triage: unreadCount > 0 ? unreadCount : nil
        case .archive: allPapers.count
        case .graph, .analytics, .trend, .ask: nil
        }
    }

    // MARK: Navigation events

    private func syncSidebarVisibility() {
        columnVisibility = sidebarVisibleByDefault ? .all : .automatic
    }

    private func updateColumnVisibility(from oldValue: AppSection?, to newValue: AppSection?) {
        // With the sidebar set to visible it stays visible everywhere. Only
        // when it isn't pinned does the Graph reclaim its width for the canvas.
        if sidebarVisibleByDefault {
            columnVisibility = .all
        } else {
            columnVisibility = newValue == .graph ? .doubleColumn : .automatic
        }
    }

    private func ensureSelectionVisible() {
        if let selection, !visibleSections.contains(selection) {
            self.selection = visibleSections.first
        }
    }

    private func handlePendingSection(from oldValue: AppSection?, to section: AppSection?) {
        guard let section else { return }
        if visibleSections.contains(section) {
            selection = section
        }
        router.pendingSection = nil
    }

    private func handlePendingPaperID(from oldValue: String?, to paperID: String?) {
        guard let paperID else { return }
        openPaper(id: paperID)
        selection = .archive
        router.pendingPaperID = nil
    }

    private func handlePendingTrendOpen(from oldValue: Bool, to shouldOpen: Bool) {
        guard shouldOpen else { return }
        selection = .trend
        router.pendingTrendOpen = false
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
        HStack(spacing: 8) {
            if isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Text(text)
                .font(.callout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.primary), alignment: .bottom)
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
