//
//  NetworkStatus.swift
//  AIPapers
//
//  Offline mode. arXiv is the only remote service the app talks to — Ollama,
//  embeddings and everything else are on localhost — so "offline" only ever
//  means "can't pull papers". Offline is either real (no network path) or
//  chosen (the "Work offline" setting).
//

import Foundation
import Network
import Combine

@MainActor
final class NetworkStatus: ObservableObject {
    static let shared = NetworkStatus()

    @Published private(set) var isConnected = true
    /// Called when pulling papers becomes possible again.
    var onOnline: (() -> Void)?

    private let monitor = NWPathMonitor()
    private var wasOffline = false
    private var defaultsObserver: NSObjectProtocol?

    var isForcedOffline: Bool { UserDefaults.standard.bool(forKey: AppSettingsKeys.forceOffline) }
    var isOffline: Bool { !isConnected || isForcedOffline }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.changed()
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkStatus"))
        // The setting is an @AppStorage bool; re-publish when it flips.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.changed() }
        }
        wasOffline = isOffline
    }

    private func changed() {
        objectWillChange.send()
        let offline = isOffline
        defer { wasOffline = offline }
        if wasOffline && !offline { onOnline?() }
    }
}
