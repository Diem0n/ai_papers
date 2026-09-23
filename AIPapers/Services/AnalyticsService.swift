//
//  AnalyticsService.swift
//  AIPapers
//
//  Pure aggregation over the local archive — no I/O, so it's cheap to call
//  straight from a view's computed properties and easy to unit test.
//

import Foundation

enum AnalyticsService {
    struct DailyCount: Identifiable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    struct CategoryCount: Identifiable {
        let category: String
        let count: Int
        var id: String { category }
    }

    struct RelevanceBucket: Identifiable {
        let range: String
        let count: Int
        var id: String { range }
    }

    /// Topic frequency in the most recent window vs. the equal-length window
    /// before it — the simplest honest way to say "this is trending" without
    /// needing a real time-series model for a few dozen papers a day.
    struct TrendingTopic: Identifiable {
        let topic: String
        let recentCount: Int
        let priorCount: Int
        var delta: Int { recentCount - priorCount }
        var id: String { topic }
    }

    /// One column of the Sankey: 0 = area, 1 = topic, 2 = subtopic, 3 = read status.
    struct SankeyNode: Identifiable {
        let id: String
        let column: Int
        let label: String
        let area: String
        let value: Int
    }

    struct SankeyLink: Identifiable {
        let source: String
        let target: String
        let value: Int
        let area: String
        var id: String { source + ">" + target }
    }

