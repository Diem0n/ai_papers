//
//  PaperRowView.swift
//  AIPapers
//

import SwiftUI

struct PaperRowView: View {
    let paper: Paper

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
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
                if let category = paper.category {
                    Text(category)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tertiary, in: Capsule())
                }
            }
            Spacer()
            if !paper.isRead {
                Circle()
                    .fill(.tint)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
        .opacity(paper.isRead ? 0.65 : 1.0)
    }
}
