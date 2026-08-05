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
        guard FileManager.default.fileExists(atPath: rootCertificateURL.path) else {
            return .notInstalled
        }

        guard let certData = try? Data(contentsOf: rootCertificateURL),
              let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            return .notInstalled
        }

        if isTrustedInSystemKeychain(certificate) {
            return .installedAndTrusted
        }

        return .installedNotTrusted
    }

    static func openKeychainAccess() {
        let systemPath = "/System/Applications/Utilities/Keychain Access.app"
        if FileManager.default.fileExists(atPath: systemPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: systemPath))
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Utilities/Keychain Access.app"))
    }

    private static func isTrustedInSystemKeychain(_ certificate: SecCertificate) -> Bool {
        var trustSettings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(certificate, .admin, &trustSettings)
        if status == errSecSuccess, let trustSettings, CFArrayGetCount(trustSettings) > 0 {
            return true
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnRef: true,
        ]
        var result: CFTypeRef?
        let copyStatus = SecItemCopyMatching(query as CFDictionary, &result)
        guard copyStatus == errSecSuccess, let items = result as? [SecCertificate] else {
            return false
        }

        let targetData = SecCertificateCopyData(certificate) as Data
        return items.contains { SecCertificateCopyData($0) as Data == targetData }
    }
}
