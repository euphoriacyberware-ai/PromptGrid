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
    @StateObject private var coordinator: GenerationCoordinator

    init() {
        // Pre-warm Network.framework to avoid a recursive os_unfair_lock crash in
        // networkd_settings on macOS 26.4.x when URLSession and SwiftNIO/gRPC perform
        // first-time setup concurrently. Firing this before any gRPC setup serializes
        // the two, which is what keeps the Draw Things server from crashing mid-stream.
        // (Matches the LoRAForge app.)
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:0/_warmup")!) { _, _, _ in }.resume()
        _coordinator = StateObject(wrappedValue: GenerationCoordinator())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}
