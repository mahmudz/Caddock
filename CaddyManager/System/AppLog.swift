import Foundation
import os

enum ManagedLogFile: String, CaseIterable, Identifiable {
    case caddy
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caddy: return "Caddy"
        case .app: return "App"
        }
    }

    func url() throws -> URL {
        switch self {
        case .caddy: return try LogFiles.caddyLogURL()
        case .app: return try LogFiles.appLogURL()
        }
    }
}

enum LogFiles {
    static func directoryURL() throws -> URL {
        let dir = try FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Logs/CaddyManager", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func caddyLogURL() throws -> URL {
        try directoryURL().appendingPathComponent("caddy.log")
    }

    static func appLogURL() throws -> URL {
        try directoryURL().appendingPathComponent("app.log")
    }
}

/// Dual-writes to `os.Logger` and `~/Library/Logs/CaddyManager/app.log`.
struct AppLogger {
    private let category: String
    private let osLogger: Logger

    init(category: String) {
        self.category = category
        self.osLogger = Logger(subsystem: "dev.mahmudz.CaddyManager", category: category)
    }

    func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
        AppLog.write(level: .debug, category: category, message: message)
    }

    func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        AppLog.write(level: .info, category: category, message: message)
    }

    func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        AppLog.write(level: .warning, category: category, message: message)
    }

    func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        AppLog.write(level: .error, category: category, message: message)
    }
}

enum AppLog {
    fileprivate enum Level: String {
        case debug, info, warning, error
    }

    private static let queue = DispatchQueue(label: "dev.mahmudz.CaddyManager.AppLog")
    private static var fileHandle: FileHandle?
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func bootstrap() {
        queue.sync {
            openFileIfNeeded()
            writeLocked(level: .info, category: "AppLog", message: "App logging started.")
        }
    }

    static func clear() throws {
        let url = try LogFiles.appLogURL()
        queue.sync {
            fileHandle?.closeFile()
            fileHandle = nil
            FileManager.default.createFile(atPath: url.path, contents: nil)
            openFileIfNeeded()
        }
    }

    fileprivate static func write(level: Level, category: String, message: String) {
        queue.async {
            openFileIfNeeded()
            writeLocked(level: level, category: category, message: message)
        }
    }

    private static func openFileIfNeeded() {
        guard fileHandle == nil else { return }
        guard let url = try? LogFiles.appLogURL() else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
    }

    private static func writeLocked(level: Level, category: String, message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) [\(category)] \(level.rawValue): \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }
}
