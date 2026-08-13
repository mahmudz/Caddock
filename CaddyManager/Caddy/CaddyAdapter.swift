import Foundation

enum CaddyAdapterError: Error, LocalizedError {
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let message): return message
        }
    }
}

enum CaddyAdapter {
    static func adaptToJSON(caddyfileURL: URL, caddyBinary: URL) throws -> Data {
        let process = Process()
        process.executableURL = caddyBinary
        process.arguments = ["adapt", "--config", caddyfileURL.path, "--adapter", "caddyfile", "--pretty"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8) ?? "caddy adapt failed"
            throw CaddyAdapterError.processFailed(message)
        }
        return outData
    }
}
