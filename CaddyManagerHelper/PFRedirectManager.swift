import Foundation

enum PFRedirectError: Error, CustomStringConvertible {
    case dryRunFailed(String)
    case commandFailed(String)

    var description: String {
        switch self {
        case .dryRunFailed(let output): return "pf.conf validation failed: \(sanitizedPFCTLOutput(output))"
        case .commandFailed(let output): return "pfctl command failed: \(sanitizedPFCTLOutput(output))"
        }
    }
}

/// Strip the boilerplate macOS warning that always accompanies `pfctl -f` / `-nf`.
private func sanitizedPFCTLOutput(_ output: String) -> String {
    output
        .components(separatedBy: "\n")
        .filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return false }
            if trimmed.hasPrefix("pfctl: Use of -f option") { return false }
            if trimmed.hasPrefix("present in the main ruleset") { return false }
            if trimmed.hasPrefix("at startup.") { return false }
            if trimmed.hasPrefix("See /etc/pf.conf") { return false }
            if trimmed.hasPrefix("No ALTQ support") { return false }
            if trimmed.hasPrefix("ALTQ related functions") { return false }
            return true
        }
        .joined(separator: "\n")
}

enum PFRedirectManager {
    private static let pfConfPath = "/etc/pf.conf"
    private static let pfConfBackupPath = "/etc/pf.conf.caddymanager.bak"
    private static let anchorFilePath = "/etc/pf.anchors/\(HelperConstants.pfAnchorName)"
    private static let anchorName = HelperConstants.pfAnchorName

    // Separate markers so rdr-anchor stays in the translation section and
    // optional load stays at end of file (never between Apple's anchors).
    private static let rdrMarkerBegin = "# BEGIN CaddyManager pf rdr"
    private static let rdrMarkerEnd = "# END CaddyManager pf rdr"
    private static let loadMarkerBegin = "# BEGIN CaddyManager pf load"
    private static let loadMarkerEnd = "# END CaddyManager pf load"

    static func install(httpPort: Int, httpsPort: Int) throws {
        try writeAnchorFile(httpPort: httpPort, httpsPort: httpsPort)
        let pfConfChanged = try ensurePFConfAnchorPoint()
        if pfConfChanged {
            try reloadMainRuleset()
        }
        try loadAnchorRules()
        try enablePF()
    }

    static func remove() throws {
        // Flush our anchor first so rules disappear even if pf.conf edit fails.
        _ = try? ProcessRunner.run("/sbin/pfctl", ["-a", anchorName, "-F", "all"])
        try removePFConfPatches()
        try? FileManager.default.removeItem(atPath: anchorFilePath)
        try reloadMainRuleset()
    }

    // MARK: - Anchor file

    private static func writeAnchorFile(httpPort: Int, httpsPort: Int) throws {
        let contents = """
        rdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 80 -> 127.0.0.1 port \(httpPort)
        rdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 443 -> 127.0.0.1 port \(httpsPort)

        """
        try contents.write(toFile: anchorFilePath, atomically: true, encoding: .utf8)
    }

    private static func loadAnchorRules() throws {
        // Validate anchor rules in isolation under the named anchor, then load.
        let dryRun = try ProcessRunner.run("/sbin/pfctl", ["-a", anchorName, "-nf", anchorFilePath])
        guard dryRun.exitCode == 0 else {
            throw PFRedirectError.dryRunFailed(dryRun.output)
        }

        let load = try ProcessRunner.run("/sbin/pfctl", ["-a", anchorName, "-f", anchorFilePath])
        guard load.exitCode == 0 else {
            throw PFRedirectError.commandFailed(load.output)
        }
    }

    // MARK: - pf.conf patching

