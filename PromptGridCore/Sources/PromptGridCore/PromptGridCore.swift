//
//  PromptGridCore.swift
//  PromptGridCore
//
//  Shared model + business-logic package for the PromptGrid apps (macOS + iOS).
//  Both app targets depend on this package; all real model/document logic lives
//  here rather than in either platform's app target (see Specification §2.1).
//

// Re-export the Draw Things dependencies so a single `import PromptGridCore`
// gives callers the queue and client types (DrawThingsQueue,
// DrawThingsConfiguration, GenerationRequest, …) without a separate import.
@_exported import DrawThingsClient
@_exported import DrawThingsQueue

/// Namespace for package-wide constants. Model types (Project, Prompt, Run,
/// GenerationJob) and the request-building / wildcard logic land here in the
/// following phases.
public enum PromptGridCore {
    /// The package extension for a PromptGrid project bundle (Specification §3).
    /// Placeholder — rename alongside the app once a final name is chosen.
    public static let projectFileExtension = "pgproj"
}
