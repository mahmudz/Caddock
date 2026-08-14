import Foundation

enum CaddyAdminClientError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Caddy admin API."
        case .httpError(let code, let body): return "Caddy admin API returned \(code): \(body)"
        }
    }
}

struct CaddyAdminClient {
    let adminPort: Int

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(adminPort)") ?? URL(fileURLWithPath: "/")
    }

    func isReachable() async -> Bool {
        (try? await currentConfig()) != nil
    }

    func load(_ configJSON: Data) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("load"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = configJSON
        try await send(request)
    }

    func stop() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("stop"))
        request.httpMethod = "POST"
        try await send(request)
    }

    func currentConfig() async throws -> Data {
        let request = URLRequest(url: baseURL.appendingPathComponent("config/"))
        return try await send(request)
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CaddyAdminClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CaddyAdminClientError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
