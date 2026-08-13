import Foundation
import Network
import Observation

@Observable
final class LocalDNSResponder: LocalDNSResponding {
    private static let logger = AppLogger(category: "LocalDNS")

    private(set) var isRunning = false
    private(set) var lastError: String?

    private var listener: NWListener?
    private var tlds: Set<String> = []
    private let queue = DispatchQueue(label: "dev.mahmudz.CaddyManager.dns")

    func update(tlds: [String]) {
        self.tlds = Set(tlds.map { $0.lowercased() }.filter { !$0.isEmpty })
        if self.tlds.isEmpty {
            stop()
        } else if !isRunning {
            start()
        }
    }

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: UInt16(HelperConstants.dnsListenPort)) else { return }
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.lastError = nil
                    Self.logger.info("DNS responder listening on 127.0.0.1:\(HelperConstants.dnsListenPort)")
                case .failed(let error):
                    self?.isRunning = false
                    self?.lastError = error.localizedDescription
                    Self.logger.error("DNS responder failed: \(error.localizedDescription)")
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Failed to start DNS responder: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receiveMessage { [weak self] data, _, _, _ in
            defer { connection.cancel() }
            guard let self, let data, !data.isEmpty else { return }
            guard let response = self.buildResponse(for: data) else { return }
            connection.send(content: response, completion: .contentProcessed { _ in })
        }
    }

    private func buildResponse(for request: Data) -> Data? {
        guard request.count >= 12 else { return nil }
        let questionCount = Int(request[4]) << 8 | Int(request[5])
        guard questionCount >= 1 else { return nil }

        var offset = 12
        guard let (name, nameEnd) = parseName(request, offset: offset) else { return nil }
        offset = nameEnd
        guard offset + 4 <= request.count else { return nil }
        let qtype = Int(request[offset]) << 8 | Int(request[offset + 1])
        offset += 4

        let lower = name.lowercased()
        let queryTLD = lower.split(separator: ".").last.map(String.init) ?? ""
        guard tlds.contains(queryTLD) else {
            return nxdomainResponse(copyingHeaderFrom: request, questionBytes: request[12..<offset])
        }

        if qtype == 28 {
            return emptySuccessResponse(copyingHeaderFrom: request, questionBytes: request[12..<offset])
        }
        guard qtype == 1 else {
            return emptySuccessResponse(copyingHeaderFrom: request, questionBytes: request[12..<offset])
        }

        var response = Data()
        response.append(request[0])
        response.append(request[1])
        response.append(0x81)
        response.append(0x80)
        response.append(contentsOf: [0x00, 0x01])
        response.append(contentsOf: [0x00, 0x01])
        response.append(contentsOf: [0x00, 0x00])
        response.append(contentsOf: [0x00, 0x00])
        response.append(request[12..<offset])
        response.append(contentsOf: [0xC0, 0x0C])
        response.append(contentsOf: [0x00, 0x01])
        response.append(contentsOf: [0x00, 0x01])
        response.append(contentsOf: [0x00, 0x00, 0x00, 0x3C])
        response.append(contentsOf: [0x00, 0x04])
        response.append(contentsOf: [127, 0, 0, 1])
        return response
    }

    private func emptySuccessResponse(copyingHeaderFrom request: Data, questionBytes: Data.SubSequence) -> Data {
        var response = Data()
        response.append(request[0])
        response.append(request[1])
        response.append(0x81)
        response.append(0x80)
        response.append(contentsOf: [0x00, 0x01])
        response.append(contentsOf: [0x00, 0x00])
        response.append(contentsOf: [0x00, 0x00])
        response.append(contentsOf: [0x00, 0x00])
        response.append(questionBytes)
        return response
    }

    private func nxdomainResponse(copyingHeaderFrom request: Data, questionBytes: Data.SubSequence) -> Data {
        var response = Data()
        response.append(request[0])
        response.append(request[1])
        response.append(0x81)
        response.append(0x83)
        response.append(contentsOf: [0x00, 0x01])
        response.append(contentsOf: [0x00, 0x00])
        response.append(contentsOf: [0x00, 0x00])
        response.append(contentsOf: [0x00, 0x00])
        response.append(questionBytes)
        return response
    }

    private func parseName(_ data: Data, offset: Int) -> (String, Int)? {
        var labels: [String] = []
        var i = offset
        while i < data.count {
            let length = Int(data[i])
            if length == 0 {
                return (labels.joined(separator: "."), i + 1)
            }
            if length & 0xC0 == 0xC0 {
                return nil
            }
            guard i + 1 + length <= data.count else { return nil }
            let labelData = data[(i + 1)..<(i + 1 + length)]
            guard let label = String(data: labelData, encoding: .utf8) else { return nil }
            labels.append(label)
            i += 1 + length
        }
        return nil
    }
}
