//
//  OnboardingView.swift
//  AIPapers
//
//  Shown on first launch (and from AI Papers ▸ Setup Assistant…): get Ollama
//  and the models in place, and describe your stack so papers are judged
//  against it from the start. Nothing here leaves the Mac except model downloads.
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var setup = OllamaSetup()
    @AppStorage(AppSettingsKeys.stackProfile) private var stackProfile = ""
    @AppStorage(AppSettingsKeys.onboardingDone) private var onboardingDone = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                PixelEyeLogo(size: 40, blinkTrigger: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to AI Papers").font(.title.bold())
                    Text("Daily AI engineering research, judged against the system you run. Everything stays on your Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            step(1, "Local model", done: setup.state == .ready) { ollamaStep }
            step(2, "Your stack (optional)", done: !stackProfile.trimmingCharacters(in: .whitespaces).isEmpty) {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $stackProfile)
                        .font(.body)
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    Text("Models, serving, data, hardware, constraints — e.g. “RAG over support docs, pgvector, Llama 3.1 8B on vLLM, 800 ms p95”. Each paper gets a verdict: does it apply, what would change, how much work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Change any of this later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(setup.state == .ready ? "Start Reading" : "Skip for Now") {
                    onboardingDone = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 560)
        .task { await setup.check() }
    }

    @ViewBuilder
    private var ollamaStep: some View {
        switch setup.state {
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Looking for Ollama…").foregroundStyle(.secondary) }
        case .notRunning:
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Papers summarizes and analyses papers with Ollama, a free app that runs models on your Mac. It isn't running.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Link("Download Ollama", destination: URL(string: "https://ollama.com/download")!)
                        .buttonStyle(.bordered)
                    Button("Check Again") { Task { await setup.check() } }
                }
            }
        case .missing(let models):
            VStack(alignment: .leading, spacing: 8) {
                Text("Ollama is running. The app needs \(models.joined(separator: " and ")) — a one-time download of several GB.")
                    .fixedSize(horizontal: false, vertical: true)
                if let model = setup.pulling {
                    ProgressView(value: setup.progress) {
                        Text("Downloading \(model)… \(Int(setup.progress * 100))%").font(.caption)
                    }
                } else {
                    Button("Download Models") { Task { await setup.pullMissing() } }
                        .buttonStyle(.bordered)
                }
                if let error = setup.pullError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .ready:
            Label("Ollama is running with \(setup.required.joined(separator: " and ")).", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private func step(_ number: Int, _ title: String, done: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.15)).frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.green)
                } else {
                    Text("\(number)").font(.callout.bold()).foregroundStyle(.tint)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
        }
    }
}
