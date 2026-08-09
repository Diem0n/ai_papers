//
//  ContentView.swift
//  AIPapers
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Paper.publishedAt, order: .reverse)
    private var papers: [Paper]

    var body: some View {
        NavigationSplitView {
            Group {
                if papers.isEmpty {
                    ContentUnavailableView(
                        "No papers yet",
                        systemImage: "tray",
                        description: Text("Your daily digest will appear here once papers are collected.")
                    )
                } else {
                    List(papers) { paper in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(paper.title)
                                .font(.headline)
                            Text(paper.authors)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("AI Papers")
        } detail: {
            Text("Select a paper")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Paper.self, inMemory: true)
}
