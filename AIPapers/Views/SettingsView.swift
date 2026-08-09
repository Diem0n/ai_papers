//
//  SettingsView.swift
//  AIPapers
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.maxPapersToFetch) private var maxPapersToFetch = 50
    @AppStorage(AppSettingsKeys.topicsCSV) private var topicsCSV = AppConstants.topics.joined(separator: ", ")
    @AppStorage(AppSettingsKeys.ollamaModel) private var ollamaModel = AppConstants.ollamaModel

    @State private var availableModels: [String] = []
    @State private var modelListError: String?

    var body: some View {
        Form {
            Section("Fetching") {
                Stepper("Papers per refresh: \(maxPapersToFetch)", value: $maxPapersToFetch, in: 10...200, step: 10)
            }
            Section("Summarization") {
                if availableModels.isEmpty {
                    Text(modelListError ?? "Loading installed models…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Ollama model", selection: $ollamaModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
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
        .frame(width: 420, height: 420)
        .task {
            await loadModels()
        }
    }

    private func loadModels() async {
        do {
            let models = try await OllamaService().listModels()
            availableModels = models
            if !models.contains(ollamaModel), let first = models.first {
                ollamaModel = first
            }
        } catch {
            modelListError = "Couldn't reach Ollama. Start Ollama to choose a model."
        }
    }
}

#Preview {
    SettingsView()
}
