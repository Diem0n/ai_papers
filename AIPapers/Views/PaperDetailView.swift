//
//  PaperDetailView.swift
//  AIPapers
//

import SwiftUI

struct PaperDetailView: View {
    @Bindable var paper: Paper

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(paper.title)
                    .font(.title2)
                    .bold()

                Text(paper.authors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label(paper.publishedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    if let category = paper.category {
                        Label(category, systemImage: "tag")
                    }
                    Label("\(Int(paper.relevanceScore * 100))% relevant", systemImage: "gauge.with.needle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                if let summary = paper.summary {
                    section("Summary", text: summary)
                }
                if let whyItMatters = paper.whyItMatters {
                    section("Why it matters", text: whyItMatters)
                }
                if paper.summary == nil {
                    Text("No summary yet. Refresh with Ollama running to generate one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                section("Abstract", text: paper.abstractText)

                HStack {
                    if let url = URL(string: paper.url) {
                        Link(destination: url) {
                            Label("Open on arXiv", systemImage: "arrow.up.right.square")
                        }
                    }
                    Spacer()
                    Toggle(isOn: $paper.isFavorite) {
                        Label("Favorite", systemImage: paper.isFavorite ? "star.fill" : "star")
                    }
                    .toggleStyle(.button)
                    Toggle(isOn: $paper.isRead) {
                        Label("Read", systemImage: paper.isRead ? "checkmark.circle.fill" : "circle")
                    }
                    .toggleStyle(.button)
                }
            }
            .padding()
        }
        .navigationTitle(paper.title)
        .onAppear { paper.isRead = true }
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text)
        }
    }
}
