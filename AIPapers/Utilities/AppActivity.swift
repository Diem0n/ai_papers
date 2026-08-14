//
//  AppActivity.swift
//  AIPapers
//
//  Owns long-running background work (refresh, trend brief, batch
//  summarization) at the App level so it survives sidebar navigation.
//  Previously this lived in DashboardView's @State/.task, which meant
//  switching to Archive or Graph mid-refresh cancelled it outright —
//  SwiftUI tears down a view's tasks when the view leaves the hierarchy.
//  This object is owned by AIPapersApp, not any one screen, so it doesn't.
//

import Foundation
import SwiftData
import Combine
import os

private let logger = Logger(subsystem: "com.Diem0n.AIPapers", category: "AppActivity")

@MainActor
final class AppActivity: ObservableObject {
    @Published var isRefreshing = false
    @Published var refreshProgressText: String?
    @Published var refreshStatusMessage: String?
    @Published var refreshErrorMessage: String?

    @Published var isSummarizingAll = false
    @Published var summarizeCompleted = 0
    @Published var summarizeTotal = 0
    @Published var summarizeStartedAt: Date?

    /// Per-paper summarize() in flight — tracked here, not view-local @State,
    /// so navigating away and back shows the real state instead of resetting
    /// to "not generating" while the call is still actually running.
    @Published var summarizingPaperIDs: Set<String> = []
    @Published var failedSummaryPaperIDs: Set<String> = []

    private var hasAutoRefreshed = false
    private let modelContainer: ModelContainer
    private var refreshTask: Task<Void, Never>?
    private var summarizeTask: Task<Void, Never>?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private func makeService() -> PaperService {
        let context = ModelContext(modelContainer)
        return PaperService(repository: PaperRepository(context: context))
    }

    func autoRefreshIfNeeded() {
        guard !hasAutoRefreshed else { return }
        hasAutoRefreshed = true

        let context = ModelContext(modelContainer)
        let repository = PaperRepository(context: context)
        let refreshedToday = (try? repository.allPapers().contains { Calendar.current.isDateInToday($0.discoveredAt) }) ?? false

        if refreshedToday {
            // arXiv doesn't need hitting again today, but the trend brief is a
            // separate daily concern — don't let it ride on that check too.
            guard !isRefreshing else { return }
            isRefreshing = true
            refreshTask = Task {
                let service = self.makeService()
                await service.generateTrendBriefIfNeeded { stage in self.refreshProgressText = stage }
                self.isRefreshing = false
                self.refreshProgressText = nil
            }
        } else {
            refresh()
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshErrorMessage = nil
        refreshStatusMessage = nil

        refreshTask = Task {
            let service = self.makeService()
            do {
                let result = try await service.refresh { stage in self.refreshProgressText = stage }
                if result.papersAdded == 0 {
                    self.refreshStatusMessage = "No new papers found. Your archive is already up to date."
                } else {
                    self.refreshStatusMessage = "Added \(result.papersAdded) new papers."
                }
            } catch let error as ArxivServiceError {
                self.refreshErrorMessage = error.errorDescription
            } catch {
                self.refreshErrorMessage = "arXiv is unavailable. Check your connection and try again."
            }
            self.isRefreshing = false
            self.refreshProgressText = nil
        }
    }

    func summarizeAllMissing() {
        guard !isSummarizingAll else { return }
        isSummarizingAll = true
        summarizeStartedAt = .now
        summarizeCompleted = 0
        summarizeTotal = 0

        summarizeTask = Task {
            let context = ModelContext(self.modelContainer)
            let repository = PaperRepository(context: context)
            let service = PaperService(repository: repository)
            let missing = (try? repository.papersNeedingSummary()) ?? []

            self.summarizeTotal = missing.count
            for paper in missing {
                if Task.isCancelled { break }
                await service.summarize(paper)
                self.summarizeCompleted += 1
            }

            self.isSummarizingAll = false
            self.summarizeStartedAt = nil
        }
    }

    func cancelSummarizeAll() {
        summarizeTask?.cancel()
        isSummarizingAll = false
        summarizeStartedAt = nil
    }

    /// Fire-and-forget: safe to call from a view that's about to be
    /// navigated away from — the Task isn't parented to that view.
    func summarize(_ paper: Paper) {
        guard !summarizingPaperIDs.contains(paper.id) else { return }
        summarizingPaperIDs.insert(paper.id)
        failedSummaryPaperIDs.remove(paper.id)
        Task {
            let service = self.makeService()
            let success = await service.summarize(paper)
            if !success {
                self.failedSummaryPaperIDs.insert(paper.id)
            }
            self.summarizingPaperIDs.remove(paper.id)
        }
    }
}
