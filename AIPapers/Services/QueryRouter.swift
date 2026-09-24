//
//  QueryRouter.swift
//  AIPapers
//
//  Decides what to do with a message typed into Ask: teach a general concept
//  (explain — no retrieval, no sources) or answer from the saved papers
//  (archive). A two-class logistic regression over word and bigram features,
//  trained on RouteTrainingData in a few milliseconds at first use — no model
//  call, deterministic, and fully explainable (the weights are just words).
//  Slash commands always win: /explain and /ask.
//

import Foundation

nonisolated enum QueryRoute: Equatable {
    case explain(String)
    case archive(String)
}

nonisolated struct RouteClassifier {
    private var weights: [String: Double] = [:]
    private var bias = 0.0

    static func features(_ text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
        var result = Set(words.map { "u:" + $0 })
        for pair in zip(words, words.dropFirst()) { result.insert("b:\(pair.0)_\(pair.1)") }
        if let first = words.first { result.insert("first:" + first) }
        if words.count >= 2 { result.insert("first2:\(words[0])_\(words[1])") }
        if words.count <= 3 { result.insert("short") }
        return result
    }

    /// Full-batch gradient descent with L2 — a few hundred passes over ~120 short examples.
    init(explain: [String], archive: [String], epochs: Int = 400, rate: Double = 0.5, l2: Double = 0.002) {
        let data = explain.map { (Self.features($0), 1.0) } + archive.map { (Self.features($0), 0.0) }
        for (features, _) in data { for f in features { weights[f] = 0 } }
        for _ in 0..<epochs {
            var gradient: [String: Double] = [:]
            var biasGradient = 0.0
            for (features, label) in data {
                let error = probability(of: features) - label
                biasGradient += error
                for f in features { gradient[f, default: 0] += error }
            }
            let n = Double(data.count)
            bias -= rate * biasGradient / n
            for (f, w) in weights { weights[f] = w - rate * (gradient[f, default: 0] / n + l2 * w) }
        }
    }

    private func probability(of features: Set<String>) -> Double {
        var z = bias
        for f in features { z += weights[f] ?? 0 }
        return 1 / (1 + exp(-z))
    }

    /// Probability that the message is a request to explain a general concept.
    func probabilityExplain(_ text: String) -> Double { probability(of: Self.features(text)) }
}

nonisolated enum QueryRouter {
    private static let classifier = RouteClassifier(explain: RouteTrainingData.explain, archive: RouteTrainingData.archive)

    static func route(_ message: String) -> QueryRoute {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.hasPrefix("/explain") { return .explain(String(text.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)) }
        if lower.hasPrefix("/ask") { return .archive(String(text.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)) }
        return classifier.probabilityExplain(text) >= 0.5 ? .explain(text) : .archive(text)
    }

    static func accuracy(explain: [String], archive: [String]) -> Double {
        let hits = explain.filter { if case .explain = route($0) { true } else { false } }.count
            + archive.filter { if case .archive = route($0) { true } else { false } }.count
        return Double(hits) / Double(explain.count + archive.count)
    }
}
