import Foundation
import Observation
import os

@Observable
final class VhostStore {
    private static let logger = Logger(subsystem: "dev.mahmudz.CaddyManager", category: "VhostStore")

    private(set) var vhosts: [Vhost] = []
    var lastError: String?

    private let settings: AppSettings
    private let processController: CaddyProcessController
    private let helperInstaller: HelperInstaller
    private let helperClient: HelperClient
    private let fileManager = FileManager.default

    init(settings: AppSettings, processController: CaddyProcessController, helperInstaller: HelperInstaller, helperClient: HelperClient) {
        self.settings = settings
        self.processController = processController
        self.helperInstaller = helperInstaller
        self.helperClient = helperClient
        load()
    }

    // MARK: - Persistence paths

    static func supportDirectory() throws -> URL {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("CaddyManager", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func caddyDirectory() throws -> URL {
        let dir = try supportDirectory().appendingPathComponent("Caddy", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func vhostsFileURL() throws -> URL {
        try supportDirectory().appendingPathComponent("vhosts.json")
    }

    static func caddyfileURL() throws -> URL {
        try caddyDirectory().appendingPathComponent("Caddyfile")
    }

    // MARK: - Load / save

    func load() {
        do {
            let url = try Self.vhostsFileURL()
            guard fileManager.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            vhosts = try JSONDecoder().decode([Vhost].self, from: data)
        } catch {
            Self.logger.error("Failed to load vhosts: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    private func persist() {
        do {
            let url = try Self.vhostsFileURL()
            let data = try JSONEncoder().encode(vhosts)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Failed to save vhosts: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    // MARK: - CRUD

    @discardableResult
    func add(_ vhost: Vhost) -> [VhostValidationIssue] {
        let issues = VhostValidator.validate(vhost, existing: vhosts)
        guard !issues.contains(where: { $0.severity == .error }) else { return issues }
        vhosts.append(vhost)
        persist()
        Task { await regenerateAndReload() }
        return issues
    }

    @discardableResult
    func update(_ vhost: Vhost) -> [VhostValidationIssue] {
        let issues = VhostValidator.validate(vhost, existing: vhosts)
        guard !issues.contains(where: { $0.severity == .error }) else { return issues }
        guard let index = vhosts.firstIndex(where: { $0.id == vhost.id }) else { return issues }
        vhosts[index] = vhost
        persist()
        Task { await regenerateAndReload() }
        return issues
    }

    func delete(_ vhost: Vhost) {
        vhosts.removeAll { $0.id == vhost.id }
        persist()
        Task { await regenerateAndReload() }
    }

    func toggleEnabled(_ vhost: Vhost) {
        guard let index = vhosts.firstIndex(where: { $0.id == vhost.id }) else { return }
        vhosts[index].isEnabled.toggle()
        persist()
        Task { await regenerateAndReload() }
    }

    func toggleSSL(_ vhost: Vhost) {
        guard let index = vhosts.firstIndex(where: { $0.id == vhost.id }) else { return }
        vhosts[index].sslEnabled.toggle()
        persist()
        Task { await regenerateAndReload() }
    }

    // MARK: - Caddy sync

    func regenerateAndReload() async {
        do {
            let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: vhosts, settings: settings)
            let url = try Self.caddyfileURL()
            try caddyfile.write(to: url, atomically: true, encoding: .utf8)

            guard let binary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride) else {
                lastError = "Caddy binary not found. Install it with Homebrew: brew install caddy"
                return
            }

            if case .running = processController.status {
                try await processController.reload(caddyBinary: binary, caddyfileURL: url)
            } else {
                await processController.start(caddyBinary: binary, caddyfileURL: url)
            }
            lastError = nil
            
            if helperInstaller.isEnabled {
                do {
                    try await helperClient.syncHosts(domains: vhosts.filter(\.isEnabled).map(\.domain))
                    
                } catch {
                    Self.logger.error("Failed to sync /etc/hosts via helper: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            Self.logger.error("Failed to regenerate/reload Caddy config: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }
}
