//
//  ArchiveView.swift
//  AIPapers
//

import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Query(sort: \Paper.publishedAt, order: .reverse) private var papers: [Paper]
    @EnvironmentObject private var appActivity: AppActivity
    @Binding var selectedPaper: Paper?
    @State private var searchText = ""

    private var filteredPapers: [Paper] {
        guard !searchText.isEmpty else { return papers }
        return papers.filter { paper in
            paper.title.localizedCaseInsensitiveContains(searchText)
                || paper.authors.localizedCaseInsensitiveContains(searchText)
                || (paper.category ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var missingSummaryCount: Int {
        papers.filter { $0.summary == nil }.count
    }

    var body: some View {
        Group {
            if papers.isEmpty {
                ContentUnavailableView(
                    "Archive is empty",
                    systemImage: "archivebox",
                    description: Text("Papers you've seen will appear here.")
                )
            } else {
                List(selection: $selectedPaper) {
                    ForEach(filteredPapers) { paper in
                        PaperRowView(paper: paper).tag(paper)
                    }
                }
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
            }
        }
        .navigationTitle("Archive")
        .searchable(text: $searchText, prompt: "Search papers")
        .toolbar {
            ToolbarItem {
                Button {
                    appActivity.summarizeAllMissing()
                } label: {
                    if appActivity.isSummarizingAll {
                        ProgressView()
                    } else {
                        Label("Generate Summaries (\(missingSummaryCount))", systemImage: "text.badge.plus")
                    }
                }
                .disabled(appActivity.isSummarizingAll || missingSummaryCount == 0)
            }
        }
    }
}
