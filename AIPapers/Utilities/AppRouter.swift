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
