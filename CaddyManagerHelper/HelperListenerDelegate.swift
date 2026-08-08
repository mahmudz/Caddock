import Foundation
import os
import Security

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private static let logger = Logger(subsystem: "dev.mahmudz.CaddyManager.Helper", category: "XPC")

    /// Retained for the lifetime of the daemon so XPC does not export a dangling object.
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

    /// Accepts connections from any process signed with the main app's bundle identifier. This
    /// project has no Developer ID identity yet, so local/Automatic builds use Apple Development
    /// signing — an overly strict "anchor apple generic + Developer ID" clause would reject
    /// valid debug builds.
    private static func isConnectionFromMainApp(_ connection: NSXPCConnection) -> Bool {
        guard let code = copyGuestCode(for: connection) else {
            return false
        }

        var requirement: SecRequirement?
        let requirementString = "identifier \"dev.mahmudz.CaddyManager\"" as CFString
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

        // Prefer audit token via KVC — property exists in ObjC but is often absent from the Swift overlay.
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
