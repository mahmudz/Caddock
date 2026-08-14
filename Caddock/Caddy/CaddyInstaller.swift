import Foundation

enum CaddyInstallerError: Error, LocalizedError {
    case brewNotFound
    case brewFailed(String)
    case processFailed(String)
    case releaseLookupFailed(String)
    case assetNotFound(String)
    case downloadFailed(String)
    case extractFailed(String)
    case verifyFailed(String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Homebrew was not found. Install it from https://brew.sh or download Caddy instead."
        case .brewFailed(let message), .processFailed(let message):
            return message
        case .releaseLookupFailed(let message):
            return "Could not look up the latest Caddy release: \(message)"
        case .assetNotFound(let arch):
            return "No macOS (\(arch)) Caddy build found in the latest GitHub release."
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .extractFailed(let message):
            return "Could not extract the Caddy archive: \(message)"
        case .verifyFailed(let message):
            return "Downloaded Caddy binary failed verification: \(message)"
        }
    }
}

enum CaddyInstaller {
    private static let brewPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    private static let githubLatestReleaseURL = URL(
        string: "https://api.github.com/repos/caddyserver/caddy/releases/latest"
    )!

    static func locateBrew() -> URL? {
        for path in brewPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return locateViaWhich("brew")
    }

    static func installWithHomebrew() async throws -> URL {
        guard let brew = locateBrew() else { throw CaddyInstallerError.brewNotFound }

        let output: String
        do {
            output = try await runProcess(
                executable: brew,
                arguments: ["install", "caddy"],
                environmentExtras: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"]
            )
        } catch let CaddyInstallerError.processFailed(message) {
            throw CaddyInstallerError.brewFailed(message)
        }

        if let binary = CaddyInstallation.locateBinary() {
            return binary
        }

        throw CaddyInstallerError.brewFailed(
            output.isEmpty
                ? "brew install caddy finished but the caddy binary was not found."
                : output
        )
    }

    static func downloadOfficialBinary(
        status: (@Sendable (String) -> Void)? = nil
    ) async throws -> URL {
        status?("Looking up latest release…")
        let (version, assetID, browserURL) = try await latestMacReleaseAsset()
        let destination = try AppPaths.managedBinaryURL()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Caddock-caddy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let archiveURL = tempDir.appendingPathComponent("caddy.tar.gz")
        status?("Downloading Caddy \(version)…")
        try await download(assetID: assetID, browserURL: browserURL, to: archiveURL)

        status?("Extracting…")
        let extractedBinary = try extractCaddyBinary(from: archiveURL, into: tempDir)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: extractedBinary, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destination.path
        )
        clearQuarantine(at: destination)

        status?("Verifying…")
        do {
            _ = try CaddyInstallation.version(of: destination)
        } catch {
            throw CaddyInstallerError.verifyFailed(error.localizedDescription)
        }

        let marker = destination.deletingLastPathComponent().appendingPathComponent("caddy.version")
        try? version.write(to: marker, atomically: true, encoding: .utf8)

