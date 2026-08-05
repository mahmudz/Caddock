import Foundation

struct Vhost: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case staticSite    // file_server only
        case phpSite       // file_server + php_fastcgi over a unix socket
        case reverseProxy  // reverse_proxy to a local host:port

        var displayName: String {
            switch self {
            case .staticSite: return "Static Site"
            case .phpSite: return "PHP Site"
            case .reverseProxy: return "Reverse Proxy"
            }
        }

        var systemImage: String {
            switch self {
            case .staticSite: return "doc.on.doc"
            case .phpSite: return "chevron.left.forwardslash.chevron.right"
            case .reverseProxy: return "arrow.triangle.swap"
            }
        }
    }

    var id: UUID = UUID()
    var domain: String            // e.g. "myproject.test"
    var aliases: [String] = []    // additional hostnames served by the same site block
    var kind: Kind
    var documentRoot: String?     // required for .staticSite / .phpSite
    var phpSocketPath: String?    // required for .phpSite, e.g. "/opt/homebrew/var/run/php/php8.3.sock"
    var proxyTarget: String?      // required for .reverseProxy, e.g. "127.0.0.1:3000"
    var sslEnabled: Bool = true
    var isEnabled: Bool = true    // included in generated config only if true

    // Server options
    var compressionEnabled: Bool = true
    var indexFiles: String?       // nil = kind default (index.html or index.html index.php)

    // Reverse-proxy options
    var websocketEnabled: Bool = true       // long-lived connections for WebSocket / SSE / HMR
    var preserveHostHeader: Bool = false    // header_up Host {host}
    var forwardProxyHeaders: Bool = true    // X-Forwarded-* and X-Real-IP

    // Per-site log monitoring
    var logSource: VhostLogSource = .none

    enum CodingKeys: String, CodingKey {
        case id, domain, aliases, kind, documentRoot, phpSocketPath, proxyTarget
        case sslEnabled, isEnabled, compressionEnabled, indexFiles
        case websocketEnabled, preserveHostHeader, forwardProxyHeaders, logSource
    }

    init(
        id: UUID = UUID(),
        domain: String,
        aliases: [String] = [],
        kind: Kind,
        documentRoot: String? = nil,
        phpSocketPath: String? = nil,
        proxyTarget: String? = nil,
        sslEnabled: Bool = true,
        isEnabled: Bool = true,
        compressionEnabled: Bool = true,
        indexFiles: String? = nil,
        websocketEnabled: Bool = true,
        preserveHostHeader: Bool = false,
        forwardProxyHeaders: Bool = true,
        logSource: VhostLogSource = .none
    ) {
        self.id = id
        self.domain = domain
        self.aliases = aliases
        self.kind = kind
        self.documentRoot = documentRoot
        self.phpSocketPath = phpSocketPath
        self.proxyTarget = proxyTarget
        self.sslEnabled = sslEnabled
        self.isEnabled = isEnabled
        self.compressionEnabled = compressionEnabled
        self.indexFiles = indexFiles
        self.websocketEnabled = websocketEnabled
        self.preserveHostHeader = preserveHostHeader
        self.forwardProxyHeaders = forwardProxyHeaders
        self.logSource = logSource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        domain = try c.decode(String.self, forKey: .domain)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        kind = try c.decode(Kind.self, forKey: .kind)
        documentRoot = try c.decodeIfPresent(String.self, forKey: .documentRoot)
        phpSocketPath = try c.decodeIfPresent(String.self, forKey: .phpSocketPath)
        proxyTarget = try c.decodeIfPresent(String.self, forKey: .proxyTarget)
        sslEnabled = try c.decodeIfPresent(Bool.self, forKey: .sslEnabled) ?? true
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        compressionEnabled = try c.decodeIfPresent(Bool.self, forKey: .compressionEnabled) ?? true
        indexFiles = try c.decodeIfPresent(String.self, forKey: .indexFiles)
        websocketEnabled = try c.decodeIfPresent(Bool.self, forKey: .websocketEnabled) ?? true
        preserveHostHeader = try c.decodeIfPresent(Bool.self, forKey: .preserveHostHeader) ?? false
        forwardProxyHeaders = try c.decodeIfPresent(Bool.self, forKey: .forwardProxyHeaders) ?? true
        logSource = try c.decodeIfPresent(VhostLogSource.self, forKey: .logSource) ?? .none
    }

    /// All hostnames (primary + aliases), trimmed and deduplicated.
    var allDomains: [String] {
        var seen = Set<String>()
        return ([domain] + aliases)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var isWildcard: Bool {
        LocalDomainPolicy.isWildcardDomain(domain)
    }

    var topLevelDomain: String? {
        LocalDomainPolicy.tld(of: domain)
    }

    func defaultIndexFiles() -> String {
        switch kind {
        case .staticSite: return "index.html"
        case .phpSite: return "index.html index.php"
        case .reverseProxy: return ""
        }
    }

    func resolvedIndexFiles() -> String {
        let trimmed = indexFiles?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? defaultIndexFiles() : trimmed
    }

    /// URL to open this vhost in a browser.
    func browserURL(settings: AppSettings, useStandardPorts: Bool) -> URL? {
        guard !domain.isEmpty else { return nil }
        // Wildcard domains have no concrete host to open.
        if isWildcard { return nil }

        if sslEnabled {
            if useStandardPorts || settings.httpsPort == 443 {
                return URL(string: "https://\(domain)")
            }
            return URL(string: "https://\(domain):\(settings.httpsPort)")
        }

        if useStandardPorts || settings.httpPort == 80 {
            return URL(string: "http://\(domain)")
        }
        return URL(string: "http://\(domain):\(settings.httpPort)")
    }
}
