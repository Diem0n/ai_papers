//
//  ReviewStore.swift
//  AIPapers
//
//  Spaced review of what you've learned: the check question from an
//  explanation (and its answer) becomes a card that comes back after 1, 3, 7,
//  16 and 35 days — a Leitner schedule. Remembering moves a card up a box;
//  forgetting sends it back to the first. Retrieval practice, spaced out, is
//  the best-supported way to keep what you've read.
//

import Foundation
import Combine

nonisolated struct ReviewCard: Codable, Identifiable, Equatable {
    let id: UUID
    let topic: String
    let question: String
    let answer: String
    var box: Int
    var due: Date
    let created: Date
}

@MainActor
final class ReviewStore: ObservableObject {
    static let shared = ReviewStore()
    static let intervals: [Double] = [1, 3, 7, 16, 35] // days

    @Published private(set) var cards: [ReviewCard]
    private let file = JSONFile<[ReviewCard]>(name: "ReviewCards.json")

    private init() {
        cards = file.load() ?? []
    }

    var due: [ReviewCard] {
        cards.filter { $0.due <= .now }.sorted { $0.due < $1.due }
    }

    func contains(question: String) -> Bool {
        cards.contains { $0.question == question }
    }

    func add(topic: String, question: String, answer: String) {
        guard !contains(question: question) else { return }
        cards.append(ReviewCard(id: UUID(), topic: topic, question: question, answer: answer, box: 0,
                                due: .now.addingTimeInterval(Self.intervals[0] * 86_400), created: .now))
        file.save(cards)
    }

    func grade(_ id: UUID, remembered: Bool) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        let box = remembered ? min(cards[i].box + 1, Self.intervals.count - 1) : 0
        cards[i].box = box
        cards[i].due = Self.nextDue(box: box, remembered: remembered)
        file.save(cards)
    }

    func remove(_ id: UUID) {
        cards.removeAll { $0.id == id }
        file.save(cards)
    }

    /// Forgotten cards come back in ten minutes, within the same sitting.
    nonisolated static func nextDue(box: Int, remembered: Bool, from now: Date = .now) -> Date {
        remembered ? now.addingTimeInterval(intervals[box] * 86_400) : now.addingTimeInterval(600)
    }
}
