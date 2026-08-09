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
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .onOpenURL { url in
                    router.handle(url)
                }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 780)

        Settings {
            SettingsView()
        }
    }
}
