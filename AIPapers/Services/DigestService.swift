//
//  DigestService.swift
//  AIPapers
//
//  The deterministic half of the weekly digest. Instead of asking a language
//  model to free-write "the trends" (a 450-word wall of prose), this finds
//  them with plain data science over what's already stored:
//
//    - k-means over the paper embeddings           -> themes
//    - taxonomy mode + TF-IDF over title/abstract   -> a label and distinctive keywords per theme
//    - recent vs. older document frequency (lift)   -> rising terms
//    - nearest-neighbour isolation                  -> "wildcard" papers unlike anything else
//
//  The model is only asked, elsewhere, to put a sentence or two of plain
//  language on each theme. Pure functions, no I/O — fast enough to run in a view.
//

import Foundation
import NaturalLanguage

struct DigestTheme: Identifiable {
    let id: Int
    let topic: String
    let subtopic: String?
    let keywords: [String]
    /// Most representative (closest to the theme's centre) first.
    let papers: [Paper]
    /// Papers on this theme in the window before; nil when there was no earlier window to compare.
    let priorCount: Int?

    var label: String { subtopic.map { "\(topic) · \($0)" } ?? topic }
    var representative: Paper { papers[0] }
}

struct RisingTerm: Identifiable {
    let term: String
    let recentCount: Int
    let lift: Double
    var id: String { term }
}

struct Digest {
    let themes: [DigestTheme]
    let risingTerms: [RisingTerm]
    let wildcards: [Paper]
    let readingPlan: [Paper]
    let windowStart: Date
    let windowEnd: Date
    let paperCount: Int
    /// Changes exactly when the set of papers in the window changes — the
    /// cache key for the model-written text, so it's never regenerated needlessly.
    let signature: String
}

enum DigestService {
    static func build(_ all: [Paper], windowDays: Int = 7) -> Digest? {
        let embedded = all.filter { $0.embedding != nil }
        guard let newest = embedded.map(\.discoveredAt).max() else { return nil }

        let calendar = Calendar.current
        let windowOpen = calendar.date(byAdding: .day, value: -windowDays, to: newest) ?? newest
        var recent = embedded.filter { $0.discoveredAt >= windowOpen }
        var older = embedded.filter { $0.discoveredAt < windowOpen }
        // A window with only a handful of papers can't show a trend: fall back
        // to the newest batch instead.
        if recent.count < 12 {
            let newestFirst = embedded.sorted { $0.discoveredAt > $1.discoveredAt }
            recent = Array(newestFirst.prefix(40))
            older = Array(newestFirst.dropFirst(40))
        }
        guard recent.count >= 6, let windowStart = recent.map(\.discoveredAt).min() else { return nil }

        let priorStart = calendar.date(byAdding: .day, value: -windowDays, to: windowStart) ?? windowStart
        let prior = older.filter { $0.discoveredAt >= priorStart }

        let vectors = recent.map { unit($0.embedding ?? []) }
        let clusters = cluster(vectors, relevance: recent.map(\.relevanceScore))

        let docTerms = Dictionary(uniqueKeysWithValues: all.map { ($0.id, terms(in: "\($0.title) \($0.abstractText)")) })
        var documentFrequency: [String: Int] = [:]
        for set in docTerms.values { for term in set { documentFrequency[term, default: 0] += 1 } }

        let themes: [DigestTheme] = clusters.prefix(5).enumerated().map { index, cluster in
            let members = cluster.members
                .sorted { dot(vectors[$0], cluster.centroid) > dot(vectors[$1], cluster.centroid) }
                .map { recent[$0] }
            let (topic, subtopic) = dominantLabel(of: members)
            let priorCount: Int? = prior.isEmpty ? nil : prior.filter { paper in
                dot(unit(paper.embedding ?? []), cluster.centroid) >= 0.55
            }.count
            return DigestTheme(
                id: index,
                topic: topic,
                subtopic: subtopic,
                keywords: distinctiveTerms(of: members, docTerms: docTerms, frequency: documentFrequency, total: all.count),
                papers: members,
                priorCount: priorCount
            )
        }

        return Digest(
            themes: themes,
            risingTerms: risingTerms(recent: recent, older: older, docTerms: docTerms),
            wildcards: wildcards(recent: recent, vectors: vectors),
            readingPlan: readingPlan(themes: themes, recent: recent),
            windowStart: windowStart,
            windowEnd: newest,
            paperCount: recent.count,
            signature: signature(of: recent.map(\.id))
        )
    }

    // MARK: Clustering

    private struct Cluster {
        var members: [Int]
        var centroid: [Double]
    }

