//
//  AppSection.swift
//  AIPapers
//
//  The app's top-level pages, shared by the sidebar, the top-tab switcher,
//  the Go menu shortcuts and Settings (which lets each one be hidden).
//

import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case archive = "Archive"
    case graph = "Graph"
    case analytics = "Analytics"
    case lab = "Lab"
    case trend = "Trend Brief"
    case triage = "Triage"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .archive: "archivebox"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .analytics: "chart.bar.xaxis"
        case .lab: "flask"
        case .trend: "text.book.closed"
        case .triage: "bolt.horizontal"
        }
    }

    static func hidden(fromCSV csv: String) -> Set<AppSection> {
        Set(csv.split(separator: ",").compactMap { AppSection(rawValue: String($0)) })
    }

    static func csv(fromHidden hidden: Set<AppSection>) -> String {
        hidden.map(\.rawValue).sorted().joined(separator: ",")
    }
}

enum NavigationStyle: String, CaseIterable, Identifiable {
    case sidebar
    case tabs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sidebar: "Sidebar"
        case .tabs: "Top tabs"
        }
    }
}
