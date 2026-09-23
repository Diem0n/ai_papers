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

    @State private var availableModels: [String] = []
    @State private var modelListError: String?

    var body: some View {
        Form {
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
