import XCTest
@testable import Caddock

@MainActor
final class CaddyConfigBuilderTests: XCTestCase {
    private var suiteName: String!
    private var settings: AppSettings!

    override func setUp() {
        super.setUp()
        suiteName = "dev.mahmudz.Caddock.tests.config.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettings(defaults: defaults)
    }

    override func tearDown() {
        if let suiteName {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        settings = nil
        suiteName = nil
        super.tearDown()
    }

    func testGlobalOptionsIncludeHttpHttpsAndAdminPorts() {
        settings.httpPort = 8880
        settings.httpsPort = 8843
        settings.adminPort = 2019

        let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: [], settings: settings)

        XCTAssertTrue(caddyfile.contains("http_port 8880"))
        XCTAssertTrue(caddyfile.contains("https_port 8843"))
        XCTAssertTrue(caddyfile.contains("admin 127.0.0.1:2019"))
    }

    func testDisabledVhostsAreOmitted() {
        let enabled = Vhost(
            domain: "live.test",
            kind: .staticSite,
            documentRoot: "/tmp/live",
            isEnabled: true
        )
        let disabled = Vhost(
            domain: "off.test",
            kind: .staticSite,
            documentRoot: "/tmp/off",
            isEnabled: false
        )

        let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: [enabled, disabled], settings: settings)

        XCTAssertTrue(caddyfile.contains("live.test"))
        XCTAssertFalse(caddyfile.contains("off.test"))
    }

    func testSSLOnUsesDomainAndTlsInternal() {
        let vhost = Vhost(
            domain: "secure.test",
            kind: .staticSite,
            documentRoot: "/tmp/secure",
            sslEnabled: true
        )

        let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: [vhost], settings: settings)

        XCTAssertTrue(caddyfile.contains("secure.test {"))
        XCTAssertTrue(caddyfile.contains("tls internal"))
        XCTAssertFalse(caddyfile.contains("http://secure.test"))
    }

    func testSSLOffUsesHttpAddressAndOmitsTls() {
        let vhost = Vhost(
            domain: "plain.test",
            kind: .staticSite,
            documentRoot: "/tmp/plain",
            sslEnabled: false
        )

        let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: [vhost], settings: settings)

        XCTAssertTrue(caddyfile.contains("http://plain.test {"))
        XCTAssertFalse(caddyfile.contains("tls internal"))
    }

    func testAliasesShareOneSiteBlock() {
        let vhost = Vhost(
            domain: "myproject.test",
            aliases: ["www.myproject.test"],
            kind: .staticSite,
            documentRoot: "/tmp/myproject"
        )

        let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: [vhost], settings: settings)

        XCTAssertTrue(caddyfile.contains("myproject.test, www.myproject.test {"))
        let siteBlocks = caddyfile.components(separatedBy: "{").filter { $0.contains("myproject.test") }
        XCTAssertEqual(siteBlocks.filter { $0.contains("www.myproject.test") }.count, 1)
    }

    func testStaticSiteEmitsRootEncodeGzipAndFileServerIndex() {
        let vhost = Vhost(
            domain: "static.test",
            kind: .staticSite,
            documentRoot: "/Users/dev/Sites/static",
            compressionEnabled: true
        )

        let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: [vhost], settings: settings)

        XCTAssertTrue(caddyfile.contains("root * /Users/dev/Sites/static"))
        XCTAssertTrue(caddyfile.contains("encode gzip"))
        XCTAssertTrue(caddyfile.contains("file_server {"))
        XCTAssertTrue(caddyfile.contains("index index.html"))
    }

    func testPHPAbsoluteSocketUsesUnixDoubleSlash() {
        let vhost = Vhost(
            domain: "php.test",
            kind: .phpSite,
            documentRoot: "/Users/dev/Sites/php/public",
            phpSocketPath: "/opt/homebrew/var/run/php/php8.3.sock"
        )

        let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: [vhost], settings: settings)

        XCTAssertTrue(caddyfile.contains("php_fastcgi unix//opt/homebrew/var/run/php/php8.3.sock"))
    }

    func testPHPTCPTargetIsPassedThrough() {
        let vhost = Vhost(
            domain: "php-tcp.test",
            kind: .phpSite,
            documentRoot: "/Users/dev/Sites/php/public",
            phpSocketPath: "127.0.0.1:9000"
        )

        let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: [vhost], settings: settings)

        XCTAssertTrue(caddyfile.contains("php_fastcgi 127.0.0.1:9000"))
        XCTAssertFalse(caddyfile.contains("unix/127.0.0.1:9000"))
    }

    func testProxyWithWebsocketEmitsFlushIntervalAndForwardedHeadersInSpecOrder() {
        let vhost = Vhost(
            domain: "api.test",
            kind: .reverseProxy,
            proxyTarget: "127.0.0.1:3000",
            websocketEnabled: true,
            preserveHostHeader: false,
            forwardProxyHeaders: true
        )

        let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: [vhost], settings: settings)

        XCTAssertTrue(caddyfile.contains("reverse_proxy 127.0.0.1:3000 {"))
        XCTAssertTrue(caddyfile.contains("flush_interval -1"))
        XCTAssertTrue(caddyfile.contains("header_up X-Forwarded-Proto {scheme}"))
        XCTAssertTrue(caddyfile.contains("header_up X-Forwarded-Host {host}"))
        XCTAssertTrue(caddyfile.contains("header_up X-Real-IP {remote_host}"))

        let proto = caddyfile.range(of: "header_up X-Forwarded-Proto {scheme}")
        let host = caddyfile.range(of: "header_up X-Forwarded-Host {host}")
        let realIP = caddyfile.range(of: "header_up X-Real-IP {remote_host}")
        XCTAssertNotNil(proto)
        XCTAssertNotNil(host)
        XCTAssertNotNil(realIP)
        XCTAssertLessThan(proto!.lowerBound, host!.lowerBound)
        XCTAssertLessThan(host!.lowerBound, realIP!.lowerBound)
    }

    func testProxyWithoutExtrasIsSingleReverseProxyLine() {
        let vhost = Vhost(
            domain: "bare-proxy.test",
            kind: .reverseProxy,
            proxyTarget: "127.0.0.1:3000",
            websocketEnabled: false,
            preserveHostHeader: false,
            forwardProxyHeaders: false
        )

        let caddyfile = CaddyConfigBuilder.buildCaddyfile(vhosts: [vhost], settings: settings)

        XCTAssertTrue(caddyfile.contains("    reverse_proxy 127.0.0.1:3000\n"))
        XCTAssertFalse(caddyfile.contains("flush_interval"))
        XCTAssertFalse(caddyfile.contains("header_up"))
        XCTAssertFalse(caddyfile.contains("reverse_proxy 127.0.0.1:3000 {"))
    }
}
