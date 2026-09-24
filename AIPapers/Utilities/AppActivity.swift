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

    @Published var isCategorizing = false
    @Published var categorizeCompleted = 0
    @Published var categorizeTotal = 0

    /// Per-paper summarize() in flight — tracked here, not view-local @State,
    /// so navigating away and back shows the real state instead of resetting
    /// to "not generating" while the call is still actually running.
    @Published var summarizingPaperIDs: Set<String> = []
    @Published var failedSummaryPaperIDs: Set<String> = []

    private var hasAutoRefreshed = false
    private var isWritingBrief = false
    private let modelContainer: ModelContainer
    private var refreshTask: Task<Void, Never>?
    private var summarizeTask: Task<Void, Never>?
    private var categorizeTask: Task<Void, Never>?

    /// Set when the launch-time pull was skipped for lack of a connection.
    private var refreshWhenOnline = false

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        LabBatch.shared.container = modelContainer
        NetworkStatus.shared.onOnline = { [weak self] in
            guard let self, self.refreshWhenOnline else { return }
            self.refreshWhenOnline = false
            self.refresh()
        }
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
            // arXiv doesn't need hitting again today, but the daily brief is a
            // separate concern — write it quietly, without a loading state.
            writeDailyBriefInBackground()
        } else if NetworkStatus.shared.isOffline {
            refreshWhenOnline = true
            writeDailyBriefInBackground()
        } else {
            refresh()
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        // Only pulling needs the network; the archive, search, Ask and the
        // rest keep working against local data and the local model.
        guard !NetworkStatus.shared.isOffline else {
            refreshErrorMessage = nil
            refreshStatusMessage = "You're offline — papers can't be pulled. Everything else still works."
            return
        }
        isRefreshing = true
        refreshErrorMessage = nil
        refreshStatusMessage = nil

        refreshTask = Task {
            let service = self.makeService()
            do {
                let result = try await service.refresh { stage in self.refreshProgressText = stage }
                if result.wasPaused {
                    self.refreshStatusMessage = "Paused — saved \(result.papersAdded) paper\(result.papersAdded == 1 ? "" : "s") so far. Resume anytime with Refresh."
                } else if result.papersAdded == 0 {
                    self.refreshStatusMessage = "No new papers found. Your archive is already up to date."
                } else {
                    self.refreshStatusMessage = "Added \(result.papersAdded) new papers."
                }
            } catch is CancellationError {
                self.refreshStatusMessage = "Paused. Resume anytime with Refresh."
            } catch let error as URLError where error.code == .cancelled {
                self.refreshStatusMessage = "Paused. Resume anytime with Refresh."
            } catch let error as ArxivServiceError {
                self.refreshErrorMessage = error.errorDescription
            } catch {
                self.refreshErrorMessage = "arXiv is unavailable. Check your connection and try again."
            }
            self.isRefreshing = false
            self.refreshProgressText = nil
            WidgetSnapshotWriter.refresh(self.modelContainer)
            self.writeDailyBriefInBackground()
        }
    }

    /// The daily trend brief is a long model call (~40s). It never blocks
    /// refresh or shows as "loading": papers are usable the moment they're saved.
    private func writeDailyBriefInBackground() {
        guard !isWritingBrief else { return }
        isWritingBrief = true
        Task {
            let service = self.makeService()
            await service.generateTrendBriefIfNeeded()
            self.isWritingBrief = false
            // Background upkeep after the brief: code/weights links for papers
            // not checked lately (newest first — those change most).
            if !NetworkStatus.shared.isOffline, let papers = try? PaperRepository(context: ModelContext(self.modelContainer)).allPapers() {
                await service.updateCodeLinks(for: papers.sorted { $0.discoveredAt > $1.discoveredAt })
            }
        }
    }

    /// Cancels the in-flight refresh. Cooperative: the running task notices
    /// at its next checkpoint (between papers, or when arXiv's request is
    /// torn down) and saves whatever it already fetched before stopping.
    func pauseRefresh() {
        refreshTask?.cancel()
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

    /// Backfills topic and subtopic for every paper that lacks them — or,
    /// with `reclassifyAll`, decides both again for every paper (e.g. after
    /// switching to a better model).
    func categorizeAll(reclassifyAll: Bool = false) {
        guard !isCategorizing else { return }
        isCategorizing = true
        categorizeCompleted = 0
        categorizeTotal = 0
        refreshErrorMessage = nil

        categorizeTask = Task {
            let context = ModelContext(self.modelContainer)
            let repository = PaperRepository(context: context)
            let service = PaperService(repository: repository)
            let everything = (try? repository.allPapers()) ?? []
            let pending = reclassifyAll ? everything : everything.filter { !AnalyticsService.isClassified($0) }

            self.categorizeTotal = pending.count
            for paper in pending {
                if Task.isCancelled { break }
                do {
                    try await service.categorize(paper, reclassify: reclassifyAll)
                } catch {
                    if !Task.isCancelled {
                        self.refreshErrorMessage = "Ollama isn't running. Start Ollama and try again."
                    }
                    break
                }
                self.categorizeCompleted += 1
            }

            self.isCategorizing = false
        }
    }

    func cancelCategorize() {
        categorizeTask?.cancel()
        isCategorizing = false
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
