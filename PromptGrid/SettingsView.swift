//
//  SettingsView.swift
//  PromptGrid
//
//  App settings: generation behavior + the device-local Draw Things server
//  address (Specification §2.3). Presented from the sidebar's gear button.
//

import SwiftUI
import PromptGridCore

/// Shared preference key: whether creating a run immediately queues generation.
/// Default off — a new run adds an empty column; the user fills it when ready.
enum GenerationPreferenceKey {
    static let autoGenerateNewRuns = "autoGenerateNewRuns"
}

struct SettingsView: View {
    @EnvironmentObject private var coordinator: GenerationCoordinator
    @Environment(\.dismiss) private var dismiss

    @AppStorage(GenerationPreferenceKey.autoGenerateNewRuns) private var autoGenerateNewRuns = false

    @State private var host = ""
    @State private var portText = ""
    @State private var useTLS = false
    @State private var sharedSecret = ""

    @State private var testOutcome: GenerationCoordinator.ConnectionOutcome?
    @State private var isTesting = false

    private var candidateSettings: ServerSettings {
        ServerSettings(
            host: host.trimmingCharacters(in: .whitespaces),
            port: Int(portText) ?? ServerSettings.defaultPort,
            useTLS: useTLS,
            sharedSecret: sharedSecret
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Generation") {
                    Toggle("Generate automatically when adding a run", isOn: $autoGenerateNewRuns)
                    Text("When on, creating a run immediately queues a generation for every prompt. When off, the run's cells start empty — use Generate or Generate Missing when you're ready.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Server") {
                    TextField("Host", text: $host, prompt: Text("e.g. 192.168.1.10"))
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
#endif
                    TextField("Port", text: $portText, prompt: Text("\(ServerSettings.defaultPort)"))
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    Toggle("Use TLS", isOn: $useTLS)
                    TextField("Shared secret (optional)", text: $sharedSecret)
                }

                Section {
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "bolt.horizontal.circle")
                            if isTesting { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)

                    switch testOutcome {
                    case .success(let message):
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .fixedSize(horizontal: false, vertical: true)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    case nil:
                        EmptyView()
                    }
                }

                if let error = coordinator.connectionError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Text("The server address is stored on this device only and is not synced. Each device points at its own Draw Things server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            host = coordinator.settings.host
            portText = String(coordinator.settings.port)
            useTLS = coordinator.settings.useTLS
            sharedSecret = coordinator.settings.sharedSecret
        }
        .frame(minWidth: 420, minHeight: 380)
    }

    private func runTest() {
        isTesting = true
        testOutcome = nil
        Task {
            let outcome = await coordinator.testConnection(candidateSettings)
            testOutcome = outcome
            isTesting = false
        }
    }

    private func save() {
        let port = Int(portText) ?? ServerSettings.defaultPort
        coordinator.updateSettings(
            ServerSettings(
                host: host.trimmingCharacters(in: .whitespaces),
                port: port,
                useTLS: useTLS,
                sharedSecret: sharedSecret
            )
        )
        dismiss()
    }
}
