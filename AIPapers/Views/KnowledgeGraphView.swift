//
//  KnowledgeGraphView.swift
//  AIPapers
//
//  Papers as nodes, edges above a similarity threshold. Layout settles once
//  via GraphLayoutService, then nodes are freely draggable — no continuous
//  physics loop.
//

import SwiftUI
import SwiftData

private let similarityThreshold = 0.75

struct KnowledgeGraphView: View {
    @Query private var allPapers: [Paper]
    @Binding var selectedPaper: Paper?

    @State private var nodePositions: [String: CGPoint] = [:]

    private var embeddedPapers: [Paper] {
        allPapers.filter { $0.embedding != nil }
    }

    private var edges: [GraphLayoutService.Edge] {
        var result: [GraphLayoutService.Edge] = []
        for i in 0..<embeddedPapers.count {
            for j in (i + 1)..<embeddedPapers.count {
                let a = embeddedPapers[i], b = embeddedPapers[j]
                guard let ea = a.embedding, let eb = b.embedding else { continue }
                let similarity = SimilarityService.cosineSimilarity(ea, eb)
                if similarity > similarityThreshold {
                    result.append(.init(from: a.id, to: b.id, weight: similarity))
                }
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
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
                        GraphNodeView(paper: paper, isSelected: selectedPaper?.id == paper.id)
                            .position(position)
                            .gesture(
                                DragGesture(coordinateSpace: .local)
                                    .onChanged { value in nodePositions[paper.id] = value.location }
                            )
                            .onTapGesture { selectedPaper = paper }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear { layoutIfNeeded(size: geometry.size) }
            .onChange(of: embeddedPapers.map(\.id)) { layoutIfNeeded(size: geometry.size) }
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

    private func layoutIfNeeded(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let ids = embeddedPapers.map(\.id)
        guard ids.contains(where: { nodePositions[$0] == nil }) else { return }
        nodePositions = GraphLayoutService.layout(nodeIDs: ids, edges: edges, canvasSize: size)
    }
}

private struct GraphNodeView: View {
    let paper: Paper
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.6))
                .frame(width: 14, height: 14)
            Text(paper.title)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 100)
        }
        .contentShape(Rectangle())
    }
}
