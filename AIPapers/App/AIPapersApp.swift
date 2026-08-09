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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Paper.self)
    }
}
