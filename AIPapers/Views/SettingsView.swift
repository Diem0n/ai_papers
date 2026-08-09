//
//  SettingsView.swift
//  AIPapers
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.maxPapersToFetch) private var maxPapersToFetch = 50
    @AppStorage(AppSettingsKeys.topicsCSV) private var topicsCSV = AppConstants.topics.joined(separator: ", ")

    var body: some View {
        Form {
            Section("Fetching") {
                Stepper("Papers per refresh: \(maxPapersToFetch)", value: $maxPapersToFetch, in: 10...200, step: 10)
            }
            Section("Topics") {
                Text("Comma-separated. Used to score and tag papers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $topicsCSV)
                    .frame(minHeight: 120)
                    .font(.body)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 340)
    }
}

#Preview {
    SettingsView()
}
