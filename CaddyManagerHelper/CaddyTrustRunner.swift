import Foundation

enum CaddyTrustError: Error, CustomStringConvertible {
    case failed(String)
    case certificateMissing(String)

    var description: String {
        switch self {
        case .failed(let output): return "Failed to trust Root CA: \(output)"
        case .certificateMissing(let path):
            return "Root certificate not found at \(path). Start Caddy with a TLS-enabled vhost first."
        }
    }
}

enum CaddyTrustRunner {
    /// Install Caddy's local Root CA into the System keychain as a trusted root.
    /// Runs as root in the helper — must NOT shell out to `caddy trust` (that calls `sudo` and fails).
    static func trust(caddyBinaryPath: String, callingUserHome: String) throws {
        let rootCRT = rootCertificatePath(callingUserHome: callingUserHome)
        guard FileManager.default.fileExists(atPath: rootCRT) else {
            throw CaddyTrustError.certificateMissing(rootCRT)
        }

        // Remove previous Caddy CA entries so re-trust is clean. Ignore failures
        // (cert may be absent after `caddy untrust`).
        _ = try? ProcessRunner.run(
            "/usr/bin/security",
            ["delete-certificate", "-c", "Caddy Local Authority - 2025 ECC Root", "/Library/Keychains/System.keychain"]
        )
        _ = try? ProcessRunner.run(
            "/usr/bin/security",
            ["delete-certificate", "-c", "Caddy Local Authority - 2023 ECC Root", "/Library/Keychains/System.keychain"]
        )
        _ = try? ProcessRunner.run(
            "/usr/bin/security",
            ["delete-certificate", "-c", "Caddy Local Authority", "/Library/Keychains/System.keychain"]
        )

        let result = try ProcessRunner.run("/usr/bin/security", [
            "add-trusted-cert",
            "-d",
            "-r", "trustRoot",
            "-p", "ssl",
            "-p", "basic",
            "-k", "/Library/Keychains/System.keychain",
            rootCRT,
        ])

        if result.exitCode == 0 { return }

        // Fallback without explicit policies (older macOS).
        let fallback = try ProcessRunner.run("/usr/bin/security", [
            "add-trusted-cert",
            "-d",
            "-r", "trustRoot",
            "-k", "/Library/Keychains/System.keychain",
            rootCRT,
        ])
        guard fallback.exitCode == 0 else {
            throw CaddyTrustError.failed(result.output.isEmpty ? fallback.output : result.output)
        }
    }

    static func rootCertificatePath(callingUserHome: String) -> String {
        (callingUserHome as NSString)
            .appendingPathComponent("Library/Application Support/Caddy/pki/authorities/local/root.crt")
    }
}