    static func papersPerDay(_ papers: [Paper]) -> [DailyCount] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: papers) { calendar.startOfDay(for: $0.discoveredAt) }
        return grouped
            .map { DailyCount(date: $0.key, count: $0.value.count) }
            .sorted { $0.date < $1.date }
    }

    static func topCategories(_ papers: [Paper], limit: Int = 8) -> [CategoryCount] {
        let grouped = Dictionary(grouping: papers) { fixedTopic(for: $0) }
        return grouped
            .map { CategoryCount(category: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    /// The stored topic if it's already on the taxonomy (i.e. the model put
    /// it there), else nil.
    static func storedTopic(_ paper: Paper, topics: [String] = Taxonomy.names) -> String? {
        guard let category = paper.category else { return nil }
        return topics.first { $0.caseInsensitiveCompare(category) == .orderedSame }
    }

    /// True once the model has assigned both a topic and a subtopic — the
    /// condition for never sending this paper to the model again.
    static func isClassified(_ paper: Paper) -> Bool {
        storedTopic(paper) != nil && paper.subtopic != nil
    }

    static func fixedSubtopic(for paper: Paper) -> String {
        paper.subtopic ?? Taxonomy.unclassifiedSubtopic
    }

    static func fixedTopic(for paper: Paper, topics: [String] = Taxonomy.names) -> String {
        if let matched = storedTopic(paper, topics: topics) {
            return matched
        }
        let matches = RelevanceService.matchingTopics(title: paper.title, abstractText: paper.abstractText, topics: topics)
        // "LLM" appears in nearly every abstract; only fall back to it when
        // nothing more specific matched.
        if let best = matches.first(where: { $0 != "LLM" }) ?? matches.first {
            return best
        }
        return Taxonomy.uncategorized
    }

    /// Area -> Topic -> Subtopic -> Read/Unread flows, ordered so ribbons in
    /// the hierarchy columns don't cross: areas by size, topics grouped under
    /// their area, subtopics grouped under their topic, biggest first.
    static func sankey(_ papers: [Paper]) -> (nodes: [SankeyNode], links: [SankeyLink]) {
        var areaTopic: [String: [String: Int]] = [:]
        var topicSub: [String: [String: Int]] = [:]
        var subStatus: [String: [String: Int]] = [:]   // key: "topic/sub"
        var areaTotals: [String: Int] = [:]
        var topicTotals: [String: Int] = [:]
        var subTotals: [String: Int] = [:]             // key: "topic/sub"
        var statusTotals: [String: Int] = [:]
        var topicArea: [String: String] = [:]

        for paper in papers {
            let topic = fixedTopic(for: paper)
            let area = Taxonomy.area(of: topic)
            let sub = fixedSubtopic(for: paper)
            let key = "\(topic)/\(sub)"
            let status = paper.isRead ? "Read" : "Unread"
            areaTopic[area, default: [:]][topic, default: 0] += 1
            topicSub[topic, default: [:]][sub, default: 0] += 1
            subStatus[key, default: [:]][status, default: 0] += 1
            areaTotals[area, default: 0] += 1
            topicTotals[topic, default: 0] += 1
            subTotals[key, default: 0] += 1
            statusTotals[status, default: 0] += 1
            topicArea[topic] = area
        }

        let areaOrder = areaTotals.keys.sorted { areaTotals[$0]! > areaTotals[$1]! }
        let topicOrder = areaOrder.flatMap { area in
            (areaTopic[area] ?? [:]).keys.sorted { topicTotals[$0]! > topicTotals[$1]! }
        }
        let subOrder: [(topic: String, sub: String)] = topicOrder.flatMap { topic in
            (topicSub[topic] ?? [:]).keys
                .sorted { subTotals["\(topic)/\($0)"]! > subTotals["\(topic)/\($1)"]! }
                .map { (topic, $0) }
        }
        let statusOrder = ["Unread", "Read"].filter { statusTotals[$0] != nil }

        var nodes: [SankeyNode] = []
        nodes += areaOrder.map { SankeyNode(id: "a:\($0)", column: 0, label: $0, area: $0, value: areaTotals[$0]!) }
        nodes += topicOrder.map { SankeyNode(id: "t:\($0)", column: 1, label: $0, area: topicArea[$0]!, value: topicTotals[$0]!) }
        nodes += subOrder.map { SankeyNode(id: "u:\($0.topic)/\($0.sub)", column: 2, label: $0.sub, area: topicArea[$0.topic]!, value: subTotals["\($0.topic)/\($0.sub)"]!) }
        nodes += statusOrder.map { SankeyNode(id: "s:\($0)", column: 3, label: $0, area: "Status", value: statusTotals[$0]!) }

        var links: [SankeyLink] = []
        for area in areaOrder {
            for (topic, count) in areaTopic[area] ?? [:] {
                links.append(SankeyLink(source: "a:\(area)", target: "t:\(topic)", value: count, area: area))
            }
        }
        for topic in topicOrder {
            for (sub, count) in topicSub[topic] ?? [:] {
                links.append(SankeyLink(source: "t:\(topic)", target: "u:\(topic)/\(sub)", value: count, area: topicArea[topic]!))
            }
        }
        for entry in subOrder {
            let key = "\(entry.topic)/\(entry.sub)"
            for (status, count) in subStatus[key] ?? [:] {
                links.append(SankeyLink(source: "u:\(key)", target: "s:\(status)", value: count, area: topicArea[entry.topic]!))
            }
        }
        return (nodes, links)
    }

    static func relevanceDistribution(_ papers: [Paper]) -> [RelevanceBucket] {
        let labels = ["0-20%", "20-40%", "40-60%", "60-80%", "80-100%"]
        var counts = [Int](repeating: 0, count: labels.count)
        for paper in papers {
            let index = min(max(Int(paper.relevanceScore * Double(labels.count)), 0), labels.count - 1)
            counts[index] += 1
        }
        return zip(labels, counts).map { RelevanceBucket(range: $0, count: $1) }
    }

    static func trendingTopics(
        _ papers: [Paper],
        topics: [String] = AppConstants.topics,
        windowDays: Int = 7,
        now: Date = .now,
        limit: Int = 5
    ) -> [TrendingTopic] {
        let calendar = Calendar.current
        guard let recentStart = calendar.date(byAdding: .day, value: -windowDays, to: now),
              let priorStart = calendar.date(byAdding: .day, value: -windowDays * 2, to: now) else {
            return []
        }

        let recent = papers.filter { $0.discoveredAt >= recentStart }
        let prior = papers.filter { $0.discoveredAt >= priorStart && $0.discoveredAt < recentStart }

        func counts(in list: [Paper]) -> [String: Int] {
            var result: [String: Int] = [:]
            for paper in list {
                let text = "\(paper.title) \(paper.abstractText)"
                for topic in topics where text.localizedCaseInsensitiveContains(topic) {
                    result[topic, default: 0] += 1
                }
            }
            return result
        }

        let recentCounts = counts(in: recent)
        let priorCounts = counts(in: prior)

        return Set(recentCounts.keys).union(priorCounts.keys)
            .map { TrendingTopic(topic: $0, recentCount: recentCounts[$0] ?? 0, priorCount: priorCounts[$0] ?? 0) }
            .filter { $0.recentCount > 0 }
            .sorted { $0.delta > $1.delta }
            .prefix(limit)
            .map { $0 }
    }
}
