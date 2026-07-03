//
//  ServerSettingsView.swift
//  PromptGrid
//
//  Manual, device-local Draw Things server address entry (Specification §2.3).
//

import SwiftUI
import PromptGridCore

struct ServerSettingsView: View {
    @EnvironmentObject private var coordinator: GenerationCoordinator
    @Environment(\.dismiss) private var dismiss

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
                    Text("The address is stored on this device only and is not synced. Each device points at its own Draw Things server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Server Settings")
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
        .frame(minWidth: 380, minHeight: 320)
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
