//
//  PicksService.swift
//  AIPapers
//
//  "Picks for you": which five unread papers to read next, given what you've
//  favorited and read. The deterministic half — pure functions, no I/O:
//
//    1. Taste: a weighted average of the embeddings of papers you engaged
//       with (favorite counts most, then finished/reading, then merely opened).
//    2. Shortlist: unread papers closest to that taste, with a small nudge
//       for the paper's own relevance score.
//    3. Fallbacks for every thin case — no signals yet, fewer than five
//       candidates, papers without embeddings, the model unavailable — so the
//       card is never empty when there is anything unread.
//
//  The model's job (elsewhere) is only to choose five from the shortlist and
//  say why, in a few words, by reference to what you liked.
//

import Foundation

struct Pick: Identifiable {
    let paper: Paper
    let reason: String
    var id: String { paper.id }
}

struct PickCandidate {
    let paper: Paper
    /// Closeness to the reader's taste; nil when there is no taste to compare to.
    let similarity: Double?
    /// The liked paper it most resembles — the basis of a plain-language reason.
    let nearestLiked: Paper?
}

struct PickPool {
    /// Best first.
    let candidates: [PickCandidate]
    /// Strongest signals first.
    let liked: [Paper]
    /// False when nothing has been favorited/read yet (or none of it has an embedding).
    let isPersonalized: Bool
    /// Changes when the liked set or the shortlist changes — the cache key for the model's picks.
    let signature: String
}

enum PicksService {
    static let pickCount = 5
    private static let maxPerTopic = 2

    // MARK: Signals

    /// How strongly a paper says "I like this kind of thing".
    static func tasteWeight(_ paper: Paper) -> Double {
        var weight = 0.0
        if paper.isFavorite { weight += 3 }
        switch paper.status {
        case .done: weight += 2
        case .reading: weight += 1.5
        default: break
        }
        if paper.isRead { weight += 1 }
        return weight
    }

    static func pool(from papers: [Paper], shortlistSize: Int = 12) -> PickPool {
        let liked = papers
            .filter { tasteWeight($0) > 0 }
            .sorted { tasteWeight($0) != tasteWeight($1) ? tasteWeight($0) > tasteWeight($1) : $0.discoveredAt > $1.discoveredAt }
        let likedEmbedded = liked.filter { !($0.embedding ?? []).isEmpty }

        let unread = papers.filter { !$0.isRead && $0.status != .done }

        var candidates: [PickCandidate]
        let personalized = !likedEmbedded.isEmpty
        if personalized, let taste = tasteVector(likedEmbedded) {
            let likedUnits = likedEmbedded.map { unit($0.embedding ?? []) }
            let scored = unread.compactMap { paper -> (PickCandidate, Double)? in
                guard let embedding = paper.embedding, !embedding.isEmpty else { return nil }
                let vector = unit(embedding)
                let similarity = dot(vector, taste)
                let nearest = likedEmbedded.indices.max { dot(vector, likedUnits[$0]) < dot(vector, likedUnits[$1]) }.map { likedEmbedded[$0] }
                return (PickCandidate(paper: paper, similarity: similarity, nearestLiked: nearest), similarity + 0.15 * paper.relevanceScore)
            }.sorted { $0.1 > $1.1 }
            candidates = scored.prefix(shortlistSize).map(\.0)

            // Unread papers with no embedding can't be scored, but shouldn't
            // leave the card short if they're all there is.
            if candidates.count < pickCount {
                let have = Set(candidates.map { $0.paper.id })
                let extras = unread.filter { !have.contains($0.id) }
                    .sorted { $0.relevanceScore > $1.relevanceScore }
                    .prefix(pickCount - candidates.count)
                candidates += extras.map { PickCandidate(paper: $0, similarity: nil, nearestLiked: nil) }
            }
        } else {
            let byRelevance = unread.sorted { $0.relevanceScore > $1.relevanceScore }
            candidates = diversified(byRelevance.map { PickCandidate(paper: $0, similarity: nil, nearestLiked: nil) }, limit: shortlistSize)
        }

        return PickPool(
            candidates: candidates,
            liked: liked,
            isPersonalized: personalized,
            signature: signature(liked: liked, candidates: candidates, personalized: personalized)
        )
    }

    // MARK: Choosing

