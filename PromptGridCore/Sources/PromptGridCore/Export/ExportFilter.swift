//
//  ExportFilter.swift
//  PromptGridCore
//
//  Export-time rank filter (Specification §11): All / Final only / Final +
//  shortlisted. Chosen at export time; each option shows a live count.
//

import Foundation

public enum ExportFilter: String, CaseIterable, Sendable, Identifiable {
    case all
    case finalOnly
    case finalAndShortlisted

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .finalOnly: return "Final only"
        case .finalAndShortlisted: return "Final + shortlisted"
        }
    }

    /// Whether a completed job with this rank is included.
    public func includes(_ rank: CellRank?) -> Bool {
        switch self {
        case .all: return true
        case .finalOnly: return rank == .final
        case .finalAndShortlisted: return rank == .final || rank == .shortlisted
        }
    }
}
