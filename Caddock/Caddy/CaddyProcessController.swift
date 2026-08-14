import Foundation
import Observation

@Observable
final class CaddyProcessController: CaddyControlling {
    private static let logger = AppLogger(category: "CaddyProcessController")

    private(set) var status: CaddyStatus = .stopped

    private var process: Process?
    private var isStoppingIntentionally = false
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    private var adminClient: CaddyAdminClient {
        CaddyAdminClient(adminPort: settings.adminPort)
    }

    func start(caddyBinary: URL, caddyfileURL: URL) async {
        status = .starting

        if await adminClient.isReachable() {
            do {
                let json = try CaddyAdapter.adaptToJSON(caddyfileURL: caddyfileURL, caddyBinary: caddyBinary)
                try await adminClient.load(json)
                status = .running
                Self.logger.info("Reloaded already-running Caddy instance.")
            } catch {
                status = .failed(error.localizedDescription)
                Self.logger.error("Reload of running Caddy failed: \(error.localizedDescription)")
            }
            return
        }

        do {
            let logURL = try LogFiles.caddyLogURL()
            if settings.clearLogsOnRestart {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            } else if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let logHandle = try FileHandle(forWritingTo: logURL)
            if !settings.clearLogsOnRestart {
                logHandle.seekToEndOfFile()
            }

            let process = Process()
            process.executableURL = caddyBinary
            process.arguments = ["run", "--config", caddyfileURL.path, "--adapter", "caddyfile"]
            process.standardOutput = logHandle
            process.standardError = logHandle
            process.terminationHandler = { [weak self] proc in
                guard let self else { return }
                Task { @MainActor in
                    if self.isStoppingIntentionally {
                        self.isStoppingIntentionally = false
                        return
                    }
                    if proc.terminationStatus != 0 {
                        self.status = .failed("Caddy exited with status \(proc.terminationStatus).")
                    } else {
                        self.status = .stopped
                    }
                }
            }
            try process.run()
            self.process = process
            status = .running
            Self.logger.info("Started Caddy process (pid \(process.processIdentifier)).")
        } catch {
            status = .failed(error.localizedDescription)
            Self.logger.error("Failed to start Caddy: \(error.localizedDescription)")
        }
    }

    func reload(caddyBinary: URL, caddyfileURL: URL) async throws {
        let json = try CaddyAdapter.adaptToJSON(caddyfileURL: caddyfileURL, caddyBinary: caddyBinary)
        try await adminClient.load(json)
        status = .running
    }

    func stop() async {
        isStoppingIntentionally = true
        if await adminClient.isReachable() {
            try? await adminClient.stop()
        }
        process?.terminate()
        process = nil
        status = .stopped
    }
}
