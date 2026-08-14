import Foundation

enum HelperConstants {
    static let appBundleIdentifier = "dev.mahmudz.Caddock"
    static let helperBundleIdentifier = "dev.mahmudz.Caddock.Helper"
    static let machServiceName = "dev.mahmudz.Caddock.Helper"
    static let launchdLabel = "dev.mahmudz.Caddock.Helper"
    static let daemonPlistName = "dev.mahmudz.Caddock.Helper.plist"
    static let pfAnchorName = "dev.mahmudz.Caddock"
    static let teamID = "SP792GFSPZ"
    static let dnsListenPort = 53_535

    static let hostsMarkerBegin = "# BEGIN Caddock"
    static let hostsMarkerEnd = "# END Caddock"
    static let pfMarkerBegin = "# BEGIN Caddock pf"
    static let pfMarkerEnd = "# END Caddock pf"

    static let helperStateFileURL = URL(fileURLWithPath: "/Library/Application Support/Caddock/HelperState.json")
}
