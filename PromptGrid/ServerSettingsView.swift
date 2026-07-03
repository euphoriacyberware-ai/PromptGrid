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
