//
//  AIPapersApp.swift
//  AIPapers
//
//  Created by Talha on 09/08/2026.
//

import SwiftUI
import SwiftData

@main
struct AIPapersApp: App {
    let modelContainer = SharedModelContainer.make()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 780)

        Settings {
            SettingsView()
        }
    }
}
