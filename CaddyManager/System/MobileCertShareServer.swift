import Darwin
import Foundation
import Network
import Observation
import os

@Observable
final class MobileCertShareServer {
    private static let logger = Logger(subsystem: "dev.mahmudz.CaddyManager", category: "MobileCertShare")

    private(set) var isRunning = false
    private(set) var downloadURL: URL?
    private(set) var lastError: String?

    private var listener: NWListener?
    private var certData: Data = Data()
    private let queue = DispatchQueue(label: "dev.mahmudz.CaddyManager.mobile-cert")

    func start() {
        stop()
        lastError = nil

        let certURL = CertificateStatusChecker.rootCertificateURL
        guard let data = try? Data(contentsOf: certURL), !data.isEmpty else {
            lastError = "Root certificate not found. Start Caddy with a TLS-enabled site first."
            return
        }
        certData = data

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: .any)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                    if let port = listener.port?.rawValue,
                       let ip = Self.localIPv4Address() {
                        self?.downloadURL = URL(string: "http://\(ip):\(port)/CaddyManager-Root-CA.crt")
                    } else if let port = listener.port?.rawValue {
                        self?.downloadURL = URL(string: "http://127.0.0.1:\(port)/CaddyManager-Root-CA.crt")
                    }
                    Self.logger.info("Mobile cert server ready at \(self?.downloadURL?.absoluteString ?? "?", privacy: .public)")
                case .failed(let error):
                    self?.isRunning = false
                    self?.lastError = error.localizedDescription
                case .cancelled:
                    self?.isRunning = false
                    self?.downloadURL = nil
                default:
                    break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        downloadURL = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let path = Self.requestPath(from: data)
            let body: Data
            let contentType: String
            let status: String
            if path == "/" || path.hasSuffix(".crt") || path.isEmpty {
                body = self.certData
                contentType = "application/x-x509-ca-cert"
                status = "200 OK"
            } else {
                body = Data("Not Found\n".utf8)
                contentType = "text/plain"
                status = "404 Not Found"
            }

            var response = Data()
            let header = """
            HTTP/1.1 \(status)\r
            Content-Type: \(contentType)\r
            Content-Length: \(body.count)\r
            Connection: close\r
            Content-Disposition: attachment; filename="CaddyManager-Root-CA.crt"\r
            \r

            """
            response.append(Data(header.utf8))
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private static func requestPath(from data: Data?) -> String {
        guard let data, let text = String(data: data, encoding: .utf8) else { return "/" }
        let firstLine = text.split(separator: "\r\n", maxSplits: 1).first ?? Substring(text)
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
    }

    private static func localIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name == "wlan0" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            let ip = String(cString: hostname)
            if ip.hasPrefix("127.") { continue }
            address = ip
            break
        }
        return address
    }
}
