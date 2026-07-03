//
//  ContentView.swift
//  PromptGrid
//
//  Created by Brian Cantin on 2026-07-03.
//

import SwiftUI
import PromptGridCore

/// Top-level library shell: a sidebar listing projects and a detail pane for the
/// selected project (Specification §2.2, §6). Both are placeholders for now —
/// the library scan (Phase 3) and grid (Phase 4) fill them in.
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("No projects yet")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("PromptGrid")
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
#endif
        } detail: {
            ContentUnavailableView(
                "Select a project",
                systemImage: "square.grid.3x3",
                description: Text("Create or choose a project to see its prompt grid.")
            )
        }
    }
}

#Preview {
    ContentView()
}
