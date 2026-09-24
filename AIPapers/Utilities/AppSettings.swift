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
    static let ollamaModel = "ollamaModel"
    static let navigationStyle = "navigationStyle"
    static let sidebarVisibleByDefault = "sidebarVisibleByDefault"
    static let hiddenSections = "hiddenSections"
    static let forceOffline = "forceOffline"
    static let askModel = "askModel"
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

    /// The model that answers Ask and /explain. Empty means "same as summarization".
    static var askModel: String {
        let stored = UserDefaults.standard.string(forKey: AppSettingsKeys.askModel)
        return (stored?.isEmpty == false) ? stored! : ollamaModel
    }

    static var ollamaModel: String {
        let stored = UserDefaults.standard.string(forKey: AppSettingsKeys.ollamaModel)
        return (stored?.isEmpty == false) ? stored! : AppConstants.ollamaModel
    }
}
