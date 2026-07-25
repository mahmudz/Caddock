import Foundation

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

HelperTool().reapplyPersistedStateIfNeeded()

RunLoop.current.run()
