//
//  PromptGridApp.swift
//  PromptGrid
//
//  Created by Brian Cantin on 2026-07-03.
//

import SwiftUI
import PromptGridCore

@main
struct PromptGridApp: App {
    // One queue/coordinator for the whole app launch (Specification §2.3).
    @StateObject private var coordinator = GenerationCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}
