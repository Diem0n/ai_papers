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

    /// Ranks papers by similarity to an arbitrary query vector (not a paper) —
    /// the basis of search-by-meaning. Papers without an embedding are skipped.
    static func rank(query: [Double], among candidates: [Paper], limit: Int) -> [(paper: Paper, score: Double)] {
        candidates
            .compactMap { paper -> (Paper, Double)? in
                guard let embedding = paper.embedding else { return nil }
                return (paper, cosineSimilarity(query, embedding))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (paper: $0.0, score: $0.1) }
    }

    /// Search by meaning *and* wording. Embeddings alone are fuzzy at this
    /// model size (a paper literally about KV caches can rank 4th for "shrink
    /// attention cache memory"), so the semantic ranking is fused with a
    /// keyword-overlap ranking by reciprocal rank fusion — a paper that is
    /// both close in meaning and shares the query's words rises to the top.
    /// `score` stays the plain cosine similarity, for display.
    static func hybridRank(queryVector: [Double], queryText: String, among candidates: [Paper], limit: Int) -> [(paper: Paper, score: Double)] {
        let semantic = rank(query: queryVector, among: candidates, limit: candidates.count)
        let stems = queryText.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 4 && !searchFiller.contains($0) }
            .map { String($0.prefix(5)) }   // crude stemming: cache/caches/caching
        guard !stems.isEmpty else { return Array(semantic.prefix(limit)) }

        func overlap(_ paper: Paper) -> Int {
            let words = "\(paper.title) \(paper.abstractText)".lowercased()
                .split { !$0.isLetter && !$0.isNumber }
            let wordSet = Set(words.map { String($0.prefix(5)) })
            return stems.filter { wordSet.contains($0) }.count
        }
        let overlaps = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, overlap($0)) })
        let keywordOrder = semantic.map(\.paper)
            .filter { overlaps[$0.id, default: 0] > 0 }
            .sorted { overlaps[$0.id, default: 0] > overlaps[$1.id, default: 0] }
        let keywordRank = Dictionary(uniqueKeysWithValues: keywordOrder.enumerated().map { ($1.id, $0) })

        let k = 60.0
        return semantic.enumerated()
            .map { index, hit -> (hit: (paper: Paper, score: Double), fused: Double) in
                let fused = 1 / (k + Double(index)) + (keywordRank[hit.paper.id].map { 1 / (k + Double($0)) } ?? 0)
                return (hit, fused)
            }
            .sorted { $0.fused > $1.fused }
            .prefix(limit)
            .map(\.hit)
    }

    private static let searchFiller: Set<String> = ["that", "with", "from", "this", "about", "what", "which", "into", "over", "make", "makes", "using", "used", "ways", "papers", "paper"]
}
