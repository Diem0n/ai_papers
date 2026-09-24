//
//  AskSession.swift
//  AIPapers
//
//  The Ask-your-archive conversation, owned at the App level so the dashboard
//  card and the floating panel on every other page show the same thread and
//  an in-flight answer survives switching pages. Not persisted: the archive
//  is the memory, the chat is scratch.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class AskSession: ObservableObject {
    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var isExplain = false
        var answer: String?
        /// For /explain: the last section, held back so the reader can try the check question first.
        var hiddenAnswer: String?
        var sources: [(paper: Paper, score: Double)] = []
        var error: String?
        var isWorking = true
    }

    @Published private(set) var turns: [Turn] = []

    var isBusy: Bool { turns.last?.isWorking == true }

    func ask(_ question: String, context: ModelContext) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        let command = "/explain"
        let isExplain = trimmed.lowercased().hasPrefix(command)
        let concept = String(trimmed.dropFirst(command.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        var turn = Turn(question: trimmed, isExplain: isExplain)
        if isExplain && concept.isEmpty {
            turn.error = "Say what to explain, e.g. /explain KV cache"
            turn.isWorking = false
            turns.append(turn)
            return
        }
        turns.append(turn)

        Task {
            let service = PaperService(repository: PaperRepository(context: context))
            do {
                let result = isExplain ? try await service.explain(concept) : try await service.ask(trimmed)
                let (body, hidden) = isExplain ? Self.splitAnswer(result.answer) : (result.answer, nil)
                update(turn.id) {
                    $0.answer = body
                    $0.hiddenAnswer = hidden
                    $0.sources = result.sources
                    $0.isWorking = false
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Couldn't answer that."
                update(turn.id) {
                    $0.error = message
                    $0.isWorking = false
                }
            }
        }
    }

    func clear() {
        guard !isBusy else { return }
        turns.removeAll()
    }

    /// **bold** labels and line breaks from an explanation; anything unparseable stays plain.
    static func formatted(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// Separates the trailing "**Answer**" section from an explanation.
    static func splitAnswer(_ text: String) -> (body: String, answer: String?) {
        guard let marker = text.range(of: "**Answer", options: .caseInsensitive) else { return (text, nil) }
        let body = text[..<marker.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = text[marker.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "*:—–- \n"))
        return (body, answer.isEmpty ? nil : answer)
    }

    private func update(_ id: UUID, _ change: (inout Turn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }
}
