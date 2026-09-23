//
//  AnalyticsView.swift
//  AIPapers
//
//  Mines the local archive for patterns instead of just listing papers —
//  ingestion volume over time, category mix, relevance distribution, and
//  simple week-over-week topic trend detection.
//

import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Query private var papers: [Paper]
    @EnvironmentObject private var appActivity: AppActivity
    @State private var confirmRecategorize = false

    private var uncategorizedCount: Int {
        papers.filter { !AnalyticsService.isClassified($0) }.count
    }

    private var dailyCounts: [AnalyticsService.DailyCount] {
        AnalyticsService.papersPerDay(papers)
    }
    private var topCategories: [AnalyticsService.CategoryCount] {
        AnalyticsService.topCategories(papers)
    }
    private var sankey: (nodes: [AnalyticsService.SankeyNode], links: [AnalyticsService.SankeyLink]) {
        AnalyticsService.sankey(papers)
    }
    private var relevanceBuckets: [AnalyticsService.RelevanceBucket] {
        AnalyticsService.relevanceDistribution(papers)
    }
    private var trending: [AnalyticsService.TrendingTopic] {
        AnalyticsService.trendingTopics(papers)
    }

    private var uniqueDays: Int {
        Set(papers.map { Calendar.current.startOfDay(for: $0.discoveredAt) }).count
    }

    var body: some View {
        Group {
            if papers.isEmpty {
                ContentUnavailableView(
                    "Nothing to analyze yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Refresh to start building up history.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        statsRow

                        chartSection("Flow: Area → Topic → Subtopic → Read Status") {
                            SankeyView(nodes: sankey.nodes, links: sankey.links)
                        }

                        chartSection("Papers Pulled Over Time") {
                            Chart(dailyCounts) { day in
                                BarMark(x: .value("Date", day.date, unit: .day), y: .value("Papers", day.count))
                                    .foregroundStyle(.tint)
                            }
                            .frame(height: 180)
                        }

                        HStack(alignment: .top, spacing: 28) {
                            chartSection("Top Topics") {
                                Chart(topCategories) { item in
                                    BarMark(x: .value("Count", item.count), y: .value("Category", item.category), height: .ratio(0.6))
                                        .foregroundStyle(.tint)
                                }
                                .frame(height: CGFloat(topCategories.count * 28 + 20))
                            }
                            .frame(maxWidth: .infinity)

                            chartSection("Relevance Distribution") {
                                Chart(relevanceBuckets) { bucket in
                                    BarMark(x: .value("Range", bucket.range), y: .value("Count", bucket.count))
                                        .foregroundStyle(.tint)
                                }
                                .frame(height: CGFloat(topCategories.count * 28 + 20))
                            }
                            .frame(maxWidth: .infinity)
                        }

                        trendingSection
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle("Analytics")
        .toolbar {
            ToolbarItem {
                categorizeButton
            }
        }
    }

    @ViewBuilder
    private var categorizeButton: some View {
        if appActivity.isCategorizing {
            Button {
                appActivity.cancelCategorize()
            } label: {
                Label("Stop Categorizing", systemImage: "stop.fill")
            }
        } else {
            Menu {
                Button("Categorize new papers (\(uncategorizedCount))") {
                    appActivity.categorizeAll()
                }
                .disabled(uncategorizedCount == 0)
                Button("Re-categorize all \(papers.count) papers…") {
                    confirmRecategorize = true
                }
            } label: {
                Label("Categorize with LLM", systemImage: "tag")
            }
            .confirmationDialog(
                "Re-categorize all \(papers.count) papers with \(AppSettings.ollamaModel)?",
                isPresented: $confirmRecategorize,
                titleVisibility: .visible
            ) {
                Button("Re-categorize All", role: .destructive) {
                    appActivity.categorizeAll(reclassifyAll: true)
                }
            } message: {
                Text("This replaces every stored topic and subtopic and takes a few minutes. Your papers, notes and read state aren't touched.")
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 28) {
            stat("\(papers.count)", "total papers")
            stat("\(papers.filter { !$0.isRead }.count)", "unread")
            stat("\(summarizedPercent)%", "summarized")
            stat("\(uniqueDays)", "days of activity")
        }
    }

    private var summarizedPercent: Int {
        guard !papers.isEmpty else { return 0 }
        return Int(Double(papers.filter { $0.summary != nil }.count) / Double(papers.count) * 100)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .monospaced, weight: .bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chartSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title)
            content()
        }
    }

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Trending Topics (Last 7 Days vs. Prior 7)")
            if trending.isEmpty {
                Text("Not enough history yet to detect trends.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trending) { topic in
                    HStack {
                        Text(topic.topic.uppercased())
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Image(systemName: topic.delta > 0 ? "arrow.up.right" : (topic.delta < 0 ? "arrow.down.right" : "minus"))
                            .foregroundStyle(topic.delta > 0 ? .green : (topic.delta < 0 ? .red : .secondary))
                        Text("\(topic.recentCount) (\(topic.delta >= 0 ? "+" : "")\(topic.delta))")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}
