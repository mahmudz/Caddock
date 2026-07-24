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
    }

    var id: UUID = UUID()
    var domain: String            // e.g. "myproject.test"
    var kind: Kind
    var documentRoot: String?     // required for .staticSite / .phpSite
    var phpSocketPath: String?    // required for .phpSite, e.g. "/opt/homebrew/var/run/php/php8.3.sock"
    var proxyTarget: String?      // required for .reverseProxy, e.g. "127.0.0.1:3000"
    var sslEnabled: Bool = true
    var isEnabled: Bool = true    // included in generated config only if true
}
