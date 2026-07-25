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
    func installPFRedirect(httpPort: Int, httpsPort: Int) async throws {
        try await call { proxy, reply in
            proxy.installPFRedirect(httpPort: httpPort, httpsPort: httpsPort, reply: reply)
        }
    }

    func removePFRedirect() async throws {
        try await call { proxy, reply in
            proxy.removePFRedirect(reply: reply)
        }
    }

    func syncHosts(domains: [String]) async throws {
        try await call { proxy, reply in
            proxy.syncHosts(domains: domains, reply: reply)
        }
    }

    func removeHosts() async throws {
        try await call { proxy, reply in
            proxy.removeHosts(reply: reply)
        }
    }

    func trustCaddyRootCertificate(caddyBinaryPath: String, callingUserHome: String) async throws {
        try await call { proxy, reply in
            proxy.trustCaddyRootCertificate(caddyBinaryPath: caddyBinaryPath, callingUserHome: callingUserHome, reply: reply)
        }
    }

    func uninstallAll() async throws {
        try await call { proxy, reply in
            proxy.uninstallAll(reply: reply)
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.resume()
        return connection
    }

    private func call(_ body: @escaping (HelperProtocol, @escaping (Bool, String?) -> Void) -> Void) async throws {
        let connection = makeConnection()
        defer { connection.invalidate() }

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
}
