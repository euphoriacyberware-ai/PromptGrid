//
//  ConfigurationEditor.swift
//  PromptGrid
//
//  Reusable plain-text JSON editor for a DrawThingsConfiguration (Specification
//  §12): monospaced, debounce-validated, and it keeps the last valid value on a
//  bad edit. Shared by the prompt detail editor, the app generation defaults, and
//  the project generation defaults.
//

import SwiftUI
import PromptGridCore

struct ConfigurationEditor: View {
    @Binding var configuration: DrawThingsConfigurationDTO
    var minHeight: CGFloat = 200

    @State private var jsonText = ""
    @State private var jsonError: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SpellcheckedTextView(text: $jsonText, isSpellCheckingEnabled: false, isMonospaced: true)
                .frame(minHeight: minHeight)

            if let jsonError {
                Label(jsonError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Valid — the last valid configuration is kept", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }

            Text("The seed field here is ignored — each run supplies its own seed.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear {
            if !loaded { jsonText = Self.prettyJSON(configuration); loaded = true }
        }
        .task(id: jsonText) {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { validate() }
        }
    }

    private func validate() {
        do {
            let decoded = try ProjectPackage.makeDecoder()
                .decode(DrawThingsConfigurationDTO.self, from: Data(jsonText.utf8))
            configuration = decoded          // commit last-valid
            jsonError = nil
        } catch {
            jsonError = Self.friendlyMessage(error)   // keep last-valid
        }
    }

    static func prettyJSON(_ dto: DrawThingsConfigurationDTO) -> String {
        guard let data = try? ProjectPackage.makeEncoder().encode(dto),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    static func friendlyMessage(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .dataCorrupted(let context):
                return "Invalid JSON: \(context.debugDescription)"
            case .typeMismatch(_, let context), .valueNotFound(_, let context):
                let key = context.codingPath.last?.stringValue ?? "?"
                return "Wrong type for “\(key)”: \(context.debugDescription)"
            case .keyNotFound(let key, _):
                return "Missing key “\(key.stringValue)”"
            @unknown default:
                return "Invalid configuration."
            }
        }
        return "Invalid configuration."
    }
}
