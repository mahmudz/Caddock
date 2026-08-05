import Foundation

enum ResolverManagerError: Error, CustomStringConvertible {
    case writeFailed(String)

    var description: String {
        switch self {
        case .writeFailed(let reason): return "Failed to update /etc/resolver: \(reason)"
        }
    }
}

enum ResolverManager {
    private static let resolverDirectory = "/etc/resolver"
    private static let managedMarker = "# Managed by CaddyManager"

    static func sync(tlds: [String], dnsPort: Int) throws {
        try FileManager.default.createDirectory(atPath: resolverDirectory, withIntermediateDirectories: true)

        let desired = Set(tlds.map { $0.lowercased() }.filter { !$0.isEmpty })
        let existingManaged = managedTLDs()

        for tld in existingManaged.subtracting(desired) {
            try removeFile(for: tld)
        }

        for tld in desired {
            let contents = """
            \(managedMarker)
            nameserver 127.0.0.1
            port \(dnsPort)

            """
            let path = resolverPath(for: tld)
            do {
                try contents.write(toFile: path, atomically: true, encoding: .utf8)
            } catch {
                throw ResolverManagerError.writeFailed(error.localizedDescription)
            }
        }
    }

    static func removeAll() throws {
        for tld in managedTLDs() {
            try removeFile(for: tld)
        }
    }

    private static func managedTLDs() -> Set<String> {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: resolverDirectory) else {
            return []
        }
        var result = Set<String>()
        for file in files {
            let path = (resolverDirectory as NSString).appendingPathComponent(file)
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
                  contents.contains(managedMarker) else { continue }
            result.insert(file.lowercased())
        }
        return result
    }

    private static func resolverPath(for tld: String) -> String {
        (resolverDirectory as NSString).appendingPathComponent(tld.lowercased())
    }

    private static func removeFile(for tld: String) throws {
        let path = resolverPath(for: tld)
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            throw ResolverManagerError.writeFailed(error.localizedDescription)
        }
    }
}
