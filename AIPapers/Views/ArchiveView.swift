//
//  ArchiveView.swift
//  AIPapers
//

import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Query(sort: \Paper.publishedAt, order: .reverse) private var papers: [Paper]
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
            }
        }
        .navigationTitle("Archive")
        .searchable(text: $searchText, prompt: "Search papers")
    }
}
