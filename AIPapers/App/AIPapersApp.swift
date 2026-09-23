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
    let modelContainer: ModelContainer
    @StateObject private var router = AppRouter()
    @StateObject private var appActivity: AppActivity

    init() {
        // Built once here (not as two separate default-initialized properties)
        // so the .modelContainer environment and AppActivity's background
        // contexts share the exact same container, not two separate ones
        // pointed at the same file.
        let container = SharedModelContainer.make()
        modelContainer = container
        _appActivity = StateObject(wrappedValue: AppActivity(modelContainer: container))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .environmentObject(appActivity)
                .onOpenURL { url in
                    router.handle(url)
                }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandMenu("Go") {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.rawValue) { router.pendingSection = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}
