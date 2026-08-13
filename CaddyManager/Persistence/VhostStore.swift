import Foundation
import Observation

@Observable
final class VhostStore {
    private static let logger = AppLogger(category: "VhostStore")

    private(set) var vhosts: [Vhost] = []
    var lastError: String?
    var helperSyncError: String?

    private let settings: AppSettings
    private let processController: any CaddyControlling
    private let helperInstaller: any PrivilegedHelperInstalling
    private let helperClient: any PrivilegedHelperClienting
    private let dnsResponder: any LocalDNSResponding
    private let fileManager = FileManager.default

    init(
        settings: AppSettings,
        processController: any CaddyControlling,
        helperInstaller: any PrivilegedHelperInstalling,
        helperClient: any PrivilegedHelperClienting,
        dnsResponder: any LocalDNSResponding
    ) {
        self.settings = settings
        self.processController = processController
        self.helperInstaller = helperInstaller
        self.helperClient = helperClient
        self.dnsResponder = dnsResponder
        load()
    }

    func load() {
        do {
            let url = try AppPaths.vhostsFileURL()
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
            let url = try AppPaths.vhostsFileURL()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(vhosts)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Failed to save vhosts: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

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

    func regenerateAndReload() async {
        do {
            let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: vhosts, settings: settings)
            let url = try AppPaths.caddyfileURL()
            try caddyfile.write(to: url, atomically: true, encoding: .utf8)

            guard let binary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride) else {
                lastError = "Caddy binary not found. Open Install Caddy… from the menu to set it up."
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

    /// After ports change: reload Caddy, then reinstall pf redirects.
    func applyPortChanges() async {
        await regenerateAndReload()
        guard helperInstaller.isEnabled else { return }
        do {
            try await helperClient.installPFRedirect(httpPort: settings.httpPort, httpsPort: settings.httpsPort)
        } catch {
            helperSyncError = "pf: \(error.localizedDescription)"
            Self.logger.error("Failed to reinstall pf after port change: \(error.localizedDescription)")
        }
    }

    /// Ensure `root.crt` exists by starting Caddy with at least one TLS site.
    func ensureTLSRootCertificate() async {
        if FileManager.default.fileExists(atPath: AppPaths.caddyPKIRootCertificateURL.path) {
            return
        }
        if !vhosts.contains(where: { $0.isEnabled && $0.sslEnabled }) {
            let placeholder = Vhost(
                domain: "caddymanager.localhost",
                kind: .staticSite,
                documentRoot: FileManager.default.temporaryDirectory.path,
                sslEnabled: true,
                isEnabled: true
            )
            let previous = vhosts
            vhosts.append(placeholder)
            await regenerateAndReload()
            vhosts = previous
            persist()
            await regenerateAndReload()
            return
        }
        await regenerateAndReload()
    }

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
                helperSyncError = "Privileged helper unreachable (\(message)). Open Settings → Advanced and press Reinstall."
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
        return pfOK
    }

    @discardableResult
    func ensurePrivilegedNetworkingOnLaunch() async -> Bool {
        guard helperInstaller.isEnabled else {
            helperSyncError = nil
            return true
        }

        var delayNs: UInt64 = 500_000_000
        let maxDelayNs: UInt64 = 8_000_000_000
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

    func enabledHostnamesForHosts() -> [String] {
        vhosts
            .filter(\.isEnabled)
            .flatMap(\.allDomains)
            .filter { !$0.hasPrefix("*.") }
            .reduce(into: [String]()) { result, domain in
                if !result.contains(domain) { result.append(domain) }
            }
    }

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
