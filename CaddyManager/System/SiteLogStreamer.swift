import Combine
import Foundation

/// Streams per-vhost log output from a file or `docker logs`.
@MainActor
final class SiteLogStreamer: ObservableObject {
    @Published var text: String = ""
    @Published var errorMessage: String?

    private var process: Process?
    private var pipe: Pipe?
    private var readabilityHandler: ((FileHandle) -> Void)?

    func start(source: VhostLogSource) {
        stop()
        text = ""
        errorMessage = nil

        switch source.kind {
        case .none:
            errorMessage = "No log source configured."
        case .file:
            startFile(source)
        case .docker:
            startDocker(source)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
    }

    private func startFile(_ source: VhostLogSource) {
        guard let path = source.filePath?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
            errorMessage = "Log file path is empty."
            return
        }

        var args = ["-n", "\(source.linesFromEnd ?? 100)"]
        if source.followFile {
            args.append("-F")
        }
        args.append(path)
        launch("/usr/bin/tail", args: args)
    }

    private func startDocker(_ source: VhostLogSource) {
        guard let container = source.dockerContainer?.trimmingCharacters(in: .whitespaces), !container.isEmpty else {
            errorMessage = "Docker container is empty."
            return
        }

        var args = ["logs"]
        if source.dockerFollow { args.append("-f") }
        if source.dockerTimestamps { args.append("-t") }
        args.append("--tail=\(min(max(source.dockerTail, 1), 500))")
        args.append(container)

        let docker = locateDocker() ?? "/usr/local/bin/docker"
        launch(docker, args: args)
    }

    private func locateDocker() -> String? {
        let candidates = [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "/usr/bin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func launch(_ executable: String, args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        self.process = process
        self.pipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.text.append(chunk)
                if let self, self.text.count > 500_000 {
                    self.text = String(self.text.suffix(400_000))
                }
            }
        }

        do {
            try process.run()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    deinit {
        process?.terminate()
        pipe?.fileHandleForReading.readabilityHandler = nil
    }
}
