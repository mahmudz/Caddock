import Foundation

enum CaddyConfigBuilder {
    static func buildCaddyfile(vhosts: [Vhost], settings: AppSettings) -> String {
        var blocks: [String] = [globalOptionsBlock(settings: settings)]
        blocks.append(contentsOf: vhosts.filter(\.isEnabled).map { block(for: $0) })
        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func globalOptionsBlock(settings: AppSettings) -> String {
        """
        {
            http_port \(settings.httpPort)
            https_port \(settings.httpsPort)
            admin 127.0.0.1:\(settings.adminPort)
        }
        """
    }

    private static func block(for vhost: Vhost) -> String {
        let address = vhost.sslEnabled ? vhost.domain : "http://\(vhost.domain)"
        let tlsLine = vhost.sslEnabled ? "\n    tls internal" : ""

        switch vhost.kind {
        case .staticSite:
            return """
            \(address) {\(tlsLine)
                root * \(vhost.documentRoot ?? "")
                encode gzip
                file_server
            }
            """
        case .phpSite:
            return """
            \(address) {\(tlsLine)
                root * \(vhost.documentRoot ?? "")
                encode gzip
                php_fastcgi unix/\(vhost.phpSocketPath ?? "")
                file_server
            }
            """
        case .reverseProxy:
            return """
            \(address) {\(tlsLine)
                reverse_proxy \(vhost.proxyTarget ?? "")
            }
            """
        }
    }
}
