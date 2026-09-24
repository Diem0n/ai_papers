//
//  AppRouter.swift
//  AIPapers
//
//  Routes widget taps — aipapers://paper/<id> or aipapers://trend — to the
//  right place in the app.
//

import Foundation
import Combine

@MainActor
final class AppRouter: ObservableObject {
    @Published var pendingPaperID: String?
    @Published var pendingTrendOpen = false
    @Published var pendingSection: AppSection?
    /// Bumped by the Ask command (⌘K): focuses the dashboard's Ask card, or
    /// toggles the floating panel on any other page.
    @Published var askTick = 0
    /// Bumped by AI Papers ▸ Setup Assistant… to show onboarding again.
    @Published var setupTick = 0

    func handle(_ url: URL) {
        guard url.scheme == "aipapers" else { return }
        switch url.host {
        case "paper":
            pendingPaperID = url.lastPathComponent
        case "trend":
            pendingTrendOpen = true
        default:
            break
        }
    }
}
