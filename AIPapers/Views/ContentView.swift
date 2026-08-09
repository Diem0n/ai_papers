//
//  ContentView.swift
//  AIPapers
//

import SwiftUI
import SwiftData

private enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case archive = "Archive"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .dashboard: "sparkles"
        case .archive: "archivebox"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .dashboard
    @State private var selectedPaper: Paper?

    var body: some View {
        NavigationSplitView {
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
            case .none:
                ContentUnavailableView("Select a section", systemImage: "sidebar.left")
            }
        } detail: {
            if let selectedPaper {
                PaperDetailView(paper: selectedPaper)
            } else {
                ContentUnavailableView("Select a paper", systemImage: "doc.text")
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Paper.self, inMemory: true)
}
