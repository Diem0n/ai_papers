//
//  DashboardView.swift
//  AIPapers
//
//  "What should I read today?" — top-ranked papers, not just recent ones.
//  Refresh status lives in AppActivity (shown by ContentView's persistent
//  banner) so it isn't tied to this view's lifecycle.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.Diem0n.AIPapers", category: "DashboardView")

struct DashboardView: View {
    @EnvironmentObject private var appActivity: AppActivity
    @Query(sort: \Paper.relevanceScore, order: .reverse) private var allPapers: [Paper]
    @Binding var selectedPaper: Paper?

    private var topPapers: [Paper] {
        Array(allPapers.prefix(30))
    }

    var body: some View {
        Group {
            if allPapers.isEmpty {
                if appActivity.isRefreshing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(appActivity.refreshProgressText ?? "Refreshing…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "No papers yet",
                        systemImage: "tray",
                        description: Text("Refresh to fetch today's AI engineering papers.")
                    )
                }
            } else {
                List(selection: $selectedPaper) {
                    ForEach(topPapers) { paper in
                        PaperRowView(paper: paper).tag(paper)
                    }
                }
                .navigationSplitViewColumnWidth(min: 360, ideal: 560)
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem {
                Button {
                    appActivity.refresh()
                } label: {
                    if appActivity.isRefreshing {
                        ProgressView()
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(appActivity.isRefreshing)
            }
        }
        .task {
            logger.notice("Dashboard loaded with \(allPapers.count, privacy: .public) stored papers")
            appActivity.autoRefreshIfNeeded()
        }
    }
}
