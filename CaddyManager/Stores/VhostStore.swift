import Foundation
import Observation

@Observable
final class VhostStore {
    private static let logger = AppLogger(category: "VhostStore")

    private(set) var vhosts: [Vhost] = []
    var lastError: String?
    /// Set when privileged helper sync (hosts/resolvers/pf) fails after retries.
    var helperSyncError: String?

    private let settings: AppSettings
    private let processController: CaddyProcessController
    private let helperInstaller: HelperInstaller
    private let helperClient: HelperClient
    private let dnsResponder: LocalDNSResponder
    private let fileManager = FileManager.default

    init(
        settings: AppSettings,
        processController: CaddyProcessController,
        helperInstaller: HelperInstaller,
        helperClient: HelperClient,
        dnsResponder: LocalDNSResponder
    ) {
        self.settings = settings
        self.processController = processController
        self.helperInstaller = helperInstaller
        self.helperClient = helperClient
        self.dnsResponder = dnsResponder
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
            Self.logger.error("Failed to load vhosts: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    private func persist() {
        do {
            let url = try Self.vhostsFileURL()
            let data = try JSONEncoder().encode(vhosts)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Failed to save vhosts: \(error.localizedDescription)")
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

    // MARK: - Import / Export

    func exportData() throws -> Data {
        try VhostImportExport.exportData(vhosts: vhosts)
    }

    @discardableResult
    func importData(_ data: Data) throws -> Int {
        let result = try VhostImportExport.importVhosts(from: data, existing: vhosts)
        guard !result.imported.isEmpty else { return result.skipped }
        vhosts.append(contentsOf: result.imported)
        persist()
        Task { await regenerateAndReload() }
        return result.skipped
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
                _ = await syncPrivilegedNetworking()
            } else {
                helperSyncError = nil
                dnsResponder.stop()
            }
        } catch {
            Self.logger.error("Failed to regenerate/reload Caddy config: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Ping helper, then sync hosts / resolvers / pf independently.
    /// Returns `true` when ping and pf redirect both succeed (sites on :80/:443 need pf).
    @discardableResult
    func syncPrivilegedNetworking() async -> Bool {
        guard helperInstaller.isEnabled else {
            helperSyncError = nil
            dnsResponder.stop()
            return true
        }

        var errors: [String] = []

        helperInstaller.refreshStatus()
        guard helperInstaller.isEnabled else {
            helperSyncError = nil
            dnsResponder.stop()
            return true
        }

        do {
            _ = try await helperClient.ping()
        } catch {
            let message = error.localizedDescription
            Self.logger.error("Helper ping failed: \(message)")
            if message.localizedCaseInsensitiveContains("invalidated")
                || message.localizedCaseInsensitiveContains("interrupted") {
                helperSyncError = "Privileged helper unreachable (\(message)). Open Settings → Helper and press Reinstall."
            } else {
                helperSyncError = "Privileged helper unreachable: \(message)"
            }
            return false
        }

        let domains = enabledHostnamesForHosts()
        let tlds = enabledResolverTLDs()

        do {
            try await helperClient.syncHosts(domains: domains)
        } catch {
            let message = error.localizedDescription
            Self.logger.error("Failed to sync hosts via helper: \(message)")
            errors.append("hosts: \(message)")
        }

        do {
            try await helperClient.syncResolvers(tlds: tlds, dnsPort: LocalDomainPolicy.dnsListenPort)
            dnsResponder.update(tlds: tlds)
        } catch {
            let message = error.localizedDescription
            Self.logger.error("Failed to sync resolvers via helper: \(message)")
            errors.append("resolvers: \(message)")
            if tlds.isEmpty {
                dnsResponder.stop()
            }
        }

        var pfOK = false
        do {
            try await helperClient.installPFRedirect(httpPort: settings.httpPort, httpsPort: settings.httpsPort)
            pfOK = true
        } catch {
            let message = error.localizedDescription
            Self.logger.error("Failed to install pf redirect via helper: \(message)")
            errors.append("pf: \(message)")
        }

        if errors.isEmpty {
            helperSyncError = nil
        } else {
            helperSyncError = "Privileged networking incomplete: \(errors.joined(separator: "; "))"
        }
        // Sites on :80/:443 need pf; hosts/resolvers failures are reported but do not block launch retries.
        return pfOK
    }

    /// Retries `syncPrivilegedNetworking` with exponential backoff until success or ~30s elapsed.
    @discardableResult
    func ensurePrivilegedNetworkingOnLaunch() async -> Bool {
        guard helperInstaller.isEnabled else {
            helperSyncError = nil
            return true
        }

        var delayNs: UInt64 = 500_000_000
        let maxDelayNs: UInt64 = 8_000_000_000
        // 0.5 + 1 + 2 + 4 + 8 + 8 ≈ 23.5s of sleeps, plus attempt work ≈ ~30s window
        for attempt in 0..<6 {
            if await syncPrivilegedNetworking() {
                return true
            }
            if attempt == 5 { break }
            Self.logger.info("Privileged networking sync retry \(attempt + 1) after failure")
            try? await Task.sleep(nanoseconds: delayNs)
            delayNs = min(delayNs * 2, maxDelayNs)
        }
        return false
    }

    /// Explicit hostnames for /etc/hosts (non-wildcard domains + aliases).
    func enabledHostnamesForHosts() -> [String] {
        vhosts
            .filter(\.isEnabled)
            .flatMap(\.allDomains)
            .filter { !$0.hasPrefix("*.") }
            .reduce(into: [String]()) { result, domain in
                if !result.contains(domain) { result.append(domain) }
            }
    }

    /// TLDs that need /etc/resolver + local DNS (any enabled wildcard under that TLD).
    func enabledResolverTLDs() -> [String] {
        var tlds = Set<String>()
        for vhost in vhosts where vhost.isEnabled && vhost.isWildcard {
            if let tld = vhost.topLevelDomain {
                tlds.insert(tld)
            }
        }
        return tlds.sorted()
    }
}
