import AppKit
import Foundation
import Security

enum CertificateTrustInstallerError: LocalizedError {
    case certificateMissing(String)
    case invalidCertificate
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .certificateMissing(let path):
            return "Root certificate not found at \(path). Start Caddy with a TLS-enabled vhost first."
        case .invalidCertificate:
            return "Could not read Caddy's Root CA certificate."
        case .authorizationFailed(let detail):
            return detail
        }
    }
}

enum CertificateTrustInstaller {
    /// Trust Caddy's local Root CA in the GUI process so Security Agent can prompt.
    @MainActor
    static func installRootCA() throws {
        let rootURL = CertificateStatusChecker.rootCertificateURL
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw CertificateTrustInstallerError.certificateMissing(rootURL.path)
        }
        guard let certificate = CertificateLoader.load(from: rootURL) else {
            throw CertificateTrustInstallerError.invalidCertificate
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        defer { AppWindowPresenter.hideDockIconIfNoWindows() }

        try setTrustSettings(certificate, domain: .user)
        _ = runSecurityAddTrustedCert(rootPath: rootURL.path)
    }

    private static func setTrustSettings(_ certificate: SecCertificate, domain: SecTrustSettingsDomain) throws {
        let trustResult = NSNumber(value: SecTrustSettingsResult.trustRoot.rawValue)
        let properties: [[String: Any]] = [
            [kSecTrustSettingsResult as String: trustResult],
        ]

        addToKeychainIfNeeded(certificate)

        let status = SecTrustSettingsSetTrustSettings(certificate, domain, properties as CFArray)
        switch status {
        case errSecSuccess:
            return
        case errSecAuthFailed, errSecUserCanceled:
            throw CertificateTrustInstallerError.authorizationFailed("Authentication was cancelled.")
        default:
            let retry = SecTrustSettingsSetTrustSettings(certificate, domain, properties as CFArray)
            guard retry == errSecSuccess else {
                throw CertificateTrustInstallerError.authorizationFailed(secErrorMessage(status))
            }
        }
    }

    private static func addToKeychainIfNeeded(_ certificate: SecCertificate) {
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
        ]
        var result: CFTypeRef?
        _ = SecItemAdd(addQuery as CFDictionary, &result)
    }

    private static func runSecurityAddTrustedCert(rootPath: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-trusted-cert", "-r", "trustRoot", "-p", "ssl", "-p", "basic",
            "-d", "-k", "/Library/Keychains/System.keychain",
            rootPath,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private static func secErrorMessage(_ status: OSStatus) -> String {
        if let msg = SecCopyErrorMessageString(status, nil) as String? {
            return msg
        }
        return "Security error \(status)."
    }
}

enum KeychainAccessOpener {
    static func open() throws {
        let configuration = NSWorkspace.OpenConfiguration()
        let systemURL = URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app")

        if FileManager.default.fileExists(atPath: systemURL.path) {
            NSWorkspace.shared.openApplication(at: systemURL, configuration: configuration) { _, error in
                if let error {
                    AppLogger(category: "Keychain").error("Failed to open Keychain Access: \(error.localizedDescription)")
                }
            }
            return
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.keychainaccess") {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    AppLogger(category: "Keychain").error("Failed to open Keychain Access: \(error.localizedDescription)")
                }
            }
            return
        }

        throw NSError(
            domain: "Caddock",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not find Keychain Access. Open it from Spotlight."]
        )
    }
}
