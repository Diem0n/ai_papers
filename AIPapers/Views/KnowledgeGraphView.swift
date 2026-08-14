//
//  KnowledgeGraphView.swift
//  AIPapers
//
//  Papers as nodes, edges above a similarity threshold, colored by connected
//  cluster. Edge/cluster computation is O(n²) over embeddings — it runs once
//  when the embedded-paper set changes, cached in @State, never recomputed
//  during render (that was the earlier slowness: it was a computed property
//  re-evaluated on every drag frame).
//

import SwiftUI
import SwiftData

private let similarityThreshold = 0.75
private let maxLabeledEdges = 40 // beyond this, cluster color alone carries the signal

private struct GraphEdge: Identifiable {
    let id: String
    let from: String
    let to: String
    let weight: Double
    let sharedTopics: [String]
}

private struct GraphCluster {
    let label: String
    let color: Color
}

struct KnowledgeGraphView: View {
    @Query private var allPapers: [Paper]
    @Binding var selectedPaper: Paper?
    @Environment(\.colorScheme) private var colorScheme

    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var edges: [GraphEdge] = []
    @State private var nodeClusterIndex: [String: Int] = [:]
    @State private var clusters: [GraphCluster] = []
    @State private var computedForIDs: Set<String> = []
    @State private var lastLayoutSize: CGSize = .zero
    @State private var hoveredPaperID: String?

    private var embeddedPapers: [Paper] {
        allPapers.filter { $0.embedding != nil }
    }

