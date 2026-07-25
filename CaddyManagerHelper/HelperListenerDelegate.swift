import Foundation
import Security

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard Self.isConnectionFromMainApp(newConnection) else {
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = HelperTool()
        newConnection.resume()
        return true
    }

    /// Accepts connections from any process signed with the main app's bundle identifier. This
    /// project has no Developer ID identity yet, so local/Automatic builds are ad-hoc signed
    /// (no certificate chain at all) -- an "anchor apple generic" clause would reject every
    /// connection unconditionally. Once a Developer ID identity exists, tighten this with a
    /// team identifier / anchor check.
    private static func isConnectionFromMainApp(_ connection: NSXPCConnection) -> Bool {
        print("isConnectionFromMainApp")
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else {
            return false
        }

        var requirement: SecRequirement?
        let requirementString = "identifier \"dev.mahmudz.CaddyManager\"" as CFString
        guard SecRequirementCreateWithString(requirementString, [], &requirement) == errSecSuccess, let requirement else {
            return false
        }

        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
