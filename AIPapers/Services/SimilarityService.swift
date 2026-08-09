//
//  SimilarityService.swift
//  AIPapers
//
//  Pure cosine-similarity math over embeddings — no persistence, no I/O.
//  Cheap enough (microseconds per pair) to run on demand rather than cache.
//

import Foundation

enum SimilarityService {
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denominator = (normA.squareRoot() * normB.squareRoot())
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    /// Ranks `candidates` by similarity to `target`'s embedding, most similar first.
    /// Candidates without an embedding yet are skipped.
    static func mostSimilar(to target: Paper, among candidates: [Paper], limit: Int) -> [(paper: Paper, score: Double)] {
        guard let targetEmbedding = target.embedding else { return [] }
        return candidates
            .filter { $0.id != target.id }
            .compactMap { paper -> (Paper, Double)? in
                guard let embedding = paper.embedding else { return nil }
                return (paper, cosineSimilarity(targetEmbedding, embedding))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (paper: $0.0, score: $0.1) }
    }
}
