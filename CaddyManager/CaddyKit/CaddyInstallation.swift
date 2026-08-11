import Foundation

enum CaddyInstallationError: Error, LocalizedError {
    case binaryNotFound
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "Caddy binary not found."
        case .processFailed(let message): return message
        }
    }
}

enum CaddyInstallation {
    private static let knownPaths = [
        "/opt/homebrew/bin/caddy",
        "/usr/local/bin/caddy",
    ]

    static func locateBinary(override: String? = nil) -> URL? {
        if let override, FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        for path in knownPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let managed = try? CaddyInstaller.managedBinaryURL(),
           FileManager.default.isExecutableFile(atPath: managed.path) {
            return managed
        }
        return locateViaWhich()
    }

    private static func locateViaWhich() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["caddy"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }

    static func version(of binary: URL) throws -> String {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw CaddyInstallationError.processFailed(output)
        }
        return output
    }
}
