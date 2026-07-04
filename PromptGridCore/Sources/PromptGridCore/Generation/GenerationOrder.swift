//
//  GenerationOrder.swift
//  PromptGridCore
//
//  Order in which "Generate Missing" enqueues empty cells.
//

import Foundation

public enum GenerationOrder: String, Sendable, CaseIterable, Identifiable {
    /// Fill each seed (column) across all prompts before the next seed — you get
    /// a full sweep of every prompt at each seed first.
    case bySeed
    /// Fill each prompt (row) across all seeds before the next prompt — keeps the
    /// same prompt's settings/model in play run after run.
    case byPrompt

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bySeed: return "By Seed"
        case .byPrompt: return "By Prompt"
        }
    }
}
