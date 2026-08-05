import Foundation

enum CaddyConfigBuilder {
    static func buildCaddyfile(vhosts: [Vhost], settings: AppSettings) -> String {
        var blocks: [String] = []
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
        let address = siteAddresses(for: vhost)
        let tlsLine = vhost.sslEnabled ? "\n    tls internal" : ""
        let encodeLine = vhost.compressionEnabled ? "\n    encode gzip" : ""

        switch vhost.kind {
        case .staticSite:
            return """
            \(address) {\(tlsLine) \(encodeLine)
                root * \(vhost.documentRoot ?? "")
                file_server {
                    index \(vhost.resolvedIndexFiles())
                }
            }
            """
        case .phpSite:
            return """
            \(address) {\(tlsLine) \(encodeLine)
                root * \(vhost.documentRoot ?? "")
                php_fastcgi \(phpFastcgiTarget(vhost.phpSocketPath ?? ""))
                file_server {
                    index \(vhost.resolvedIndexFiles())
                }
            }
            """
        case .reverseProxy:
            return """
            \(address) {
                \(reverseProxyBlock(for: vhost))
            }
            """
        }
    }

    private static func siteAddresses(for vhost: Vhost) -> String {
        let hosts = vhost.allDomains
        guard !hosts.isEmpty else { return vhost.domain }
        if vhost.sslEnabled {
            return hosts.joined(separator: ", ")
        }
        return hosts.map { "http://\($0)" }.joined(separator: ", ")
    }

    private static func phpFastcgiTarget(_ socketPath: String) -> String {
        if socketPath.hasPrefix("unix/") || socketPath.contains("://") {
            return socketPath
        }
        return "\(socketPath)"
    }

    private static func reverseProxyBlock(for vhost: Vhost) -> String {
        let target = vhost.proxyTarget ?? ""
        let needsBlock = vhost.websocketEnabled || vhost.preserveHostHeader || vhost.forwardProxyHeaders
        guard needsBlock else {
            return "reverse_proxy \(target)"
        }

        var lines = ["reverse_proxy \(target) {"]
        if vhost.websocketEnabled {
            lines.append("    flush_interval -1")
            lines.append("    transport http {")
            lines.append("        read_timeout 0")
            lines.append("        write_timeout 0")
            lines.append("    }")
        }
        if vhost.preserveHostHeader {
            lines.append("    header_up Host {host}")
        }
        if vhost.forwardProxyHeaders {
            lines.append("    header_up X-Real-IP {remote_host}")
            lines.append("    header_up X-Forwarded-For {remote_host}")
            lines.append("    header_up X-Forwarded-Proto {scheme}")
            lines.append("    header_up X-Forwarded-Host {host}")
        }
        lines.append("}")
        return lines.joined(separator: "\n    ")
    }
}
