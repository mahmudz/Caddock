import Foundation

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

// Do not block before the run loop — otherwise the first XPC accept is delayed/raced
// while pfctl/hosts reapply runs, and clients see "XPC connection invalidated".
DispatchQueue.main.async {
    HelperTool().reapplyPersistedStateIfNeeded()
}

RunLoop.current.run()
