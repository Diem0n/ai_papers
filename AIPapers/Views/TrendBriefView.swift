//
//  TrendBriefView.swift
//  AIPapers
//
//  The full "where is the field heading" narrative — generated once a day
//  in PaperService, this view only reads and displays it.
//

import SwiftUI

struct TrendBriefView: View {
    @State private var brief: TrendBrief?

    var body: some View {
        ScrollView {
            if let brief {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Industry Trend Brief")
                        .font(.title2)
                        .bold()

                    HStack(spacing: 16) {
                        Label(brief.generatedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        Label("Based on \(brief.paperCount) papers", systemImage: "doc.text.magnifyingglass")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider()

                    Text(brief.content)
                        .lineSpacing(4)
                }
                .padding(24)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView(
                    "No brief yet",
                    systemImage: "text.book.closed",
                    description: Text("Refresh to generate today's industry trend brief.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Trend Brief")
        .onAppear { brief = TrendBriefStore.loadLatest() }
    }
}
