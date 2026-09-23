//
//  ArchiveView.swift
//  AIPapers
//

import SwiftUI
import SwiftData

private enum SortOrder: String, CaseIterable, Identifiable {
    case relevance = "Relevance"
    case recent = "Most Recent"
    case unread = "Unread First"

    var id: String { rawValue }
}

private enum SearchMode: String, CaseIterable, Identifiable {
    case keyword = "Keyword"
    case meaning = "Meaning"

    var id: String { rawValue }
}

private enum DateFilter: String, CaseIterable, Identifiable {
    case allTime = "All Time"
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"

    var id: String { rawValue }

    func matches(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .allTime: return true
        case .today: return calendar.isDateInToday(date)
        case .thisWeek: return calendar.isDate(date, equalTo: .now, toGranularity: .weekOfYear)
        case .thisMonth: return calendar.isDate(date, equalTo: .now, toGranularity: .month)
        }
    }
}

struct ArchiveView: View {
    @Query(sort: \Paper.publishedAt, order: .reverse) private var papers: [Paper]
    @EnvironmentObject private var appActivity: AppActivity
    @Binding var selectedPaper: Paper?
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var searchMode: SearchMode = .keyword
    @State private var semanticHits: [(paper: Paper, score: Double)] = []
    @State private var isSearchingByMeaning = false
    @State private var semanticError: String?
    @State private var sortOrder: SortOrder = .recent
    @State private var topicFilter: String?
    @State private var statusFilter: ReadingStatus?
    @State private var dateFilter: DateFilter = .allTime
    @State private var unreadOnly = false
    @State private var favoritesOnly = false

    /// Topics actually present, grouped under their area — sub-categories
    /// as nested menus instead of one long flat list.
    private var topicsByArea: [(area: String, topics: [String])] {
        let present = Set(papers.map { AnalyticsService.fixedTopic(for: $0) })
        let areas = Taxonomy.areas + [Taxonomy.uncategorized]
        return areas.compactMap { area in
            let names = present.filter { Taxonomy.area(of: $0) == area }.sorted()
            return names.isEmpty ? nil : (area, names)
        }
    }

    private var isFiltering: Bool {
        topicFilter != nil || statusFilter != nil || dateFilter != .allTime || unreadOnly || favoritesOnly
    }

    private var isMeaningSearch: Bool {
        searchMode == .meaning && !searchText.isEmpty
    }

    private var matchScores: [String: Double] {
        Dictionary(semanticHits.map { ($0.paper.id, $0.score) }, uniquingKeysWith: { first, _ in first })
    }