    private var clusterPalette: [Color] {
        colorScheme == .dark
            ? [Color(hex: "#3987e5"), Color(hex: "#d95926"), Color(hex: "#199e70")]
            : [Color(hex: "#2a78d6"), Color(hex: "#eb6834"), Color(hex: "#1baf7a")]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if edges.count <= maxLabeledEdges {
                    ForEach(edges) { edge in
                        if let from = nodePositions[edge.from], let to = nodePositions[edge.to] {
                            let midpoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                            if let topic = edge.sharedTopics.first {
                                Text(topic)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 3)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 3))
                                    .position(midpoint)
                            }
                        }
                    }
                }

                Canvas { context, _ in
                    for edge in edges {
                        guard let from = nodePositions[edge.from], let to = nodePositions[edge.to] else { continue }
                        var path = Path()
                        path.move(to: from)
                        path.addLine(to: to)
                        context.stroke(path, with: .color(.secondary.opacity(edge.weight * 0.5)), lineWidth: 1)
                    }
                }

                ForEach(embeddedPapers) { paper in
                    if let position = nodePositions[paper.id] {
                        GraphNodeView(
                            paper: paper,
                            isSelected: selectedPaper?.id == paper.id,
                            showLabel: selectedPaper?.id == paper.id || hoveredPaperID == paper.id,
                            color: nodeColor(for: paper.id)
                        )
                        .position(position)
                        .gesture(
                            DragGesture(coordinateSpace: .local)
                                .onChanged { value in nodePositions[paper.id] = value.location }
                        )
                        .onTapGesture { selectedPaper = paper }
                        .onHover { isHovered in hoveredPaperID = isHovered ? paper.id : nil }
                        .zIndex(selectedPaper?.id == paper.id || hoveredPaperID == paper.id ? 1 : 0)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear { recomputeIfNeeded(size: geometry.size) }
            .onChange(of: embeddedPapers.map(\.id)) { recomputeIfNeeded(size: geometry.size) }
            .onChange(of: geometry.size) { recomputeIfNeeded(size: geometry.size) }
        }
        .overlay(alignment: .topTrailing) {
            if !clusters.isEmpty {
                legend
            }
        }
        .overlay {
            if embeddedPapers.count < 2 {
                ContentUnavailableView(
                    "Not enough connections yet",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Open a few papers to build up their embeddings — the graph fills in as you go.")
                )
            }
        }
        .navigationTitle("Graph")
    }

    private func nodeColor(for paperID: String) -> Color {
        guard let index = nodeClusterIndex[paperID], index < clusterPalette.count else {
            return .secondary
        }
        return clusterPalette[index]
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                HStack(spacing: 6) {
                    Circle().fill(cluster.color).frame(width: 8, height: 8)
                    Text(cluster.label).font(.caption2)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }

    private func recomputeIfNeeded(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let ids = Set(embeddedPapers.map(\.id))
        let sizeChanged = abs(lastLayoutSize.width - size.width) > 40 || abs(lastLayoutSize.height - size.height) > 40
        guard ids != computedForIDs || sizeChanged else { return }
        computedForIDs = ids

        let topics = AppSettings.topics
        var computedEdges: [GraphEdge] = []
        for i in 0..<embeddedPapers.count {
            for j in (i + 1)..<embeddedPapers.count {
                let a = embeddedPapers[i], b = embeddedPapers[j]
                guard let ea = a.embedding, let eb = b.embedding else { continue }
                let similarity = SimilarityService.cosineSimilarity(ea, eb)
                guard similarity > similarityThreshold else { continue }
                let shared = sharedTopics(a, b, topics: topics)
                computedEdges.append(GraphEdge(id: "\(a.id)-\(b.id)", from: a.id, to: b.id, weight: similarity, sharedTopics: shared))
            }
        }
        edges = computedEdges

        let (index, groups) = connectedComponents(paperIDs: Array(ids), edges: computedEdges)
        nodeClusterIndex = index
        clusters = groups.enumerated().prefix(clusterPalette.count).map { offset, group in
            GraphCluster(label: clusterLabel(for: group, edges: computedEdges), color: clusterPalette[offset])
        }

        let missingPositions = ids.contains { nodePositions[$0] == nil }
        if missingPositions || sizeChanged {
            nodePositions = GraphLayoutService.layout(nodeIDs: Array(ids), edges: computedEdges.map { .init(from: $0.from, to: $0.to, weight: $0.weight) }, canvasSize: size)
            lastLayoutSize = size
        }
    }

    private func sharedTopics(_ a: Paper, _ b: Paper, topics: [String]) -> [String] {
        let textA = (a.title + " " + a.abstractText).lowercased()
        let textB = (b.title + " " + b.abstractText).lowercased()
        return topics.filter { textA.contains($0.lowercased()) && textB.contains($0.lowercased()) }
    }

    private func clusterLabel(for paperIDs: [String], edges: [GraphEdge]) -> String {
        let idSet = Set(paperIDs)
        var topicCounts: [String: Int] = [:]
        for edge in edges where idSet.contains(edge.from) && idSet.contains(edge.to) {
            for topic in edge.sharedTopics {
                topicCounts[topic, default: 0] += 1
            }
        }
        let topTopics = topicCounts.sorted { $0.value > $1.value }.prefix(2).map(\.key)
        return topTopics.isEmpty ? "\(paperIDs.count) papers" : topTopics.joined(separator: " & ")
    }

    /// Union-find, grouped by root, sorted largest-first. Papers with no
    /// connections have no entry in the returned index (render as gray).
    private func connectedComponents(paperIDs: [String], edges: [GraphEdge]) -> (index: [String: Int], groups: [[String]]) {
        var parent: [String: String] = Dictionary(uniqueKeysWithValues: paperIDs.map { ($0, $0) })
        func find(_ x: String) -> String {
            var x = x
            while let p = parent[x], p != x { x = p }
            return x
        }
        func union(_ a: String, _ b: String) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        for edge in edges { union(edge.from, edge.to) }

        var groups: [String: [String]] = [:]
        for id in paperIDs { groups[find(id), default: []].append(id) }
        let sortedGroups = groups.values.filter { $0.count > 1 }.sorted { $0.count > $1.count }

        var index: [String: Int] = [:]
        for (i, group) in sortedGroups.enumerated() {
            for id in group { index[id] = i }
        }
        return (index, sortedGroups)
    }
}

private struct GraphNodeView: View {
    let paper: Paper
    let isSelected: Bool
    let showLabel: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isSelected || showLabel ? color : color.opacity(0.7))
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(.primary, lineWidth: isSelected ? 1.5 : 0))

            if showLabel {
                Text(paper.title)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 130)
                    .padding(4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        // Hit area bigger than the visible dot, and consistent whether or not
        // the label is showing — small targets are hard to tap/hover precisely.
        .frame(minWidth: 28, minHeight: 28)
        .contentShape(Rectangle())
    }
}
