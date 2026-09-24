//
//  ConnectionsService.swift
//  AIPapers
//
//  The data behind the Connections view: every embedded paper placed in the
//  Area → Topic → Subtopic hierarchy, plus a link between papers whose
//  abstracts are close in embedding space (each paper's nearest few, deduped).
//  Pure and Sendable, so it runs off the main thread; drawing is D3's job.
//

import Foundation

nonisolated struct ConnectionInput: Sendable {
    let id: String
    let title: String
    let area: String
    let topic: String
    let subtopic: String
    let relevance: Double
    let isRead: Bool
    let isFavorite: Bool
    let embedding: [Double]
}

nonisolated struct ConnectionNode: Codable, Sendable {
    let id: String
    let title: String
    let area: String
    let topic: String
    let subtopic: String
    let relevance: Double
    let isRead: Bool
    let isFavorite: Bool
}

nonisolated struct ConnectionLink: Codable, Sendable {
    let source: String
    let target: String
    let score: Double
}

nonisolated struct ConnectionsData: Codable, Sendable {
    let nodes: [ConnectionNode]
    let links: [ConnectionLink]
    /// Areas in taxonomy order, so colors stay stable between launches.
    let areas: [String]
    /// Changes when the picture would change — lets the web view skip a redraw when it wouldn't.
    let signature: String
}

nonisolated enum ConnectionsService {
    /// Enough papers to fill the ring without turning the labels to mush.
    static let maxNodes = 400

    /// - neighbours: links kept per paper before deduplication.
    /// - floor: similarity below which two papers aren't called related at all.
    static func build(_ inputs: [ConnectionInput], neighbours: Int = 3, floor: Double = 0.6) -> ConnectionsData {
        let papers = Array(inputs.sorted { $0.relevance > $1.relevance }.prefix(maxNodes))
        let units = papers.map { unit($0.embedding) }

        var best: [String: ConnectionLink] = [:]
        for i in papers.indices {
            var scored: [(j: Int, score: Double)] = []
            scored.reserveCapacity(papers.count)
            for j in papers.indices where j != i && units[j].count == units[i].count {
                scored.append((j, dot(units[i], units[j])))
            }
            for hit in scored.sorted(by: { $0.score > $1.score }).prefix(neighbours) where hit.score >= floor {
                let (a, b) = papers[i].id < papers[hit.j].id ? (papers[i].id, papers[hit.j].id) : (papers[hit.j].id, papers[i].id)
                best["\(a)|\(b)"] = ConnectionLink(source: a, target: b, score: hit.score)
            }
        }

        let signature = papers.map { "\($0.id)/\($0.topic)/\($0.subtopic)/\($0.isRead)/\($0.isFavorite)" }.joined(separator: ",")
            + "|\(best.count)"
        return ConnectionsData(
            nodes: papers.map {
                ConnectionNode(id: $0.id, title: $0.title, area: $0.area, topic: $0.topic, subtopic: $0.subtopic,
                               relevance: $0.relevance, isRead: $0.isRead, isFavorite: $0.isFavorite)
            },
            links: best.values.sorted { $0.score > $1.score },
            areas: Taxonomy.areas + [Taxonomy.uncategorized],
            signature: String(fnv1a(signature), radix: 16)
        )
    }

    /// FNV-1a — stable, unlike Swift's randomized String.hashValue.
    private static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return hash
    }

    private static func dot(_ a: [Double], _ b: [Double]) -> Double {
        var sum = 0.0
        for i in a.indices { sum += a[i] * b[i] }
        return sum
    }

    private static func unit(_ v: [Double]) -> [Double] {
        let norm = dot(v, v).squareRoot()
        return norm > 0 ? v.map { $0 / norm } : v
    }
}
