import Foundation
import Observation

@Observable
final class AppSettings {
    private enum Keys {
        static let caddyBinaryPathOverride = "caddyBinaryPathOverride"
        static let httpPort = "httpPort"
        static let httpsPort = "httpsPort"
        static let adminPort = "adminPort"
        static let launchAtLogin = "launchAtLogin"
    }

    private let defaults: UserDefaults

    var caddyBinaryPathOverride: String? {
        didSet { defaults.set(caddyBinaryPathOverride, forKey: Keys.caddyBinaryPathOverride) }
    }

    var httpPort: Int {
        didSet { defaults.set(httpPort, forKey: Keys.httpPort) }
    }

    var httpsPort: Int {
        didSet { defaults.set(httpsPort, forKey: Keys.httpsPort) }
    }

    var adminPort: Int {
        didSet { defaults.set(adminPort, forKey: Keys.adminPort) }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.caddyBinaryPathOverride = defaults.string(forKey: Keys.caddyBinaryPathOverride)
        self.httpPort = defaults.object(forKey: Keys.httpPort) as? Int ?? 8880
        self.httpsPort = defaults.object(forKey: Keys.httpsPort) as? Int ?? 8843
        self.adminPort = defaults.object(forKey: Keys.adminPort) as? Int ?? 2019
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    }
}
