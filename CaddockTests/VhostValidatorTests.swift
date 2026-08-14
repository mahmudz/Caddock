import XCTest
@testable import Caddock

@MainActor
final class VhostValidatorTests: XCTestCase {
    func testEmptyDomainIsError() {
        let vhost = Vhost(domain: "", kind: .staticSite, documentRoot: "/tmp")
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.message == "Domain cannot be empty." })
    }

    func testPublicTLDDotComIsBlocked() {
        let vhost = Vhost(domain: "myapp.com", kind: .staticSite, documentRoot: "/tmp")
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.message.contains("\".com\"") })
    }

    func testLocalTLDIsWarning() {
        let vhost = Vhost(domain: "myapp.local", kind: .staticSite, documentRoot: "/tmp")
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertTrue(issues.contains { $0.severity == .warning && $0.message.contains(".local") })
        XCTAssertFalse(issues.contains { $0.severity == .error && $0.message.contains(".local") })
    }

    func testWildcardOnlyAllowedOnPrimaryDomain() {
        let vhost = Vhost(
            domain: "myapp.test",
            aliases: ["*.other.test"],
            kind: .staticSite,
            documentRoot: "/tmp"
        )
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertTrue(issues.contains {
            $0.severity == .error && $0.message.contains("Wildcard aliases are not supported")
        })
    }

    func testPrimaryWildcardIsAllowed() {
        let vhost = Vhost(
            domain: "*.myapp.test",
            kind: .staticSite,
            documentRoot: "/tmp"
        )
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertFalse(issues.contains { $0.severity == .error && $0.message.lowercased().contains("wildcard") })
        XCTAssertTrue(VhostValidator.isValid(vhost, existing: []))
    }

    func testDuplicateDomainIsError() {
        let existing = Vhost(domain: "app.test", kind: .staticSite, documentRoot: "/tmp")
        let duplicate = Vhost(domain: "app.test", kind: .staticSite, documentRoot: "/tmp/other")
        let issues = VhostValidator.validate(duplicate, existing: [existing])
        XCTAssertTrue(issues.contains {
            $0.severity == .error && $0.message == "Another vhost already uses this domain."
        })
    }

    func testDuplicateAliasesAreNotAllowed() {
        let vhost = Vhost(
            domain: "app.test",
            aliases: ["www.app.test", "www.app.test"],
            kind: .staticSite,
            documentRoot: "/tmp"
        )
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertTrue(issues.contains {
            $0.severity == .error && $0.message == "Duplicate aliases are not allowed."
        })
    }

    func testUniqueAliasesAreValid() {
        let existing = Vhost(
            domain: "other.test",
            aliases: ["alias.other.test"],
            kind: .staticSite,
            documentRoot: "/tmp"
        )
        let vhost = Vhost(
            domain: "app.test",
            aliases: ["www.app.test", "api.app.test"],
            kind: .staticSite,
            documentRoot: "/tmp"
        )
        let issues = VhostValidator.validate(vhost, existing: [existing])
        XCTAssertFalse(issues.contains { $0.severity == .error && $0.message.lowercased().contains("alias") })
        XCTAssertTrue(VhostValidator.isValid(vhost, existing: [existing]))
    }

    func testAliasCollidingWithAnotherVhostIsError() {
        let existing = Vhost(domain: "taken.test", kind: .staticSite, documentRoot: "/tmp")
        let vhost = Vhost(
            domain: "app.test",
            aliases: ["taken.test"],
            kind: .staticSite,
            documentRoot: "/tmp"
        )
        let issues = VhostValidator.validate(vhost, existing: [existing])
        XCTAssertTrue(issues.contains {
            $0.severity == .error && $0.message == "Another vhost already uses \"taken.test\"."
        })
    }

    func testStaticRequiresDocumentRoot() {
        let vhost = Vhost(domain: "static.test", kind: .staticSite, documentRoot: nil)
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertTrue(issues.contains {
            $0.severity == .error && $0.message == "Static sites require a document root."
        })
    }

    func testPHPRequiresSocket() {
        let vhost = Vhost(
            domain: "php.test",
            kind: .phpSite,
            documentRoot: "/tmp/php",
            phpSocketPath: nil
        )
        let issues = VhostValidator.validate(vhost, existing: [], socketProbe: { _ in true })
        XCTAssertTrue(issues.contains {
            $0.severity == .error && $0.message == "PHP sites require a PHP-FPM socket path."
        })
    }

    func testPHPSocketProbeFalseYieldsWarningNotError() {
        let vhost = Vhost(
            domain: "php.test",
            kind: .phpSite,
            documentRoot: "/tmp/php",
            phpSocketPath: "/tmp/php-fpm.sock"
        )
        let issues = VhostValidator.validate(vhost, existing: [], socketProbe: { _ in false })
        XCTAssertTrue(issues.contains {
            $0.severity == .warning && $0.message.contains("not accepting connections")
        })
        XCTAssertFalse(issues.contains { $0.severity == .error && $0.message.contains("not accepting connections") })
        XCTAssertTrue(VhostValidator.isValid(vhost, existing: [], socketProbe: { _ in false }))
    }

    func testPHPSocketProbeTrueHasNoWarning() {
        let vhost = Vhost(
            domain: "php.test",
            kind: .phpSite,
            documentRoot: "/tmp/php",
            phpSocketPath: "/tmp/php-fpm.sock"
        )
        let issues = VhostValidator.validate(vhost, existing: [], socketProbe: { _ in true })
        XCTAssertFalse(issues.contains { $0.message.contains("not accepting connections") })
        XCTAssertTrue(VhostValidator.isValid(vhost, existing: [], socketProbe: { _ in true }))
    }

    func testProxyRequiresTarget() {
        let vhost = Vhost(domain: "proxy.test", kind: .reverseProxy, proxyTarget: nil)
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertTrue(issues.contains {
            $0.severity == .error && $0.message.contains("Reverse proxies require a target")
        })
    }

    func testInvalidProxyTargetIsError() {
        let vhost = Vhost(domain: "proxy.test", kind: .reverseProxy, proxyTarget: "not a target")
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertTrue(issues.contains {
            $0.severity == .error && $0.message.contains("Proxy target must look like host:port")
        })
    }

    func testValidProxyTargetIsAccepted() {
        let vhost = Vhost(domain: "proxy.test", kind: .reverseProxy, proxyTarget: "127.0.0.1:3000")
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertFalse(issues.contains { $0.severity == .error })
        XCTAssertTrue(VhostValidator.isValid(vhost, existing: []))
    }

    func testReverseProxyMustNotSetDocumentRoot() {
        let vhost = Vhost(
            domain: "proxy.test",
            kind: .reverseProxy,
            documentRoot: "/tmp/should-not-be-set",
            proxyTarget: "127.0.0.1:3000"
        )
        let issues = VhostValidator.validate(vhost, existing: [])
        XCTAssertTrue(issues.contains {
            $0.severity == .error && $0.message == "Reverse proxies must not set a document root or PHP socket."
        })
    }
}
