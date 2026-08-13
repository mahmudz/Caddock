import Foundation

enum CaddyStatus: Equatable {
    case stopped
    case starting
    case running
    case failed(String)
}

@MainActor
protocol CaddyControlling: AnyObject {
    var status: CaddyStatus { get }
    func start(caddyBinary: URL, caddyfileURL: URL) async
    func reload(caddyBinary: URL, caddyfileURL: URL) async throws
    func stop() async
}

protocol PrivilegedHelperClienting: AnyObject {
    func ping() async throws -> String
    func installPFRedirect(httpPort: Int, httpsPort: Int) async throws
    func removePFRedirect() async throws
    func syncHosts(domains: [String]) async throws
    func removeHosts() async throws
    func syncResolvers(tlds: [String], dnsPort: Int) async throws
    func removeResolvers() async throws
    func uninstallAll() async throws
}

@MainActor
protocol PrivilegedHelperInstalling: AnyObject {
    var isEnabled: Bool { get }
    func refreshStatus()
}

@MainActor
protocol LocalDNSResponding: AnyObject {
    func update(tlds: [String])
    func stop()
}
