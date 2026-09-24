//
//  InsightStore.swift
//  AIPapers
//
//  The engineering layer on top of each paper: does it fit your stack, what
//  does it claim, and how would you implement it (with your progress through
//  the steps). Model-generated and cached per paper in one JSON file; the fit
//  is tied to the stack description it was judged against, so editing your
//  stack marks old verdicts stale instead of silently keeping them.
//

import Foundation
import Combine

nonisolated struct StackFit: Codable, Equatable {
    enum Verdict: String, Codable, CaseIterable { case applies, maybe, no }
    enum Effort: String, Codable, CaseIterable { case config, code, retrain, research }

    let verdict: Verdict
    let why: String
    let change: String
    let effort: Effort
    let stackSignature: String
    let generatedAt: Date
}

nonisolated struct PaperClaim: Codable, Equatable, Identifiable {
    let text: String
    let benchmark: String?
    let metric: String?
    let value: String?
    let baseline: String?
    var id: String { text }
}

nonisolated struct ImplementationPlan: Codable, Equatable {
    struct Step: Codable, Equatable {
        let title: String
        let detail: String
    }
    let prerequisites: [String]
    let steps: [Step]
    let success: String
    let risks: [String]
    let usedFullText: Bool
    let generatedAt: Date
}

nonisolated struct PaperInsights: Codable, Equatable {
    var fit: StackFit?
    var claims: [PaperClaim]?
    var plan: ImplementationPlan?
    var planDone: Set<Int> = []
}

@MainActor
final class InsightStore: ObservableObject {
    static let shared = InsightStore()

    @Published private(set) var insights: [String: PaperInsights]
    /// Paper ids with a model call in flight, per kind — for spinners.
    @Published private(set) var working: Set<String> = []

    private let file = JSONFile<[String: PaperInsights]>(name: "Insights.json")

    private init() {
        insights = file.load() ?? [:]
    }

    func update(_ id: String, _ change: (inout PaperInsights) -> Void) {
        var value = insights[id] ?? PaperInsights()
        change(&value)
        insights[id] = value
        file.save(insights)
    }

    func setWorking(_ key: String, _ on: Bool) {
        if on { working.insert(key) } else { working.remove(key) }
    }

    func isWorking(_ kind: String, _ id: String) -> Bool { working.contains("\(kind):\(id)") }

    /// The fit, only if it was judged against the stack as it's described now.
    func currentFit(_ id: String) -> StackFit? {
        guard let fit = insights[id]?.fit, fit.stackSignature == EngineeringService.stackSignature() else { return nil }
        return fit
    }
}
