import Foundation

struct ProcessResult {
    let exitCode: Int32
    let output: String
}

enum ProcessRunner {
    @discardableResult
    static func run(_ executablePath: String, _ arguments: [String], environment: [String: String]? = nil) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, output: output)
    }
}
