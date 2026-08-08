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
    /// Trust Caddy's local Root CA for this user (and try System store when possible).
    ///
    /// Must run in the GUI app process — never the LaunchDaemon helper, and never via
    /// `do shell script … with administrator privileges` (that elevated context cannot show
    /// the SecTrustSettings authorization UI → "no user interaction was possible").
    @MainActor
    static func installRootCA() throws {
        let rootURL = CertificateStatusChecker.rootCertificateURL
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw CertificateTrustInstallerError.certificateMissing(rootURL.path)
        }
        guard let certificate = loadCertificate(from: rootURL) else {
            throw CertificateTrustInstallerError.invalidCertificate
        }

        // Menu bar accessory apps cannot present Security Agent sheets until regular + active.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        defer { AppWindowPresenter.hideDockIconIfNoWindows() }

        // 1) User trust domain — enough for Safari/Chrome for this macOS user.
        try setTrustSettings(certificate, domain: .user)

        // 2) Best-effort System trust as the current user (may prompt).
        //    Do NOT elevate via osascript — that strips interactive SecTrustSettings auth.
        _ = runSecurityAddTrustedCert(rootPath: rootURL.path, systemStore: true)
    }

    /// `SecCertificateCreateWithData` requires DER. Caddy stores PEM — convert when needed.
    static func loadCertificate(from url: URL) -> SecCertificate? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let cert = SecCertificateCreateWithData(nil, data as CFData) {
            return cert
        }
        guard let der = pemToDER(data) else { return nil }
        return SecCertificateCreateWithData(nil, der as CFData)
    }

    private static func pemToDER(_ data: Data) -> Data? {
        guard let pem = String(data: data, encoding: .utf8) else { return nil }
        let lines = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let b64 = lines.joined()
        return Data(base64Encoded: b64, options: [.ignoreUnknownCharacters])
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

    private static func runSecurityAddTrustedCert(rootPath: String, systemStore: Bool) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        var args = ["add-trusted-cert", "-r", "trustRoot", "-p", "ssl", "-p", "basic"]
        if systemStore {
            args += ["-d", "-k", "/Library/Keychains/System.keychain"]
        }
        args.append(rootPath)
        process.arguments = args

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