    /// The picks without any model: the best of the shortlist, at most two
    /// per topic, each with a reason drawn from the data.
    static func fallbackPicks(_ pool: PickPool) -> [Pick] {
        diversified(pool.candidates, limit: pickCount).map { Pick(paper: $0.paper, reason: reason(for: $0)) }
    }

    /// Turns the model's numbered choices (1-based, into the shortlist) into
    /// picks, discarding anything invalid or duplicated and topping up from
    /// the deterministic ranking so there are always as many as can be had.
    static func resolve(_ chosen: [(number: Int, why: String)], in pool: PickPool) -> [Pick] {
        var picks: [Pick] = []
        var seen = Set<String>()
        for (number, why) in chosen {
            guard pool.candidates.indices.contains(number - 1), picks.count < pickCount else { continue }
            let candidate = pool.candidates[number - 1]
            guard seen.insert(candidate.paper.id).inserted else { continue }
            let text = why.trimmingCharacters(in: .whitespacesAndNewlines)
            picks.append(Pick(paper: candidate.paper, reason: text.isEmpty ? reason(for: candidate) : String(text.prefix(140))))
        }
        if picks.count < pickCount {
            for pick in fallbackPicks(pool) where picks.count < pickCount && !seen.contains(pick.id) {
                picks.append(pick)
                seen.insert(pick.id)
            }
        }
        return picks
    }

    /// Re-attaches cached reasons to today's papers; anything since read or
    /// removed is dropped and replaced from the ranking.
    static func restore(_ cached: [(id: String, why: String)], in pool: PickPool) -> [Pick] {
        let numbers = cached.compactMap { entry -> (Int, String)? in
            pool.candidates.firstIndex { $0.paper.id == entry.id }.map { ($0 + 1, entry.why) }
        }
        return resolve(numbers, in: pool)
    }

    private static func reason(for candidate: PickCandidate) -> String {
        if let liked = candidate.nearestLiked {
            return "Close to “\(shorten(liked.title))”, which you engaged with"
        }
        return "Highly relevant · \(AnalyticsService.fixedTopic(for: candidate.paper))"
    }

    private static func shorten(_ title: String) -> String {
        title.count > 46 ? String(title.prefix(44)) + "…" : title
    }

    /// Keeps order, but no more than `maxPerTopic` from one topic — unless
    /// that would leave the list short, in which case the overflow fills in.
    private static func diversified(_ candidates: [PickCandidate], limit: Int) -> [PickCandidate] {
        var counts: [String: Int] = [:]
        var chosen: [PickCandidate] = []
        var overflow: [PickCandidate] = []
        for candidate in candidates {
            let topic = AnalyticsService.fixedTopic(for: candidate.paper)
            if counts[topic, default: 0] < maxPerTopic {
                counts[topic, default: 0] += 1
                chosen.append(candidate)
            } else {
                overflow.append(candidate)
            }
            if chosen.count == limit { return chosen }
        }
        return chosen + overflow.prefix(limit - chosen.count)
    }

    // MARK: Math

    private static func tasteVector(_ liked: [Paper]) -> [Double]? {
        guard let first = liked.first?.embedding, !first.isEmpty else { return nil }
        var sum = [Double](repeating: 0, count: first.count)
        for paper in liked {
            guard let embedding = paper.embedding, embedding.count == sum.count else { continue }
            let weight = tasteWeight(paper)
            let vector = unit(embedding)
            for i in vector.indices { sum[i] += weight * vector[i] }
        }
        let result = unit(sum)
        return result.contains { $0 != 0 } ? result : nil
    }

    private static func dot(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var sum = 0.0
        for i in a.indices { sum += a[i] * b[i] }
        return sum
    }

    private static func unit(_ v: [Double]) -> [Double] {
        let norm = dot(v, v).squareRoot()
        return norm > 0 ? v.map { $0 / norm } : v
    }

    /// FNV-1a — stable across launches, unlike Swift's randomized String.hashValue.
    private static func signature(liked: [Paper], candidates: [PickCandidate], personalized: Bool) -> String {
        let text = (personalized ? "P" : "C")
            + "|" + liked.map { "\($0.id):\(tasteWeight($0))" }.sorted().joined(separator: ",")
            + "|" + candidates.map { $0.paper.id }.joined(separator: ",")
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}
