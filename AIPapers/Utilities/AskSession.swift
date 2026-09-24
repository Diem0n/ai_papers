//
//  AskSession.swift
//  AIPapers
//
//  The Ask conversation, owned at the App level so the dashboard card and the
//  floating panel on every other page show the same thread and an in-flight
//  answer survives switching pages. Not persisted: the archive is the memory,
//  the chat is scratch. Each message is routed (QueryRouter) to either a
//  concept explanation or an answer from the saved papers.
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
        var sources: [(paper: Paper, score: Double)] = []
        var error: String?
        var isWorking = true

        /// The answer as plain text for the pasteboard (no markdown markers).
        var copyText: String? {
            answer?.replacingOccurrences(of: "**", with: "")
        }
    }

    @Published private(set) var turns: [Turn] = []

    var isBusy: Bool { turns.last?.isWorking == true }

    func ask(_ question: String, context: ModelContext) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        var turn = Turn(question: trimmed)

        let route = QueryRouter.route(trimmed)
        let query: String
        switch route {
        case .explain(let concept): query = concept; turn.isExplain = true
        case .archive(let text): query = text
        }
        guard !query.isEmpty else {
            turn.error = "Say what you're after, e.g. /explain KV cache"
            turn.isWorking = false
            turns.append(turn)
            return
        }
        turns.append(turn)

        Task {
            do {
                if turn.isExplain {
                    let text = try await OllamaService().explain(concept: query)
                    update(turn.id) { $0.answer = text; $0.isWorking = false }
                } else {
                    let service = PaperService(repository: PaperRepository(context: context))
                    let result = try await service.ask(query)
                    update(turn.id) {
                        $0.answer = result.answer
                        $0.sources = result.sources
                        $0.isWorking = false
                    }
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

    private func update(_ id: UUID, _ change: (inout Turn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }
}