        return destination
    }

    static func openBrewInstallInTerminal() throws {
        guard locateBrew() != nil else { throw CaddyInstallerError.brewNotFound }
        let script = """
        tell application "Terminal"
            activate
            do script "brew install caddy"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CaddyInstallerError.brewFailed("Could not open Terminal to run brew install caddy.")
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        struct Asset: Decodable {
            let id: Int
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case id, name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private static let downloadSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "User-Agent": "Caddock (dev.mahmudz.Caddock)",
        ]
        return URLSession(configuration: config)
    }()

    private static func latestMacReleaseAsset() async throws -> (version: String, assetID: Int, browserURL: URL) {
        var request = URLRequest(url: githubLatestReleaseURL)
        request.setValue("Caddock (dev.mahmudz.Caddock)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await downloadSession.data(for: request)
        } catch {
            throw CaddyInstallerError.releaseLookupFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CaddyInstallerError.releaseLookupFailed("GitHub API returned HTTP \(code).")
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw CaddyInstallerError.releaseLookupFailed(error.localizedDescription)
        }

        let arch = macDownloadArch()
        let suffix = "mac_\(arch).tar.gz"
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(suffix) && !$0.name.contains("buildable") }) else {
            throw CaddyInstallerError.assetNotFound(arch)
        }

        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        return (version, asset.id, asset.browserDownloadURL)
    }

    private static func macDownloadArch() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine == "arm64" ? "arm64" : "amd64"
    }

    /// Prefer the releases/assets API (api.github.com). `browser_download_url` hits github.com
    /// and is often blocked from GUI apps. Fall back to curl.
    private static func download(assetID: Int, browserURL: URL, to local: URL) async throws {
        let apiURL = URL(string: "https://api.github.com/repos/caddyserver/caddy/releases/assets/\(assetID)")!

        var apiRequest = URLRequest(url: apiURL)
        apiRequest.setValue("Caddock (dev.mahmudz.Caddock)", forHTTPHeaderField: "User-Agent")
        apiRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        apiRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        if (try? await download(request: apiRequest, to: local)) != nil {
            return
        }

        var browserRequest = URLRequest(url: browserURL)
        browserRequest.setValue("Caddock (dev.mahmudz.Caddock)", forHTTPHeaderField: "User-Agent")
        if (try? await download(request: browserRequest, to: local)) != nil {
            return
        }

        do {
            try downloadWithCurl(
                from: apiURL,
                to: local,
                headers: [
                    "Accept: application/octet-stream",
                    "X-GitHub-Api-Version: 2022-11-28",
                ]
            )
        } catch {
            try downloadWithCurl(from: browserURL, to: local, headers: [])
        }
    }

    private static func download(request: URLRequest, to local: URL) async throws {
        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await downloadSession.download(for: request)
        } catch {
            throw CaddyInstallerError.downloadFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CaddyInstallerError.downloadFailed("HTTP \(code)")
        }
        if FileManager.default.fileExists(atPath: local.path) {
            try FileManager.default.removeItem(at: local)
        }
        try FileManager.default.moveItem(at: tempURL, to: local)
    }

    private static func downloadWithCurl(from remote: URL, to local: URL, headers: [String]) throws {
        if FileManager.default.fileExists(atPath: local.path) {
            try FileManager.default.removeItem(at: local)
        }

        var arguments = [
            "--fail",
            "--location",
            "--silent",
            "--show-error",
            "--connect-timeout", "30",
            "--max-time", "600",
            "--user-agent", "Caddock (dev.mahmudz.Caddock)",
            "--output", local.path,
        ]
        for header in headers {
            arguments.append(contentsOf: ["--header", header])
        }
        arguments.append(remote.absoluteString)

        do {
            _ = try runProcessSync(
                executable: URL(fileURLWithPath: "/usr/bin/curl"),
                arguments: arguments
            )
        } catch let CaddyInstallerError.processFailed(message) {
            throw CaddyInstallerError.downloadFailed(message)
        }

        guard FileManager.default.fileExists(atPath: local.path) else {
            throw CaddyInstallerError.downloadFailed("curl did not write a file.")
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: local.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        if size < 1_000 {
            throw CaddyInstallerError.downloadFailed("Downloaded file looks too small (\(size) bytes).")
        }
    }

    private static func clearQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private static func extractCaddyBinary(from archive: URL, into directory: URL) throws -> URL {
        let extractDir = directory.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let output = try runProcessSync(
            executable: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", archive.path, "-C", extractDir.path]
        )
        let binary = extractDir.appendingPathComponent("caddy")
        guard FileManager.default.isExecutableFile(atPath: binary.path)
                || FileManager.default.fileExists(atPath: binary.path) else {
            throw CaddyInstallerError.extractFailed(
                output.isEmpty ? "Archive did not contain a caddy binary." : output
            )
        }
        return binary
    }

    private static func locateViaWhich(_ name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        environmentExtras: [String: String] = [:]
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try runProcessSync(
                        executable: executable,
                        arguments: arguments,
                        environmentExtras: environmentExtras
                    )
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @discardableResult
    private static func runProcessSync(
        executable: URL,
        arguments: [String],
        environmentExtras: [String: String] = [:]
    ) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environmentExtras {
            env[key] = value
        }
        let pathExtras = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let existing = env["PATH"] ?? ""
        env["PATH"] = (pathExtras + existing.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { result, part in
                if !result.contains(part) { result.append(part) }
            }
            .joined(separator: ":")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus != 0 {
            throw CaddyInstallerError.processFailed(
                output.isEmpty
                    ? "\(executable.lastPathComponent) exited with status \(process.terminationStatus)."
                    : output
            )
        }
        return output
    }
}
