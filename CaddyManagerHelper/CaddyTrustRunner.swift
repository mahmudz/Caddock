import Foundation

enum CaddyTrustError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let output): return "caddy trust failed: \(output)"
        }
    }
}

enum CaddyTrustRunner {
    static func trust(caddyBinaryPath: String, callingUserHome: String) throws {
        let result = try ProcessRunner.run(
            caddyBinaryPath,
            ["trust"],
            environment: ["HOME": callingUserHome, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        )
        guard result.exitCode == 0 else {
            throw CaddyTrustError.failed(result.output)
        }
    }
}
