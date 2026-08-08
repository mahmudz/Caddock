import Foundation

enum HelperClientError: LocalizedError {
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperFailed(let message): return message
        }
    }
}

final class HelperClient {
    func ping() async throws -> String {
        try await performReturning { proxy, reply in
            proxy.getVersion(reply: reply)
        }
    }

    func installPFRedirect(httpPort: Int, httpsPort: Int) async throws {
        try await perform { proxy, reply in
            proxy.installPFRedirect(httpPort: httpPort, httpsPort: httpsPort, reply: reply)
        }
    }

    func removePFRedirect() async throws {
        try await perform { proxy, reply in
            proxy.removePFRedirect(reply: reply)
        }
    }

    func syncHosts(domains: [String]) async throws {
        try await perform { proxy, reply in
            proxy.syncHosts(domains: domains, reply: reply)
        }
    }

    func removeHosts() async throws {
        try await perform { proxy, reply in
            proxy.removeHosts(reply: reply)
        }
    }

    func syncResolvers(tlds: [String], dnsPort: Int) async throws {
        try await perform { proxy, reply in
            proxy.syncResolvers(tlds: tlds, dnsPort: dnsPort, reply: reply)
        }
    }

    func removeResolvers() async throws {
        try await perform { proxy, reply in
            proxy.removeResolvers(reply: reply)
        }
    }

    func trustCaddyRootCertificate(caddyBinaryPath: String, callingUserHome: String) async throws {
        try await perform { proxy, reply in
            proxy.trustCaddyRootCertificate(caddyBinaryPath: caddyBinaryPath, callingUserHome: callingUserHome, reply: reply)
        }
    }

    func uninstallAll() async throws {
        try await perform { proxy, reply in
            proxy.uninstallAll(reply: reply)
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()
        return connection
    }

    private func isRetryableXPCError(_ error: Error) -> Bool {
        let message: String
        if case HelperClientError.helperFailed(let helperMessage) = error {
            message = helperMessage
        } else {
            message = error.localizedDescription
        }

        let needles = [
            "invalidated",
            "interrupted",
            "couldn’t communicate",
            "couldn't communicate",
            "could not communicate",
            "connection invalid",
            "not available",
            "no such process",
            "unable to connect",
            "could not create helper proxy",
            "xpc connection",
        ]
        let lowered = message.lowercased()
        if needles.contains(where: { lowered.contains($0) }) {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain || nsError.domain.contains("NSXPCConnection") {
            return true
        }
        return false
    }

    private func perform(_ body: @escaping (HelperProtocol, @escaping (Bool, String?) -> Void) -> Void) async throws {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await performOnce(body)
                return
            } catch {
                lastError = error
                guard attempt < 2, isRetryableXPCError(error) else { throw error }
                // 0.5s, 1.5s between attempts
                try await Task.sleep(nanoseconds: UInt64(500_000_000 * (2 * attempt + 1)))
            }
        }
        throw lastError ?? HelperClientError.helperFailed("Unknown helper error.")
    }

    private func performReturning<T>(
        _ body: @escaping (HelperProtocol, @escaping (T) -> Void) -> Void
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await performOnceReturning(body)
            } catch {
                lastError = error
                guard attempt < 2, isRetryableXPCError(error) else { throw error }
                try await Task.sleep(nanoseconds: UInt64(500_000_000 * (2 * attempt + 1)))
            }
        }
        throw lastError ?? HelperClientError.helperFailed("Unknown helper error.")
    }

    private func performOnce(_ body: @escaping (HelperProtocol, @escaping (Bool, String?) -> Void) -> Void) async throws {
        let connection = makeConnection()
        defer {
            connection.invalidationHandler = nil
            connection.interruptionHandler = nil
            connection.invalidate()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let lock = NSLock()
            var didResume = false
            func resumeOnce(_ action: () -> Void) {
                lock.lock(); defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                action()
            }

            connection.interruptionHandler = {
                resumeOnce { continuation.resume(throwing: HelperClientError.helperFailed("XPC connection interrupted.")) }
            }
            connection.invalidationHandler = {
                resumeOnce { continuation.resume(throwing: HelperClientError.helperFailed("XPC connection invalidated.")) }
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                resumeOnce { continuation.resume(throwing: error) }
            } as? HelperProtocol

            guard let proxy else {
                resumeOnce { continuation.resume(throwing: HelperClientError.helperFailed("Could not create helper proxy.")) }
                return
            }

            body(proxy) { success, message in
                resumeOnce {
                    success ? continuation.resume() : continuation.resume(throwing: HelperClientError.helperFailed(message ?? "Unknown helper error."))
                }
            }
        }
    }

    private func performOnceReturning<T>(
        _ body: @escaping (HelperProtocol, @escaping (T) -> Void) -> Void
    ) async throws -> T {
        let connection = makeConnection()
        defer {
            connection.invalidationHandler = nil
            connection.interruptionHandler = nil
            connection.invalidate()
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let lock = NSLock()
            var didResume = false
            func resumeOnce(_ action: () -> Void) {
                lock.lock(); defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                action()
            }

            connection.interruptionHandler = {
                resumeOnce { continuation.resume(throwing: HelperClientError.helperFailed("XPC connection interrupted.")) }
            }
            connection.invalidationHandler = {
                resumeOnce { continuation.resume(throwing: HelperClientError.helperFailed("XPC connection invalidated.")) }
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                resumeOnce { continuation.resume(throwing: error) }
            } as? HelperProtocol

            guard let proxy else {
                resumeOnce { continuation.resume(throwing: HelperClientError.helperFailed("Could not create helper proxy.")) }
                return
            }

            body(proxy) { value in
                resumeOnce { continuation.resume(returning: value) }
            }
        }
    }
}
