import Foundation
import Darwin

enum SocketValidator {
    /// Returns true if something accepts connections at `target`.
    /// Accepts Unix paths (`/tmp/php-fpm.sock`, `unix//tmp/php-fpm.sock`)
    /// and TCP endpoints (`127.0.0.1:9000`, `localhost:9000`).
    static func isListening(at target: String) -> Bool {
        let cleaned = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        if cleaned.hasPrefix("unix/") {
            return testUnixSocket(path: String(cleaned.dropFirst("unix/".count)))
        }
        if cleaned.hasPrefix("/") || cleaned.hasPrefix(".") {
            return testUnixSocket(path: cleaned)
        }
        if let colonIndex = cleaned.lastIndex(of: ":") {
            let host = String(cleaned[..<colonIndex])
            let portString = String(cleaned[cleaned.index(after: colonIndex)...])
            guard let port = Int(portString), (1...65535).contains(port) else { return false }
            return testNetworkSocket(host: host, port: port)
        }
        // Bare relative path (e.g. "php-fpm.sock")
        return testUnixSocket(path: cleaned)
    }
}

// MARK: - Low-level connect probes

private func testUnixSocket(path: String) -> Bool {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { Darwin.close(fd) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let pathCount = path.utf8.count
    guard pathCount > 0, pathCount < MemoryLayout.size(ofValue: address.sun_path) else {
        return false
    }

    path.withCString { src in
        withUnsafeMutablePointer(to: &address.sun_path) { dest in
            let destRaw = UnsafeMutableRawPointer(dest).assumingMemoryBound(to: Int8.self)
            strncpy(destRaw, src, pathCount)
        }
    }

    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    return result == 0
}

private func testNetworkSocket(host: String, port: Int) -> Bool {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { Darwin.close(fd) }

    guard let server = gethostbyname(host) else { return false }

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(port).bigEndian

    guard let hAddr = server.pointee.h_addr_list[0] else { return false }
    memcpy(&address.sin_addr.s_addr, hAddr, Int(server.pointee.h_length))

    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    return result == 0
}
