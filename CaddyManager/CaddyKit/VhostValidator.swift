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
    private static let wildcardDomainRegex = try! NSRegularExpression(
        pattern: #"^\*\.[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$"#
    )

    static func validate(_ vhost: Vhost, existing: [Vhost]) -> [VhostValidationIssue] {
        var issues: [VhostValidationIssue] = []

        if vhost.domain.isEmpty {
            issues.append(.init(severity: .error, message: "Domain cannot be empty."))
        } else if vhost.domain != vhost.domain.lowercased() || vhost.domain.contains(where: \.isWhitespace) {
            issues.append(.init(severity: .error, message: "Domain must be lowercase with no whitespace."))
        } else if !isValidHostname(vhost.domain, allowWildcard: true) {
            issues.append(.init(severity: .error, message: "Domain does not look like a valid hostname (e.g. myapp.test or *.myapp.test)."))
        }

        if let tld = LocalDomainPolicy.tld(of: vhost.domain), LocalDomainPolicy.isBlockedPublicTLD(tld) {
            issues.append(.init(
                severity: .error,
                message: "Do not use public TLD \".\(tld)\" for local sites. Prefer .test, .localhost, or .example."
            ))
        } else if let tld = LocalDomainPolicy.tld(of: vhost.domain), tld == "local" {
            issues.append(.init(
                severity: .warning,
                message: "\".local\" conflicts with Bonjour/mDNS on macOS. Prefer .test for more reliable DNS and HTTPS."
            ))
        } else if let tld = LocalDomainPolicy.tld(of: vhost.domain), !LocalDomainPolicy.isRecommendedTLD(tld) {
            issues.append(.init(
                severity: .warning,
                message: "TLD \".\(tld)\" is not a reserved local TLD. Prefer .test, .localhost, or .example."
            ))
        }

        if existing.contains(where: { $0.id != vhost.id && $0.allDomains.contains(vhost.domain.lowercased()) }) {
            issues.append(.init(severity: .error, message: "Another vhost already uses this domain."))
        }

        let reservedDomains = Set(
            existing
                .filter { $0.id != vhost.id }
                .flatMap(\.allDomains)
        )
        for alias in vhost.aliases.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }).filter({ !$0.isEmpty }) {
            if alias == vhost.domain.lowercased() {
                issues.append(.init(severity: .error, message: "Alias \"\(alias)\" duplicates the primary domain."))
            } else if reservedDomains.contains(alias) {
                issues.append(.init(severity: .error, message: "Another vhost already uses \"\(alias)\"."))
            } else if LocalDomainPolicy.isWildcardDomain(alias) {
                issues.append(.init(severity: .error, message: "Wildcard aliases are not supported — put the wildcard on the primary domain."))
            } else if !isValidHostname(alias, allowWildcard: false) {
                issues.append(.init(severity: .error, message: "Alias \"\(alias)\" does not look like a valid hostname."))
            } else if let tld = LocalDomainPolicy.tld(of: alias), LocalDomainPolicy.isBlockedPublicTLD(tld) {
                issues.append(.init(severity: .error, message: "Alias \"\(alias)\" uses blocked public TLD \".\(tld)\"."))
            }
        }

        if vhost.allDomains.count != ([vhost.domain] + vhost.aliases.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }).filter({ !$0.isEmpty }).count {
            issues.append(.init(severity: .error, message: "Duplicate aliases are not allowed."))
        }

        switch vhost.kind {
        case .staticSite:
            if isBlank(vhost.documentRoot) {
                issues.append(.init(severity: .error, message: "Static sites require a document root."))
            }
            if vhost.phpSocketPath != nil || vhost.proxyTarget != nil {
                issues.append(.init(severity: .error, message: "Static sites must not set a PHP socket or proxy target."))
            }
            issues.append(contentsOf: indexFileIssues(for: vhost))
        case .phpSite:
            if isBlank(vhost.documentRoot) {
                issues.append(.init(severity: .error, message: "PHP sites require a document root."))
            }
            if isBlank(vhost.phpSocketPath) {
                issues.append(.init(severity: .error, message: "PHP sites require a PHP-FPM socket path."))
            } else if let socketPath = vhost.phpSocketPath, !SocketValidator.isListening(at: socketPath) {
                issues.append(.init(severity: .warning, message: "PHP-FPM is not accepting connections at this socket — it may not be running."))
            }
            if vhost.proxyTarget != nil {
                issues.append(.init(severity: .error, message: "PHP sites must not set a proxy target."))
            }
            issues.append(contentsOf: indexFileIssues(for: vhost))
        case .reverseProxy:
            if isBlank(vhost.proxyTarget) {
                issues.append(.init(severity: .error, message: "Reverse proxies require a target (e.g. 127.0.0.1:3000)."))
            }
            if vhost.documentRoot != nil || vhost.phpSocketPath != nil {
                issues.append(.init(severity: .error, message: "Reverse proxies must not set a document root or PHP socket."))
            }
            if vhost.indexFiles != nil && !isBlank(vhost.indexFiles) {
                issues.append(.init(severity: .error, message: "Reverse proxies must not set index files."))
            }
        }

        return issues
    }

    private static func isValidHostname(_ value: String, allowWildcard: Bool) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        if allowWildcard, LocalDomainPolicy.isWildcardDomain(value) {
            return wildcardDomainRegex.firstMatch(in: value, range: range) != nil
        }
        return domainRegex.firstMatch(in: value, range: range) != nil
    }

    private static func indexFileIssues(for vhost: Vhost) -> [VhostValidationIssue] {
        guard !isBlank(vhost.indexFiles) else { return [] }
        let tokens = vhost.indexFiles!
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if tokens.isEmpty {
            return [.init(severity: .error, message: "Index files cannot be blank when specified.")]
        }
        if tokens.contains(where: { $0.contains("/") || $0.isEmpty }) {
            return [.init(severity: .error, message: "Index files must be filenames only (e.g. index.html index.php).")]
        }
        return []
    }

    static func isValid(_ vhost: Vhost, existing: [Vhost]) -> Bool {
        !validate(vhost, existing: existing).contains { $0.severity == .error }
    }

    private static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
