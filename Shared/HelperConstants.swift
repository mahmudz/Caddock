import Foundation

enum HelperConstants {
    static let machServiceName = "dev.mahmudz.CaddyManager.Helper"
    static let daemonPlistName = "dev.mahmudz.CaddyManager.Helper.plist"
    static let launchdLabel = "dev.mahmudz.CaddyManager.Helper"
    static let helperBundleIdentifier = "dev.mahmudz.CaddyManager.Helper"
    static let pfAnchorName = "dev.mahmudz.CaddyManager"
    static let hostsMarkerBegin = "# BEGIN CaddyManager"
    static let hostsMarkerEnd = "# END CaddyManager"
    static let pfMarkerBegin = "# BEGIN CaddyManager pf"
    static let pfMarkerEnd = "# END CaddyManager pf"
    static let helperStateFileURL = URL(fileURLWithPath: "/Library/Application Support/CaddyManager/HelperState.json")
    static let dnsListenPort = 53_535
}
