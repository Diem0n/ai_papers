//
//  AppRouter.swift
//  AIPapers
//
//  Routes widget taps (aipapers://paper/<id>) to the right detail view.
//

import Foundation
import Combine

@MainActor
final class AppRouter: ObservableObject {
    @Published var pendingPaperID: String?

    func handle(_ url: URL) {
        guard url.scheme == "aipapers", url.host == "paper" else { return }
        pendingPaperID = url.lastPathComponent
    }
}
