import Foundation

enum PFRedirectError: Error, CustomStringConvertible {
    case dryRunFailed(String)
    case commandFailed(String)

    var description: String {
        switch self {
        case .dryRunFailed(let output): return "pf.conf validation failed: \(output)"
        case .commandFailed(let output): return "pfctl command failed: \(output)"
        }
    }
}

enum PFRedirectManager {
    private static let pfConfPath = "/etc/pf.conf"
    private static let pfConfBackupPath = "/etc/pf.conf.caddymanager.bak"
    private static let anchorFilePath = "/etc/pf.anchors/\(HelperConstants.pfAnchorName)"

    static func install(httpPort: Int, httpsPort: Int) throws {
        print("PFRedirectManager::install")
//        try writeAnchorFile(httpPort: httpPort, httpsPort: httpsPort)
//        try patchPFConf(installing: true)
//        try reloadAndEnable()
    }

    static func remove() throws {
        try patchPFConf(installing: false)
        try? FileManager.default.removeItem(atPath: anchorFilePath)
        try reloadAndEnable()
    }

    private static func writeAnchorFile(httpPort: Int, httpsPort: Int) throws {
        let contents = """
        rdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 80 -> 127.0.0.1 port \(httpPort)
        rdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 443 -> 127.0.0.1 port \(httpsPort)
        """
        try contents.write(toFile: anchorFilePath, atomically: true, encoding: .utf8)
    }

    private static func patchPFConf(installing: Bool) throws {
        print("patchPFConf")
        let originalContents = (try? String(contentsOfFile: pfConfPath, encoding: .utf8)) ?? ""

        if installing && !FileManager.default.fileExists(atPath: pfConfBackupPath) {
            try originalContents.write(toFile: pfConfBackupPath, atomically: true, encoding: .utf8)
        }

        var lines = originalContents.components(separatedBy: "\n")
        removeMarkerBlock(from: &lines)

        guard installing else {
            try lines.joined(separator: "\n").write(toFile: pfConfPath, atomically: true, encoding: .utf8)
            return
        }

        let block = [
            HelperConstants.pfMarkerBegin,
            "rdr-anchor \"\(HelperConstants.pfAnchorName)\"",
            "load anchor \"\(HelperConstants.pfAnchorName)\" from \"\(anchorFilePath)\"",
            HelperConstants.pfMarkerEnd,
        ]

        let insertionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "anchor \"com.apple/*\"" })
            ?? lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("rdr-anchor") }).map { $0 + 1 }
            ?? 0

        lines.insert(contentsOf: block, at: insertionIndex)
        let newContents = lines.joined(separator: "\n")
        
        print(newContents)
        
        let tempPath = pfConfPath + ".caddymanager.tmp"
        try newContents.write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let dryRun = try ProcessRunner.run("/sbin/pfctl", ["-nf", tempPath])
        guard dryRun.exitCode == 0 else {
            throw PFRedirectError.dryRunFailed(dryRun.output)
        }

        try newContents.write(toFile: pfConfPath, atomically: true, encoding: .utf8)
    }

    private static func removeMarkerBlock(from lines: inout [String]) {
        guard let beginIndex = lines.firstIndex(of: HelperConstants.pfMarkerBegin) else { return }
        let endIndex = lines[beginIndex...].firstIndex(of: HelperConstants.pfMarkerEnd) ?? beginIndex
        lines.removeSubrange(beginIndex...endIndex)
    }

    private static func reloadAndEnable() throws {
        print("reloadAndEnable")
        let load = try ProcessRunner.run("/sbin/pfctl", ["-f", pfConfPath])
        guard load.exitCode == 0 else {
            throw PFRedirectError.commandFailed(load.output)
        }

        let enable = try ProcessRunner.run("/sbin/pfctl", ["-e"])
        if enable.exitCode != 0 && !enable.output.contains("already enabled") {
            throw PFRedirectError.commandFailed(enable.output)
        }
    }
}
