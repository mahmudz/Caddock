import Foundation

struct VhostValidationIssue: Identifiable, Equatable {
    enum Severity {
        case error
        case warning
    }

    var id: String { message }
    var severity: Severity
    var message: String
}

enum VhostValidator {
    private static let domainRegex = try! NSRegularExpression(
        pattern: #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$"#
    )

    static func validate(_ vhost: Vhost, existing: [Vhost]) -> [VhostValidationIssue] {
        var issues: [VhostValidationIssue] = []

        if vhost.domain.isEmpty {
            issues.append(.init(severity: .error, message: "Domain cannot be empty."))
        } else if vhost.domain != vhost.domain.lowercased() || vhost.domain.contains(where: \.isWhitespace) {
            issues.append(.init(severity: .error, message: "Domain must be lowercase with no whitespace."))
        } else {
            let range = NSRange(vhost.domain.startIndex..<vhost.domain.endIndex, in: vhost.domain)
            if domainRegex.firstMatch(in: vhost.domain, range: range) == nil {
                issues.append(.init(severity: .error, message: "Domain does not look like a valid hostname (e.g. myapp.test)."))
            }
        }

        if existing.contains(where: { $0.id != vhost.id && $0.domain == vhost.domain }) {
            issues.append(.init(severity: .error, message: "Another vhost already uses this domain."))
        }

        switch vhost.kind {
        case .staticSite:
            if isBlank(vhost.documentRoot) {
                issues.append(.init(severity: .error, message: "Static sites require a document root."))
            }
            if vhost.phpSocketPath != nil || vhost.proxyTarget != nil {
                issues.append(.init(severity: .error, message: "Static sites must not set a PHP socket or proxy target."))
            }
        case .phpSite:
            if isBlank(vhost.documentRoot) {
                issues.append(.init(severity: .error, message: "PHP sites require a document root."))
            }
            if isBlank(vhost.phpSocketPath) {
                issues.append(.init(severity: .error, message: "PHP sites require a PHP-FPM socket path."))
            } else if let socketPath = vhost.phpSocketPath, !FileManager.default.fileExists(atPath: socketPath) {
                issues.append(.init(severity: .warning, message: "PHP-FPM socket not found on disk yet — it may not be running."))
            }
            if vhost.proxyTarget != nil {
                issues.append(.init(severity: .error, message: "PHP sites must not set a proxy target."))
            }
        case .reverseProxy:
            if isBlank(vhost.proxyTarget) {
                issues.append(.init(severity: .error, message: "Reverse proxies require a target (e.g. 127.0.0.1:3000)."))
            }
            if vhost.documentRoot != nil || vhost.phpSocketPath != nil {
                issues.append(.init(severity: .error, message: "Reverse proxies must not set a document root or PHP socket."))
            }
        }

        return issues
    }

    static func isValid(_ vhost: Vhost, existing: [Vhost]) -> Bool {
        !validate(vhost, existing: existing).contains { $0.severity == .error }
    }

    private static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
