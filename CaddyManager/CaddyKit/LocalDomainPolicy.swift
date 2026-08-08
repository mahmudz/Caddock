import Foundation

enum LocalDomainPolicy {
    /// TLDs reserved for local/testing use.
    /// Note: `.local` is listed but discouraged — Bonjour/mDNS owns it on macOS.
    static let recommendedTLDs: Set<String> = [
        "test", "localhost", "example", "invalid", "lan", "home", "internal",
    ]

    /// Common public TLDs that must never be used with /etc/resolver wildcards.
    static let blockedPublicTLDs: Set<String> = [
        "com", "net", "org", "edu", "gov", "mil", "io", "dev", "app", "co", "uk", "us",
        "ca", "au", "de", "fr", "jp", "cn", "ru", "info", "biz", "me", "tv", "xyz",
        "online", "site", "tech", "store", "cloud", "ai", "gg", "sh", "so", "to",
    ]

    static let dnsListenPort = HelperConstants.dnsListenPort

    static func tld(of domain: String) -> String? {
        let cleaned = domain.hasPrefix("*.") ? String(domain.dropFirst(2)) : domain
        let parts = cleaned.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts.last?.lowercased()
    }

    static func isWildcardDomain(_ domain: String) -> Bool {
        domain.hasPrefix("*.") && domain.split(separator: ".").count >= 3
    }

    static func isBlockedPublicTLD(_ tld: String) -> Bool {
        blockedPublicTLDs.contains(tld.lowercased())
    }

    static func isRecommendedTLD(_ tld: String) -> Bool {
        recommendedTLDs.contains(tld.lowercased())
    }
}
