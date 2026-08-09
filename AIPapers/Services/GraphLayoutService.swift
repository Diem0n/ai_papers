//
//  GraphLayoutService.swift
//  AIPapers
//
//  A small force-directed layout (Fruchterman-Reingold style): nodes repel
//  each other, edges pull connected nodes together, everything drifts to
//  center. Runs a fixed number of iterations and returns the settled
//  positions — no continuous animation loop.
//

import Foundation
import CoreGraphics

enum GraphLayoutService {
    struct Edge {
        let from: String
        let to: String
        let weight: Double
    }

    static func layout(nodeIDs: [String], edges: [Edge], canvasSize: CGSize, iterations: Int = 300) -> [String: CGPoint] {
        guard !nodeIDs.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return [:] }

        var positions: [String: CGPoint] = [:]
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let radius = min(canvasSize.width, canvasSize.height) / 3
        for (index, id) in nodeIDs.enumerated() {
            let angle = (2 * Double.pi * Double(index)) / Double(max(nodeIDs.count, 1))
            positions[id] = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }

        let repulsion = 6000.0
        let springLength = 90.0
        let springStrength = 0.02
        let centeringStrength = 0.008
        let margin = 50.0

        for _ in 0..<iterations {
            var forces: [String: CGVector] = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, .zero) })

            for i in 0..<nodeIDs.count {
                for j in (i + 1)..<nodeIDs.count {
                    let a = nodeIDs[i], b = nodeIDs[j]
                    guard let pa = positions[a], let pb = positions[b] else { continue }
                    let dx = pa.x - pb.x, dy = pa.y - pb.y
                    let dist = max(sqrt(dx * dx + dy * dy), 1)
                    let force = repulsion / (dist * dist)
                    let fx = (dx / dist) * force, fy = (dy / dist) * force
                    forces[a]?.dx += fx; forces[a]?.dy += fy
                    forces[b]?.dx -= fx; forces[b]?.dy -= fy
                }
            }

            for edge in edges {
                guard let pa = positions[edge.from], let pb = positions[edge.to] else { continue }
                let dx = pb.x - pa.x, dy = pb.y - pa.y
                let dist = max(sqrt(dx * dx + dy * dy), 1)
                let force = (dist - springLength) * springStrength * edge.weight
                let fx = (dx / dist) * force, fy = (dy / dist) * force
                forces[edge.from]?.dx += fx; forces[edge.from]?.dy += fy
                forces[edge.to]?.dx -= fx; forces[edge.to]?.dy -= fy
            }

            for id in nodeIDs {
                guard var pos = positions[id], let force = forces[id] else { continue }
                pos.x += force.dx + (center.x - pos.x) * centeringStrength
                pos.y += force.dy + (center.y - pos.y) * centeringStrength
                pos.x = min(max(pos.x, margin), canvasSize.width - margin)
                pos.y = min(max(pos.y, margin), canvasSize.height - margin)
                positions[id] = pos
            }
        }

        return positions
    }
}
