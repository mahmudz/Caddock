import Foundation

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

// Listen first, then reapply persisted pf/hosts/resolvers so reboot recovery
// cannot delay the first XPC accept.
DispatchQueue.main.async {
    HelperTool().reapplyPersistedStateIfNeeded()
}

RunLoop.current.run()
