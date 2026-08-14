import CryptoKit
import Foundation
import Security

enum CertificateTrustStatus: Equatable {
    case notInstalled
    case installedNotTrusted
    case installedAndTrusted
}

enum CertificateFingerprint {
    static func sha256(of certificate: SecCertificate) -> Data {
        let der = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: der)
        return Data(digest)
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

enum CertificateStatusChecker {
    static var rootCertificateURL: URL { AppPaths.caddyPKIRootCertificateURL }

    /// Status of the **current** `root.crt` only. Matching some other
    /// "Caddy Local Authority" in Keychain is not proof this CA is trusted.
    static func status() -> CertificateTrustStatus {
        guard FileManager.default.fileExists(atPath: rootCertificateURL.path) else {
            return .notInstalled
        }
        guard let certificate = CertificateLoader.load(from: rootCertificateURL) else {
            return .notInstalled
        }
        if isTrusted(certificate) {
            return .installedAndTrusted
        }
        return .installedNotTrusted
    }

    static func fingerprintHex() -> String? {
        guard let certificate = CertificateLoader.load(from: rootCertificateURL) else { return nil }
        return CertificateFingerprint.hexString(CertificateFingerprint.sha256(of: certificate))
    }

    static func isTrusted(_ certificate: SecCertificate) -> Bool {
        hasTrustSettings(certificate, domain: .user) || hasTrustSettings(certificate, domain: .admin)
    }

    private static func hasTrustSettings(_ certificate: SecCertificate, domain: SecTrustSettingsDomain) -> Bool {
        var trustSettings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(certificate, domain, &trustSettings)
        guard status == errSecSuccess, let trustSettings else { return false }
        return CFArrayGetCount(trustSettings) > 0
    }
}

enum CertificateLoader {
    static func load(from url: URL) -> SecCertificate? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return load(from: data)
    }

    static func load(from data: Data) -> SecCertificate? {
        if let cert = SecCertificateCreateWithData(nil, data as CFData) {
            return cert
        }
        guard let der = pemToDER(data) else { return nil }
        return SecCertificateCreateWithData(nil, der as CFData)
    }

    static func pemToDER(_ data: Data) -> Data? {
        guard let pem = String(data: data, encoding: .utf8) else { return nil }
        let lines = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let b64 = lines.joined()
        return Data(base64Encoded: b64, options: [.ignoreUnknownCharacters])
    }
}
