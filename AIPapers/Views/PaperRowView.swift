//
//  PaperRowView.swift
//  AIPapers
//

import SwiftUI

struct PaperRowView: View {
    let paper: Paper

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(paper.title)
                        .font(.headline)
                        .lineLimit(2)
                    if paper.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }
                Text(paper.authors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let category = paper.category {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.tertiary, in: Capsule())
                    }
                    if paper.summary == nil {
                        Label("No summary", systemImage: "text.badge.xmark")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            if !paper.isRead {
                Circle()
                    .fill(.tint)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .opacity(paper.isRead ? 0.65 : 1.0)
    }
}