    /// Ensures `rdr-anchor "…"` sits with Apple's translation anchors.
    /// Returns true if /etc/pf.conf was modified.
    @discardableResult
    private static func ensurePFConfAnchorPoint() throws -> Bool {
        let originalContents = (try? String(contentsOfFile: pfConfPath, encoding: .utf8)) ?? ""

        if !FileManager.default.fileExists(atPath: pfConfBackupPath) {
            try originalContents.write(toFile: pfConfBackupPath, atomically: true, encoding: .utf8)
        }

        var lines = originalContents.components(separatedBy: "\n")
        // Remove any prior CaddyManager blocks (old combined format + new split format).
        removeMarkerBlock(from: &lines, begin: HelperConstants.pfMarkerBegin, end: HelperConstants.pfMarkerEnd)
        removeMarkerBlock(from: &lines, begin: rdrMarkerBegin, end: rdrMarkerEnd)
        removeMarkerBlock(from: &lines, begin: loadMarkerBegin, end: loadMarkerEnd)

        let rdrBlock = [
            rdrMarkerBegin,
            "rdr-anchor \"\(anchorName)\"",
            rdrMarkerEnd,
        ]

        // Place immediately after Apple's rdr-anchor so we stay in the translation section.
        if let appleRdr = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "rdr-anchor \"com.apple/*\""
        }) {
            lines.insert(contentsOf: rdrBlock, at: appleRdr + 1)
        } else if let lastRdr = lines.lastIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("rdr-anchor")
        }) {
            lines.insert(contentsOf: rdrBlock, at: lastRdr + 1)
        } else if let appleAnchor = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "anchor \"com.apple/*\""
        }) {
            // Fallback: before filter anchors.
            lines.insert(contentsOf: rdrBlock, at: appleAnchor)
        } else {
            lines.append(contentsOf: rdrBlock)
        }

        // Do NOT put `load anchor` in pf.conf — populate via `pfctl -a … -f` instead.
        // That avoids "load" sitting between translation and filter sections (syntax error
        // on modern macOS) and lets port changes reload only our anchor.

        let newContents = lines.joined(separator: "\n")
        if newContents == originalContents {
            return false
        }

        let tempPath = pfConfPath + ".caddymanager.tmp"
        try newContents.write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let dryRun = try ProcessRunner.run("/sbin/pfctl", ["-nf", tempPath])
        guard dryRun.exitCode == 0 else {
            throw PFRedirectError.dryRunFailed(dryRun.output)
        }

        try newContents.write(toFile: pfConfPath, atomically: true, encoding: .utf8)
        return true
    }

    private static func removePFConfPatches() throws {
        let originalContents = (try? String(contentsOfFile: pfConfPath, encoding: .utf8)) ?? ""
        var lines = originalContents.components(separatedBy: "\n")
        removeMarkerBlock(from: &lines, begin: HelperConstants.pfMarkerBegin, end: HelperConstants.pfMarkerEnd)
        removeMarkerBlock(from: &lines, begin: rdrMarkerBegin, end: rdrMarkerEnd)
        removeMarkerBlock(from: &lines, begin: loadMarkerBegin, end: loadMarkerEnd)
        let newContents = lines.joined(separator: "\n")
        guard newContents != originalContents else { return }
        try newContents.write(toFile: pfConfPath, atomically: true, encoding: .utf8)
    }

    private static func removeMarkerBlock(from lines: inout [String], begin: String, end: String) {
        while let beginIndex = lines.firstIndex(of: begin) {
            let endIndex = lines[beginIndex...].firstIndex(of: end) ?? beginIndex
            lines.removeSubrange(beginIndex...endIndex)
        }
    }

    // MARK: - pfctl helpers

    private static func reloadMainRuleset() throws {
        let load = try ProcessRunner.run("/sbin/pfctl", ["-f", pfConfPath])
        guard load.exitCode == 0 else {
            throw PFRedirectError.commandFailed(load.output)
        }
    }

    private static func enablePF() throws {
        let enable = try ProcessRunner.run("/sbin/pfctl", ["-e"])
        if enable.exitCode != 0 && !enable.output.contains("already enabled") {
            throw PFRedirectError.commandFailed(enable.output)
        }
    }
}
