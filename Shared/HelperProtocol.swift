import Foundation

@objc protocol HelperProtocol {
    func getVersion(reply: @escaping (String) -> Void)

    func installPFRedirect(httpPort: Int, httpsPort: Int, reply: @escaping (Bool, String?) -> Void)
    func removePFRedirect(reply: @escaping (Bool, String?) -> Void)

    func syncHosts(domains: [String], reply: @escaping (Bool, String?) -> Void)
    func removeHosts(reply: @escaping (Bool, String?) -> Void)

    func syncResolvers(tlds: [String], dnsPort: Int, reply: @escaping (Bool, String?) -> Void)
    func removeResolvers(reply: @escaping (Bool, String?) -> Void)

    func trustCaddyRootCertificate(caddyBinaryPath: String, callingUserHome: String, reply: @escaping (Bool, String?) -> Void)

    func uninstallAll(reply: @escaping (Bool, String?) -> Void)
}
