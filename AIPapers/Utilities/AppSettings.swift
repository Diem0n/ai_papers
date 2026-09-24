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
    static let includeHuggingFace = "includeHuggingFace"
    static let stackProfile = "stackProfile"
    static let onboardingDone = "onboardingDone"
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

    /// Hugging Face daily papers alongside arXiv. On unless turned off.
    static var includeHuggingFace: Bool {
        UserDefaults.standard.object(forKey: AppSettingsKeys.includeHuggingFace) as? Bool ?? true
    }

    /// A free-text description of the reader's own system, for "does this apply to me".
    static var stackProfile: String {
        (UserDefaults.standard.string(forKey: AppSettingsKeys.stackProfile) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
