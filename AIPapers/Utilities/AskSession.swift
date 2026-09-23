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
        var answer: String?
        var sources: [(paper: Paper, score: Double)] = []
        var error: String?
        var isWorking = true
    }

    @Published private(set) var turns: [Turn] = []

    var isBusy: Bool { turns.last?.isWorking == true }

    func ask(_ question: String, context: ModelContext) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        let turn = Turn(question: trimmed)
        turns.append(turn)

        Task {
            let service = PaperService(repository: PaperRepository(context: context))
            do {
                let result = try await service.ask(trimmed)
                update(turn.id) {
                    $0.answer = result.answer
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

    private func update(_ id: UUID, _ change: (inout Turn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }
}
