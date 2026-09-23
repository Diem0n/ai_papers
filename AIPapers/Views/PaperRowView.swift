//
//  PaperRowView.swift
//  AIPapers
//
//  Dense, scannable row: monospace for scan-able data (category, relevance,
//  dates), system font for the human-readable parts (title, authors).
//

import SwiftUI

struct PaperRowView: View {
    let paper: Paper

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RelevanceBar(score: paper.relevanceScore)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(paper.title)
                        .font(.headline)
                        .lineLimit(2)
                    if paper.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                    Spacer(minLength: 8)
                    if !paper.isRead {
                        Circle()
                            .fill(.tint)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(paper.authors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(Int(paper.relevanceScore * 100))%")
                        .foregroundStyle(.tint)
                    Text("·")
                    Text(AnalyticsService.fixedTopic(for: paper).uppercased())
                    Text("·")
                    Text(paper.summary == nil ? "no summary" : "summarized")
                    Text("·")
                    Text(paper.discoveredAt.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .opacity(paper.isRead ? 0.7 : 1.0)
    }
}

/// A compact vertical meter — quicker to scan at a glance across a long list
/// than reading a percentage for every row.
private struct RelevanceBar: View {
    let score: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(.tertiary)
            .frame(width: 3, height: 32)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tint)
                    .frame(width: 3, height: 32 * min(max(score, 0), 1))
            }
    }
}
