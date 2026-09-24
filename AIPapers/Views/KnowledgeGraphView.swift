//
//  KnowledgeGraphView.swift
//  AIPapers
//
//  The Graph page: how papers connect across the Area → Topic → Subtopic
//  hierarchy, drawn by D3 as a bundled-edge ring (see ConnectionsWebView).
//  The similarity work runs once per change, off the main thread.
//

import SwiftUI
import SwiftData

struct KnowledgeGraphView: View {
    @Query private var allPapers: [Paper]
    @Binding var selectedPaper: Paper?
    @State private var data: ConnectionsData?
    @State private var isBuilding = true

    /// Rebuild when something the picture shows changes — not on every SwiftData tick.
    private var buildKey: String {
        "\(allPapers.count)-\(allPapers.filter { $0.subtopic != nil }.count)-\(allPapers.filter { $0.isRead }.count)-\(allPapers.filter { $0.isFavorite }.count)"
    }

    var body: some View {
        Group {
            if let data, data.nodes.count >= 3 {
                ConnectionsWebView(data: data, selectedID: selectedPaper?.id) { id in
                    selectedPaper = allPapers.first { $0.id == id }
                }
            } else if isBuilding {
                ProgressView("Finding connections…")
            } else {
                ContentUnavailableView(
                    "Not enough connections yet",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Papers need embeddings to be compared — refresh to pull some.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Graph")
        .paperInspector($selectedPaper)
        .task(id: buildKey) { await rebuild() }
    }

    private func rebuild() async {
        let inputs = allPapers.compactMap { paper -> ConnectionInput? in
            guard let embedding = paper.embedding, !embedding.isEmpty else { return nil }
            let topic = AnalyticsService.fixedTopic(for: paper)
            return ConnectionInput(
                id: paper.id, title: paper.title,
                area: Taxonomy.area(of: topic), topic: topic, subtopic: AnalyticsService.fixedSubtopic(for: paper),
                relevance: paper.relevanceScore, isRead: paper.isRead, isFavorite: paper.isFavorite,
                embedding: embedding
            )
        }
        data = await Task.detached { ConnectionsService.build(inputs) }.value
        isBuilding = false
    }
}
