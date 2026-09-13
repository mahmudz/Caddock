import Darwin
import Foundation
import Observation

@Observable
final class LocalDNSResponder: LocalDNSResponding {
    private static let logger = AppLogger(category: "LocalDNS")

    private(set) var isRunning = false
    private(set) var lastError: String?

    private var tlds: Set<String> = []
    private let queue = DispatchQueue(label: "dev.mahmudz.Caddock.dns")
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?

    func update(tlds: [String]) {
        self.tlds = Set(tlds.map { $0.lowercased() }.filter { !$0.isEmpty })
        if self.tlds.isEmpty {
            stop()
        } else if !isRunning {
            start()
        }
    }

    func start() {
        stop()
        do {
            let fd = try Self.bindLoopbackIPv4(port: UInt16(HelperConstants.dnsListenPort))
            socketFD = fd

            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.readAndReply()
            }
            source.setCancelHandler {
                Darwin.close(fd)
            }
            source.resume()
            readSource = source
            isRunning = true
            lastError = nil
            Self.logger.info("DNS responder listening on 127.0.0.1:\(HelperConstants.dnsListenPort)")
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Failed to start DNS responder: \(error.localizedDescription)")
        }
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        socketFD = -1
        isRunning = false
    }

    private func readAndReply() {
        let fd = socketFD
        guard fd >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 2048)
        var addr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = buffer.withUnsafeMutableBytes { raw in
            withUnsafeMutablePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    recvfrom(fd, raw.baseAddress, raw.count, 0, sockPtr, &addrLen)
                }
            }
        }
        guard received > 0 else { return }

        let request = Data(buffer.prefix(received))
        guard let response = buildResponse(for: request) else { return }

        _ = response.withUnsafeBytes { raw in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    sendto(fd, raw.baseAddress, response.count, 0, sockPtr, addrLen)
                }
            }
        }
    }

    private static func bindLoopbackIPv4(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return fd
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
