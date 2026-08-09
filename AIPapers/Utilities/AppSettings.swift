//
//  AppSettings.swift
//  AIPapers
//
//  User-configurable preferences, backed by UserDefaults so SettingsView's
//  @AppStorage and these reads always agree.
//

import Foundation

nonisolated enum AppSettingsKeys {
    static let maxPapersToFetch = "maxPapersToFetch"
    static let topicsCSV = "topicsCSV"
}

nonisolated enum AppSettings {
    static var maxPapersToFetch: Int {
        let stored = UserDefaults.standard.integer(forKey: AppSettingsKeys.maxPapersToFetch)
        return stored > 0 ? stored : 50
    }

    static var topics: [String] {
        guard let csv = UserDefaults.standard.string(forKey: AppSettingsKeys.topicsCSV), !csv.isEmpty else {
            return AppConstants.topics
        }
        let parsed = csv.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parsed.isEmpty ? AppConstants.topics : parsed
    }
}
