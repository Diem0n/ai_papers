//
//  LabBatch.swift
//  AIPapers
//
//  Runs one model pass over many papers (assess fit, extract claims) at the
//  App level, so it keeps going when you switch pages — same reason
//  AppActivity owns refresh. One batch at a time; cancellable.
//

import Foundation
import Combine
import SwiftData

@MainActor
final class LabBatch: ObservableObject {
    static let shared = LabBatch()

    enum Kind: String { case fit = "Assessing fit", claims = "Extracting claims" }

    @Published private(set) var kind: Kind?
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var failures = 0
    private var task: Task<Void, Never>?
    /// Set by the app at launch, so a finished batch can refresh the widget.
    var container: ModelContainer?

    var isRunning: Bool { kind != nil }

    func run(_ kind: Kind, over papers: [Paper]) {
        guard !isRunning, !papers.isEmpty else { return }
        self.kind = kind
        done = 0
        failures = 0
        total = papers.count
        task = Task {
            for paper in papers {
                if Task.isCancelled { break }
                do {
                    switch kind {
                    case .fit: try await EngineeringService.assessFit(paper)
                    case .claims: try await EngineeringService.extractClaims(paper)
                    }
                } catch {
                    failures += 1
                    // Ollama down or no stack: every remaining call would fail the same way.
                    if error is OllamaServiceError || (error as? EngineeringError) == .noStack { break }
                }
                done += 1
            }
            self.kind = nil
            if let container = self.container { WidgetSnapshotWriter.refresh(container) }
        }
    }

    func cancel() {
        task?.cancel()
    }
}