    private var filteredPapers: [Paper] {
        var result = isMeaningSearch ? semanticHits.map(\.paper) : papers
        if !searchText.isEmpty && !isMeaningSearch {
            result = result.filter { paper in
                paper.title.localizedCaseInsensitiveContains(searchText)
                    || paper.authors.localizedCaseInsensitiveContains(searchText)
                    || (paper.category ?? "").localizedCaseInsensitiveContains(searchText)
                    || (paper.notes ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        if let topicFilter {
            result = result.filter { AnalyticsService.fixedTopic(for: $0) == topicFilter }
        }
        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        if dateFilter != .allTime {
            result = result.filter { dateFilter.matches($0.discoveredAt) }
        }
        if unreadOnly {
            result = result.filter { !$0.isRead }
        }
        if favoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        if isMeaningSearch { return result } // already ordered by how well it matches
        switch sortOrder {
        case .relevance:
            return result.sorted { $0.relevanceScore > $1.relevanceScore }
        case .recent:
            return result // already sorted by publishedAt via @Query
        case .unread:
            return result.sorted { !$0.isRead && $1.isRead }
        }
    }

    private var missingSummaryCount: Int {
        papers.filter { $0.summary == nil }.count
    }

    var body: some View {
        Group {
            if papers.isEmpty {
                ContentUnavailableView(
                    "Archive is empty",
                    systemImage: "archivebox",
                    description: Text("Papers you've seen will appear here.")
                )
            } else if isMeaningSearch && isSearchingByMeaning {
                ProgressView("Searching by meaning…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isMeaningSearch && semanticHits.isEmpty {
                ContentUnavailableView(
                    semanticError == nil ? "Search by meaning" : "Couldn't search",
                    systemImage: "text.magnifyingglass",
                    description: Text(semanticError ?? "Describe what you're looking for, then press Return — e.g. \"ways to cut KV-cache memory\".")
                )
            } else if filteredPapers.isEmpty {
                ContentUnavailableView(
                    "No matching papers",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try clearing a filter or your search term.")
                )
            } else {
                List(selection: $selectedPaper) {
                    ForEach(filteredPapers) { paper in
                        PaperRowView(paper: paper, matchScore: isMeaningSearch ? matchScores[paper.id] : nil).tag(paper)
                    }
                }
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
            }
        }
        .navigationTitle(isFiltering ? "Archive (\(filteredPapers.count) of \(papers.count))" : "Archive (\(papers.count))")
        .navigationSubtitle(isMeaningSearch && !semanticHits.isEmpty ? "Ranked by meaning" : "")
        .searchable(text: $searchText, prompt: searchMode == .meaning ? "Describe what you're looking for" : "Search papers")
        .searchScopes($searchMode) {
            ForEach(SearchMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .onSubmit(of: .search) { runMeaningSearch() }
        .onChange(of: searchText) { semanticHits = []; semanticError = nil }
        .onChange(of: searchMode) { semanticHits = []; semanticError = nil }
        .toolbar {
            ToolbarItem {
                filterMenu
            }
            ToolbarItem {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            }
            ToolbarItem {
                Button {
                    appActivity.summarizeAllMissing()
                } label: {
                    if appActivity.isSummarizingAll {
                        ProgressView()
                    } else {
                        Label("Generate Summaries (\(missingSummaryCount))", systemImage: "text.badge.plus")
                    }
                }
                .disabled(appActivity.isSummarizingAll || missingSummaryCount == 0)
            }
        }
    }

    private func runMeaningSearch() {
        guard searchMode == .meaning, !searchText.isEmpty else { return }
        let query = searchText
        isSearchingByMeaning = true
        semanticError = nil
        Task {
            let service = PaperService(repository: PaperRepository(context: modelContext))
            do {
                let hits = try await service.semanticSearch(query)
                if query == searchText { semanticHits = hits }
            } catch {
                semanticError = "Ollama isn't running, so the query couldn't be embedded. Start Ollama and try again."
            }
            isSearchingByMeaning = false
        }
    }

    private var filterMenu: some View {
        Menu {
            Section("Topic") {
                Button {
                    topicFilter = nil
                } label: {
                    if topicFilter == nil {
                        Label("All Topics", systemImage: "checkmark")
                    } else {
                        Text("All Topics")
                    }
                }
                ForEach(topicsByArea, id: \.area) { group in
                    Menu(group.area) {
                        ForEach(group.topics, id: \.self) { topic in
                            Button {
                                topicFilter = topic
                            } label: {
                                if topicFilter == topic {
                                    Label(topic, systemImage: "checkmark")
                                } else {
                                    Text(topic)
                                }
                            }
                        }
                    }
                }
            }
            Section("Reading status") {
                Picker("Reading status", selection: $statusFilter) {
                    Text("Any").tag(ReadingStatus?.none)
                    ForEach(ReadingStatus.allCases) { status in
                        Label(status.rawValue, systemImage: status.systemImage).tag(ReadingStatus?.some(status))
                    }
                }
            }
            Section("Pulled") {
                Picker("Pulled", selection: $dateFilter) {
                    ForEach(DateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            }
            Section {
                Toggle("Unread Only", isOn: $unreadOnly)
                Toggle("Favorites Only", isOn: $favoritesOnly)
            }
            if isFiltering {
                Section {
                    Button("Clear Filters", role: .destructive) {
                        topicFilter = nil
                        statusFilter = nil
                        dateFilter = .allTime
                        unreadOnly = false
                        favoritesOnly = false
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }
}
