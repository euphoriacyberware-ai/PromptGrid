//
//  SettingsView.swift
//  PromptGrid
//
//  App settings: generation behavior + the device-local Draw Things server
//  address (Specification §2.3). Presented from the sidebar's gear button.
//

import SwiftUI
import UniformTypeIdentifiers
import PromptGridCore

/// Shared preference key: whether creating a run immediately queues generation.
/// Default off — a new run adds an empty column; the user fills it when ready.
enum GenerationPreferenceKey {
    static let autoGenerateNewRuns = "autoGenerateNewRuns"
    static let generateMissingOrder = "generateMissingOrder"
}

struct SettingsView: View {
    let library: ProjectLibrary
    @EnvironmentObject private var coordinator: GenerationCoordinator
    @Environment(\.dismiss) private var dismiss

    @AppStorage(GenerationPreferenceKey.autoGenerateNewRuns) private var autoGenerateNewRuns = false
    @AppStorage(GenerationPreferenceKey.generateMissingOrder) private var generateMissingOrder: GenerationOrder = .bySeed

    @State private var isChoosingFolder = false
    @State private var pendingFolder: URL?
    @State private var isConfirmingUseDefault = false
    @State private var relocationMessage: String?

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

                    Picker("Generate Missing order", selection: $generateMissingOrder) {
                        ForEach(GenerationOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    Text("By Seed fills each seed across all prompts first (a full sweep at each seed). By Prompt fills each prompt across all seeds first (keeps a prompt's model in play run after run).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Library") {
                    LabeledContent("Location") {
                        Text(LibraryLocationStore.hasCustomLocation ? library.libraryURL.path(percentEncoded: false) : "Local (private)")
                            .foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle)
                    }
                    Button("Choose Folder…") { isChoosingFolder = true }
                    if LibraryLocationStore.hasCustomLocation {
                        Button("Use Default (Local)") { isConfirmingUseDefault = true }
                    }
                    if let relocationMessage {
                        Text(relocationMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Your projects and images are stored here. The default is private to this device. Choose an iCloud Drive or Dropbox folder to sync across devices — note that image libraries can be large.")
                        .font(.footnote).foregroundStyle(.secondary)
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
        .frame(minWidth: 460, minHeight: 440)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { pendingFolder = folder }
        }
        .confirmationDialog(
            "Move library to this folder?",
            isPresented: Binding(get: { pendingFolder != nil }, set: { if !$0 { pendingFolder = nil } }),
            presenting: pendingFolder
        ) { folder in
            Button("Move \(library.items.count) Project\(library.items.count == 1 ? "" : "s")") {
                relocate(to: folder, isDefault: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("Your \(library.items.count) project\(library.items.count == 1 ? "" : "s") will be moved to “\(folder.lastPathComponent)”, which becomes the library location.")
        }
        .confirmationDialog(
            "Return to the default local library?",
            isPresented: $isConfirmingUseDefault
        ) {
            Button("Move to Default") { relocate(to: ProjectLibrary.defaultLibraryURL(), isDefault: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your projects will be moved back into this device's private storage and will no longer sync.")
        }
    }

    private func relocate(to destination: URL, isDefault: Bool) {
        let scoped = !isDefault && destination.startAccessingSecurityScopedResource()
        do {
            try library.moveProjects(to: destination)
            library.relocate(to: destination)
            if isDefault {
                LibraryLocationStore.useDefault()
            } else {
                try LibraryLocationStore.setCustomLocation(destination)
            }
            relocationMessage = "Library is now at “\(destination.lastPathComponent)”."
        } catch {
            relocationMessage = "Couldn’t relocate: \(error.localizedDescription)"
            if scoped { destination.stopAccessingSecurityScopedResource() }
        }
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
