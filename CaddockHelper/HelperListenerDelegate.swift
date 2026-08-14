import Foundation
import os
import Security

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private static let logger = Logger(subsystem: HelperConstants.helperBundleIdentifier, category: "XPC")

    private let tool = HelperTool()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard Self.isConnectionFromMainApp(newConnection) else {
            Self.logger.error("Rejected XPC connection from pid \(newConnection.processIdentifier, privacy: .public)")
            newConnection.invalidate()
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = tool
        newConnection.resume()
        Self.logger.info("Accepted XPC connection from pid \(newConnection.processIdentifier, privacy: .public)")
        return true
    }

    /// Require the peer to be signed as the main app. Team ID is required when present
    /// so random binaries with a colliding identifier are rejected; Apple Development
    /// and Developer ID from the same team both satisfy `certificate leaf[subject.OU]`.
    private static func isConnectionFromMainApp(_ connection: NSXPCConnection) -> Bool {
        guard let code = copyGuestCode(for: connection) else {
            return false
        }

        let requirementString = """
        identifier "\(HelperConstants.appBundleIdentifier)" and certificate leaf[subject.OU] = "\(HelperConstants.teamID)"
        """ as CFString

        var requirement: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(requirementString, [], &requirement)
        guard reqStatus == errSecSuccess, let requirement else {
            logger.error("SecRequirementCreateWithString failed: \(reqStatus, privacy: .public)")
            return false
        }

        let checkStatus = SecCodeCheckValidity(code, [], requirement)
        if checkStatus != errSecSuccess {
            logger.error("SecCodeCheckValidity failed: \(checkStatus, privacy: .public)")
            return false
        }
        return true
    }

    private static func copyGuestCode(for connection: NSXPCConnection) -> SecCode? {
        var code: SecCode?

        if let tokenData = auditTokenData(from: connection) {
            let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
            let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
            if status == errSecSuccess, let code {
                return code
            }
            logger.error("SecCodeCopyGuestWithAttributes(audit) failed: \(status, privacy: .public); falling back to pid")
        }

        let pid = connection.processIdentifier
        let pidAttributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        let pidStatus = SecCodeCopyGuestWithAttributes(nil, pidAttributes, [], &code)
        if pidStatus == errSecSuccess, let code {
            return code
        }
        logger.error("SecCodeCopyGuestWithAttributes(pid \(pid, privacy: .public)) failed: \(pidStatus, privacy: .public)")
        return nil
    }

    private static func auditTokenData(from connection: NSXPCConnection) -> Data? {
        guard let value = connection.value(forKey: "auditToken") else { return nil }
        if let data = value as? Data { return data }
        if let data = value as? NSData { return data as Data }
        return nil
    }
}
