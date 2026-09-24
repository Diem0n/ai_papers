//
//  SettingsView.swift
//  AIPapers
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.maxPapersToFetch) private var maxPapersToFetch = 50
    @AppStorage(AppSettingsKeys.topicsCSV) private var topicsCSV = AppConstants.topics.joined(separator: ", ")
    @AppStorage(AppSettingsKeys.ollamaModel) private var ollamaModel = AppConstants.ollamaModel

    @AppStorage(AppSettingsKeys.navigationStyle) private var navigationStyleRaw = NavigationStyle.sidebar.rawValue
    @AppStorage(AppSettingsKeys.sidebarVisibleByDefault) private var sidebarVisibleByDefault = true
    @AppStorage(AppSettingsKeys.hiddenSections) private var hiddenSectionsCSV = ""
    @AppStorage(AppSettingsKeys.forceOffline) private var forceOffline = false
    @AppStorage(AppSettingsKeys.askModel) private var askModel = ""
    @AppStorage(AppSettingsKeys.includeHuggingFace) private var includeHuggingFace = true
    @AppStorage(AppSettingsKeys.stackProfile) private var stackProfile = ""

    @State private var availableModels: [String] = []
    @State private var modelListError: String?

    var body: some View {
        Form {
            Section("Your stack") {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $stackProfile)
                        .font(.body)
                        .frame(minHeight: 90)
                    if stackProfile.isEmpty {
                        Text("e.g. RAG over 2M support docs: pgvector + BM25 hybrid, Llama 3.1 8B on vLLM, 2×A100, p95 latency budget 800 ms, evals with Ragas.")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                Text("What you build and run: models, serving, data, hardware, constraints. Each paper is judged against this — does it apply, what would change, how much work. It never leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Navigation") {
                Picker("Layout", selection: $navigationStyleRaw) {
                    ForEach(NavigationStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                Toggle("Show sidebar by default", isOn: $sidebarVisibleByDefault)
                    .disabled(navigationStyleRaw == NavigationStyle.tabs.rawValue)
                Text(navigationStyleRaw == NavigationStyle.tabs.rawValue
                     ? "Top tabs replace the sidebar: switch pages from the toolbar, or with \u{2318}1\u{2013}5."
                     : "Keep the sidebar open, or switch to top tabs to give its width to the content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sections") {
                ForEach(AppSection.allCases) { section in
                    Toggle(isOn: visibility(of: section)) {
                        Label(section.rawValue, systemImage: section.systemImage)
                    }
                    .disabled(isOnlyVisibleSection(section))
                }
            }
            Section("Fetching") {
                Stepper("Papers per refresh: \(maxPapersToFetch)", value: $maxPapersToFetch, in: 10...200, step: 10)
                Toggle("Include Hugging Face daily papers", isOn: $includeHuggingFace)
                Text("The papers the community upvotes each day, next to the newest arXiv submissions. Code, model and dataset links come from Hugging Face either way (it took over Papers with Code's links).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Work offline", isOn: $forceOffline)
                Text("Never contact arXiv. Search, Ask, summaries and everything else run locally and keep working; only pulling new papers needs a connection (and is paused automatically when you're offline).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Section("Ask") {
                Picker("Model for Ask, /explain and Lab", selection: $askModel) {
                    Text("Same as summarization").tag("")
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Text("Also judges stack fit, extracts claims and writes implementation plans. A bigger model is more accurate but slower. Summaries, categories and picks keep using the model above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 460, height: 620)
        .task {
            await loadModels()
        }
    }

    private var hiddenSections: Set<AppSection> {
        AppSection.hidden(fromCSV: hiddenSectionsCSV)
    }

    private func visibility(of section: AppSection) -> Binding<Bool> {
        Binding(
            get: { !hiddenSections.contains(section) },
            set: { isVisible in
                var hidden = hiddenSections
                if isVisible { hidden.remove(section) } else { hidden.insert(section) }
                hiddenSectionsCSV = AppSection.csv(fromHidden: hidden)
            }
        )
    }

    /// At least one page has to stay reachable.
    private func isOnlyVisibleSection(_ section: AppSection) -> Bool {
        !hiddenSections.contains(section) && hiddenSections.count == AppSection.allCases.count - 1
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