    /// Deterministic k-means: farthest-first seeding (starting from the most
    /// relevant paper) so the same papers always yield the same themes.
    private static func cluster(_ vectors: [[Double]], relevance: [Double]) -> [Cluster] {
        let n = vectors.count
        let k = min(6, max(3, Int((Double(n) / 2).squareRoot().rounded())))

        var seeds = [relevance.enumerated().max { $0.element < $1.element }?.offset ?? 0]
        while seeds.count < k {
            let next = (0..<n)
                .filter { !seeds.contains($0) }
                .min { lhs, rhs in
                    seeds.map { dot(vectors[lhs], vectors[$0]) }.max()! < seeds.map { dot(vectors[rhs], vectors[$0]) }.max()!
                }
            guard let next else { break }
            seeds.append(next)
        }

        var centroids = seeds.map { vectors[$0] }
        var assignment = [Int](repeating: 0, count: n)
        for _ in 0..<25 {
            var changed = false
            for i in 0..<n {
                let best = centroids.indices.max { dot(vectors[i], centroids[$0]) < dot(vectors[i], centroids[$1]) }!
                if assignment[i] != best { assignment[i] = best; changed = true }
            }
            for c in centroids.indices {
                let members = (0..<n).filter { assignment[$0] == c }
                if !members.isEmpty { centroids[c] = unit(mean(members.map { vectors[$0] })) }
            }
            if !changed { break }
        }

        var clusters = centroids.indices.map { c in
            Cluster(members: (0..<n).filter { assignment[$0] == c }, centroid: centroids[c])
        }.filter { !$0.members.isEmpty }

        // A theme of one or two papers isn't a theme: fold those into the nearest real one.
        let big = clusters.filter { $0.members.count >= 3 }
        if !big.isEmpty && big.count < clusters.count {
            var merged = big
            for small in clusters where small.members.count < 3 {
                for member in small.members {
                    let target = merged.indices.max { dot(vectors[member], merged[$0].centroid) < dot(vectors[member], merged[$1].centroid) }!
                    merged[target].members.append(member)
                }
            }
            clusters = merged
        }
        return clusters.sorted { $0.members.count > $1.members.count }
    }

    private static func dominantLabel(of members: [Paper]) -> (topic: String, subtopic: String?) {
        let topics = members.map { AnalyticsService.fixedTopic(for: $0) }.filter { $0 != Taxonomy.uncategorized }
        let topic = mode(of: topics) ?? Taxonomy.uncategorized
        let subtopics = members
            .filter { AnalyticsService.fixedTopic(for: $0) == topic }
            .compactMap(\.subtopic)
            .filter { $0 != Taxonomy.otherSubtopic && $0 != Taxonomy.unclassifiedSubtopic }
        return (topic, mode(of: subtopics))
    }

    private static func mode(of values: [String]) -> String? {
        let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        return counts.max { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key }?.key
    }

    // MARK: Terms

    /// TF-IDF flavoured: terms that appear in several of this theme's papers
    /// but in a small share of the whole archive.
    private static func distinctiveTerms(of members: [Paper], docTerms: [String: Set<String>], frequency: [String: Int], total: Int) -> [String] {
        var inCluster: [String: Int] = [:]
        for paper in members { for term in docTerms[paper.id] ?? [] { inCluster[term, default: 0] += 1 } }

        let scored = inCluster.compactMap { term, count -> (String, Double)? in
            let df = frequency[term] ?? 1
            guard count >= 2, Double(df) / Double(total) <= 0.2 else { return nil }
            // A phrase says more than a lone word.
            let phraseBonus = term.contains(" ") ? 1.6 : 1.0
            return (term, Double(count) * log(Double(total) / Double(df)) * phraseBonus)
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }

        var chosen: [String] = []
        for (term, _) in scored {
            // Skip anything that shares a word with one already chosen — "large
            // language" and "language models" say the same thing twice.
            let words = Set(term.split(separator: " "))
            if chosen.contains(where: { !Set($0.split(separator: " ")).isDisjoint(with: words) }) { continue }
            chosen.append(term)
            if chosen.count == 4 { break }
        }
        return chosen
    }

    private static func risingTerms(recent: [Paper], older: [Paper], docTerms: [String: Set<String>]) -> [RisingTerm] {
        guard !older.isEmpty else { return [] }
        var recentCounts: [String: Int] = [:]
        var olderCounts: [String: Int] = [:]
        for paper in recent { for term in docTerms[paper.id] ?? [] { recentCounts[term, default: 0] += 1 } }
        for paper in older { for term in docTerms[paper.id] ?? [] { olderCounts[term, default: 0] += 1 } }

        let nRecent = Double(recent.count), nOlder = Double(older.count)
        let recentTitles = recent.map { $0.title.lowercased() }
        let scored = recentCounts.compactMap { term, r -> (RisingTerm, Double)? in
            guard r >= 3 else { return nil }
            // Lone words must show up in a title to count — titles carry the precise vocabulary.
            guard term.contains(" ") || recentTitles.contains(where: { $0.contains(term) }) else { return nil }
            let lift = (Double(r) / nRecent) / ((Double(olderCounts[term] ?? 0) + 1) / (nOlder + 1))
            guard lift >= 1.5 else { return nil }
            return (RisingTerm(term: term, recentCount: r, lift: lift), lift * log(1 + Double(r)))
        }.sorted { $0.1 > $1.1 }

        var kept: [RisingTerm] = []
        for (term, _) in scored {
            if kept.contains(where: { $0.term.contains(term.term) || term.term.contains($0.term) }) { continue }
            kept.append(term)
            if kept.count == 8 { break }
        }
        return kept
    }

