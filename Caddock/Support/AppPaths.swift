import Foundation

enum AppPaths {
    static func supportDirectory() throws -> URL {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Caddock", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func caddyDirectory() throws -> URL {
        let dir = try supportDirectory().appendingPathComponent("Caddy", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func binDirectory() throws -> URL {
        let dir = try supportDirectory().appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func vhostsFileURL() throws -> URL {
        try supportDirectory().appendingPathComponent("vhosts.json")
    }

    static func caddyfileURL() throws -> URL {
        try caddyDirectory().appendingPathComponent("Caddyfile")
    }

    static func managedBinaryURL() throws -> URL {
        try binDirectory().appendingPathComponent("caddy", isDirectory: false)
    }

    static var caddyPKIRootCertificateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Caddy/pki/authorities/local/root.crt")
    }
}
