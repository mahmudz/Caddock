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

    /// All hostnames (primary + aliases), trimmed and deduplicated.
    var allDomains: [String] {
        var seen = Set<String>()
        return ([domain] + aliases)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
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