    // Words that carry no topic, plus the filler academic abstracts are made of.
    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "are", "was", "were", "has", "have", "had", "not", "but", "can", "our", "their",
        "its", "which", "these", "those", "such", "than", "then", "also", "into", "over", "under", "between", "across", "both", "each",
        "more", "most", "less", "other", "while", "where", "when", "how", "why", "what", "who", "whose", "using", "used", "use", "uses",
        "based", "via", "per", "may", "might", "will", "would", "could", "should", "however", "thus", "hence", "within", "without",
        "paper", "propose", "proposed", "proposes", "present", "presents", "introduce", "introduces", "introduced", "show", "shows",
        "shown", "demonstrate", "demonstrates", "achieve", "achieves", "novel", "new", "approach", "method", "methods", "results",
        "result", "existing", "recent", "work", "works", "study", "studies", "task", "tasks", "problem", "problems", "different",
        "several", "various", "further", "first", "second", "well", "high", "low", "many", "much", "among", "through",
        "often", "including", "include", "includes", "enable", "enables", "allow", "allows", "improve", "improves", "improved",
        "significantly", "effective", "effectively", "extensive", "experiments", "experimental", "evaluate", "evaluated",
        "state", "art", "outperforms", "compared",
        "provide", "provides", "particularly", "specifically", "addition", "et", "al",
        "http", "https", "www", "github", "com", "org", "arxiv", "code", "available", "publicly",
    ]

    /// Technical terms only: nouns, and adjective/noun + noun phrases.
    /// Part-of-speech tagging is what keeps filler like "instead", "because"
    /// or "emerge" out — a stopword list alone is whack-a-mole. A stopword or
    /// a non-noun breaks a phrase.
    private static func terms(in text: String) -> Set<String> {
        enum Kind { case noun, adjective, other }
        let lowered = text.lowercased()
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = lowered

        var tokens: [(word: String, kind: Kind)] = []
        tagger.enumerateTags(in: lowered.startIndex..<lowered.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation, .omitOther]) { tag, range in
            let word = String(lowered[range])
            let usable = word.count >= 3 && !word.allSatisfy(\.isNumber) && !stopwords.contains(word)
            let kind: Kind = !usable ? .other : (tag == .noun ? .noun : (tag == .adjective ? .adjective : .other))
            tokens.append((word, kind))
            return true
        }

        var result = Set<String>()
        for (index, token) in tokens.enumerated() {
            if token.kind == .noun { result.insert(token.word) }
            if token.kind != .other, index + 1 < tokens.count, tokens[index + 1].kind == .noun {
                result.insert("\(token.word) \(tokens[index + 1].word)")
            }
        }
        return result
    }

    // MARK: Picks

    /// Papers unlike anything else in the window: lowest nearest-neighbour similarity.
    private static func wildcards(recent: [Paper], vectors: [[Double]]) -> [Paper] {
        let isolation = vectors.indices.map { i in
            vectors.indices.filter { $0 != i }.map { dot(vectors[i], vectors[$0]) }.max() ?? 1
        }
        return isolation.enumerated()
            .sorted { $0.element < $1.element }
            .prefix(2)
            .map { recent[$0.offset] }
    }

    /// Up to three unread papers worth starting with: the best representative
    /// of each of the biggest themes, then the highest-relevance leftovers.
    private static func readingPlan(themes: [DigestTheme], recent: [Paper]) -> [Paper] {
        var plan: [Paper] = []
        for theme in themes {
            let pick = theme.papers.prefix(3).filter { !$0.isRead }.max { $0.relevanceScore < $1.relevanceScore }
            if let pick, !plan.contains(where: { $0.id == pick.id }) { plan.append(pick) }
            if plan.count == 3 { return plan }
        }
        for paper in recent.filter({ !$0.isRead }).sorted(by: { $0.relevanceScore > $1.relevanceScore }) {
            if !plan.contains(where: { $0.id == paper.id }) { plan.append(paper) }
            if plan.count == 3 { break }
        }
        return plan
    }

    // MARK: Math

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

    private static func mean(_ vectors: [[Double]]) -> [Double] {
        guard let first = vectors.first else { return [] }
        var sum = [Double](repeating: 0, count: first.count)
        for v in vectors { for i in v.indices { sum[i] += v[i] } }
        return sum.map { $0 / Double(vectors.count) }
    }

    /// FNV-1a — stable across launches, unlike Swift's randomized String.hashValue.
    private static func signature(of ids: [String]) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in ids.sorted().joined(separator: "|").utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return String(hash, radix: 16)
    }
}
