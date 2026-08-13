import XCTest
@testable import CaddyManager

@MainActor
final class LocalDomainPolicyTests: XCTestCase {
    func testWildcardRequiresStarDotAndAtLeastTwoLabels() {
        XCTAssertTrue(LocalDomainPolicy.isWildcardDomain("*.app.test"))
        XCTAssertTrue(LocalDomainPolicy.isWildcardDomain("*.myapp.localhost"))
        XCTAssertFalse(LocalDomainPolicy.isWildcardDomain("app.test"))
        XCTAssertFalse(LocalDomainPolicy.isWildcardDomain("*.test"))
        XCTAssertFalse(LocalDomainPolicy.isWildcardDomain("star.app.test"))
    }

    func testTLDExtraction() {
        XCTAssertEqual(LocalDomainPolicy.tld(of: "myapp.test"), "test")
        XCTAssertEqual(LocalDomainPolicy.tld(of: "*.myapp.test"), "test")
        XCTAssertEqual(LocalDomainPolicy.tld(of: "www.api.example"), "example")
        XCTAssertEqual(LocalDomainPolicy.tld(of: "MyApp.COM"), "com")
        XCTAssertNil(LocalDomainPolicy.tld(of: "localhost"))
        XCTAssertNil(LocalDomainPolicy.tld(of: "single"))
    }

    func testBlockedPublicTLD() {
        XCTAssertTrue(LocalDomainPolicy.isBlockedPublicTLD("com"))
        XCTAssertTrue(LocalDomainPolicy.isBlockedPublicTLD("COM"))
        XCTAssertTrue(LocalDomainPolicy.isBlockedPublicTLD("io"))
        XCTAssertTrue(LocalDomainPolicy.isBlockedPublicTLD("dev"))
        XCTAssertTrue(LocalDomainPolicy.isBlockedPublicTLD("app"))
        XCTAssertFalse(LocalDomainPolicy.isBlockedPublicTLD("test"))
        XCTAssertFalse(LocalDomainPolicy.isBlockedPublicTLD("localhost"))
        XCTAssertFalse(LocalDomainPolicy.isBlockedPublicTLD("example"))
    }

    func testRecommendedTLD() {
        XCTAssertTrue(LocalDomainPolicy.isRecommendedTLD("test"))
        XCTAssertTrue(LocalDomainPolicy.isRecommendedTLD("localhost"))
        XCTAssertTrue(LocalDomainPolicy.isRecommendedTLD("example"))
        XCTAssertTrue(LocalDomainPolicy.isRecommendedTLD("TEST"))
        XCTAssertFalse(LocalDomainPolicy.isRecommendedTLD("com"))
        XCTAssertFalse(LocalDomainPolicy.isRecommendedTLD("io"))
        XCTAssertFalse(LocalDomainPolicy.isRecommendedTLD("local"))
    }
}
