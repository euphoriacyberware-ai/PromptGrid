//
//  ServerSettings.swift
//  PromptGridCore
//
//  The Draw Things gRPC server address (Specification §2.3). Entered manually per
//  device and **device-local** — stored in UserDefaults, never synced via iCloud,
//  because a Mac and an iPhone typically point at different addresses.
//

import Foundation

public struct ServerSettings: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var useTLS: Bool
    public var sharedSecret: String

    /// Draw Things' default gRPC port.
    public static let defaultPort = 7859

    public init(host: String = "", port: Int = ServerSettings.defaultPort,
                useTLS: Bool = false, sharedSecret: String = "") {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.sharedSecret = sharedSecret
    }

    /// `host:port`, the form `DrawThingsService` expects.
    public var addressString: String { "\(host):\(port)" }

    public var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Persistence (device-local)

    private enum Key {
        static let host = "server.host"
        static let port = "server.port"
        static let useTLS = "server.useTLS"
        static let sharedSecret = "server.sharedSecret"
    }

    public static func load(from defaults: UserDefaults = .standard) -> ServerSettings {
        ServerSettings(
            host: defaults.string(forKey: Key.host) ?? "",
            port: defaults.object(forKey: Key.port) as? Int ?? defaultPort,
            useTLS: defaults.bool(forKey: Key.useTLS),
            sharedSecret: defaults.string(forKey: Key.sharedSecret) ?? ""
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(host, forKey: Key.host)
        defaults.set(port, forKey: Key.port)
        defaults.set(useTLS, forKey: Key.useTLS)
        defaults.set(sharedSecret, forKey: Key.sharedSecret)
    }
}
