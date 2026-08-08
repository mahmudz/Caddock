import Foundation
import os

final class HelperTool: NSObject, HelperProtocol {
    private static let logger = Logger(subsystem: "dev.mahmudz.CaddyManager.Helper", category: "HelperTool")

    func getVersion(reply: @escaping (String) -> Void) {
        reply("1")
    }

    func installPFRedirect(httpPort: Int, httpsPort: Int, reply: @escaping (Bool, String?) -> Void) {
        do {
            try PFRedirectManager.install(httpPort: httpPort, httpsPort: httpsPort)
            var state = HelperState.load()
            state.httpPort = httpPort
            state.httpsPort = httpsPort
            state.save()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func removePFRedirect(reply: @escaping (Bool, String?) -> Void) {
        do {
            try PFRedirectManager.remove()
            var state = HelperState.load()
            state.httpPort = nil
            state.httpsPort = nil
            state.save()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func syncHosts(domains: [String], reply: @escaping (Bool, String?) -> Void) {
        
        do {
            try HostsFileManager.sync(domains: domains)
            var state = HelperState.load()
            state.domains = domains
            state.save()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func removeHosts(reply: @escaping (Bool, String?) -> Void) {
        do {
            try HostsFileManager.removeAll()
            var state = HelperState.load()
            state.domains = []
            state.save()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func syncResolvers(tlds: [String], dnsPort: Int, reply: @escaping (Bool, String?) -> Void) {
        do {
            try ResolverManager.sync(tlds: tlds, dnsPort: dnsPort)
            var state = HelperState.load()
            state.resolverTLDs = tlds
            state.dnsPort = dnsPort
            state.save()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func removeResolvers(reply: @escaping (Bool, String?) -> Void) {
        do {
            try ResolverManager.removeAll()
            var state = HelperState.load()
            state.resolverTLDs = []
            state.dnsPort = nil
            state.save()
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func trustCaddyRootCertificate(caddyBinaryPath: String, callingUserHome: String, reply: @escaping (Bool, String?) -> Void) {
        do {
            try CaddyTrustRunner.trust(caddyBinaryPath: caddyBinaryPath, callingUserHome: callingUserHome)
            reply(true, nil)
        } catch {
            reply(false, String(describing: error))
        }
    }

    func uninstallAll(reply: @escaping (Bool, String?) -> Void) {
        var messages: [String] = []
        do { try PFRedirectManager.remove() } catch { messages.append(String(describing: error)) }
        do { try HostsFileManager.removeAll() } catch { messages.append(String(describing: error)) }
        do { try ResolverManager.removeAll() } catch { messages.append(String(describing: error)) }
        try? FileManager.default.removeItem(at: HelperConstants.helperStateFileURL)
        reply(messages.isEmpty, messages.isEmpty ? nil : messages.joined(separator: "; "))
    }

    func reapplyPersistedStateIfNeeded() {
        let state = HelperState.load()
        if let httpPort = state.httpPort, let httpsPort = state.httpsPort {
            do {
                try PFRedirectManager.install(httpPort: httpPort, httpsPort: httpsPort)
            } catch {
                Self.logger.error("Failed to reapply pf redirect: \(String(describing: error), privacy: .public)")
            }
        }
        if !state.domains.isEmpty {
            do {
                try HostsFileManager.sync(domains: state.domains)
            } catch {
                Self.logger.error("Failed to reapply hosts: \(String(describing: error), privacy: .public)")
            }
        }
        if !state.resolverTLDs.isEmpty {
            do {
                try ResolverManager.sync(
                    tlds: state.resolverTLDs,
                    dnsPort: state.dnsPort ?? HelperConstants.dnsListenPort
                )
            } catch {
                Self.logger.error("Failed to reapply resolvers: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
