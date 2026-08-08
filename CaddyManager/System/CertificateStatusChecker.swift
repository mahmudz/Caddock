import AppKit
import Foundation
import Security

enum CertificateTrustStatus: Equatable {
    case notInstalled
    case installedNotTrusted
    case installedAndTrusted
}

enum CertificateStatusChecker {
    static var rootCertificateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Caddy/pki/authorities/local/root.crt")
    }

    static func status() -> CertificateTrustStatus {
        let fileExists = FileManager.default.fileExists(atPath: rootCertificateURL.path)
        let fileCert = fileExists ? CertificateTrustInstaller.loadCertificate(from: rootCertificateURL) : nil

        if let fileCert, hasTrust(fileCert) {
            return .installedAndTrusted
        }

        if hasAnyTrustedCaddyAuthority() {
            return fileExists ? .installedNotTrusted : .installedAndTrusted
        }

        if fileExists {
            return .installedNotTrusted
        }

        return .notInstalled
    }

    static func openKeychainAccess() {
        let systemPath = "/System/Applications/Utilities/Keychain Access.app"
        if FileManager.default.fileExists(atPath: systemPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: systemPath))
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Utilities/Keychain Access.app"))
    }

    /// Trusted in user or admin (System) trust settings.
    private static func hasTrust(_ certificate: SecCertificate) -> Bool {
        hasTrust(certificate, domain: .user) || hasTrust(certificate, domain: .admin)
    }

    private static func hasTrust(_ certificate: SecCertificate, domain: SecTrustSettingsDomain) -> Bool {
        var trustSettings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(certificate, domain, &trustSettings)
        guard status == errSecSuccess, let trustSettings else { return false }
        return CFArrayGetCount(trustSettings) > 0
    }

    private static func hasAnyTrustedCaddyAuthority() -> Bool {
        for domain: SecTrustSettingsDomain in [.user, .admin] {
            var certArray: CFArray?
            let status = SecTrustSettingsCopyCertificates(domain, &certArray)
            guard status == errSecSuccess, let certs = certArray as? [SecCertificate] else { continue }
            if certs.contains(where: { cert in
                let summary = SecCertificateCopySubjectSummary(cert) as String? ?? ""
                return summary.localizedCaseInsensitiveContains("Caddy Local Authority")
            }) {
                return true
            }
        }
        return false
    }
}
