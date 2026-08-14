import Foundation

enum HostsFileError: Error, CustomStringConvertible {
    case writeFailed(String)

    var description: String {
        switch self {
        case .writeFailed(let reason): return "Failed to update /etc/hosts: \(reason)"
        }
    }
}

enum HostsFileManager {
    private static let hostsPath = "/etc/hosts"

    static func sync(domains: [String]) throws {
        try rewrite { lines in
            guard !domains.isEmpty else { return }
            lines.append(HelperConstants.hostsMarkerBegin)
            lines.append(contentsOf: domains.map { "127.0.0.1\t\($0)" })
            lines.append(HelperConstants.hostsMarkerEnd)
        }
    }

    static func removeAll() throws {
        try rewrite { _ in }
    }

    private static func rewrite(appending: (inout [String]) -> Void) throws {
        let originalContents = (try? String(contentsOfFile: hostsPath, encoding: .utf8)) ?? ""
        var lines = originalContents.components(separatedBy: "\n")

        if let beginIndex = lines.firstIndex(of: HelperConstants.hostsMarkerBegin) {
            let endIndex = lines[beginIndex...].firstIndex(of: HelperConstants.hostsMarkerEnd) ?? beginIndex
            lines.removeSubrange(beginIndex...endIndex)
        }

        while lines.last == "" {
            lines.removeLast()
        }

        appending(&lines)

        let newContents = lines.joined(separator: "\n") + "\n"
        do {
            try newContents.write(toFile: hostsPath, atomically: true, encoding: .utf8)
        } catch {
            throw HostsFileError.writeFailed(error.localizedDescription)
        }
    }
}
