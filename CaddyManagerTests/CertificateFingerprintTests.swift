import XCTest
@testable import CaddyManager

@MainActor
final class CertificateFingerprintTests: XCTestCase {
    /// Tiny self-signed EC P-256 certificate (CN=CaddyManager Test CA).
    private static let pem = """
    -----BEGIN CERTIFICATE-----
    MIIBkzCCATmgAwIBAgIUQAZH+e9OdnU0Q15ZGwbB3ZwgI1QwCgYIKoZIzj0EAwIw
    HzEdMBsGA1UEAwwUQ2FkZHlNYW5hZ2VyIFRlc3QgQ0EwHhcNMjYwODEzMTc1MjIw
    WhcNMzYwODEwMTc1MjIwWjAfMR0wGwYDVQQDDBRDYWRkeU1hbmFnZXIgVGVzdCBD
    QTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABBibzZIhGGZEevBy7moMoX2oCRfi
    iDhXFKbrVe1LXWNvFtrLcq0HmZxlkXBSeFfAn4cDDzclUErhslkvncLpaVejUzBR
    MB0GA1UdDgQWBBQByx7i8J9Wbdnv2Lm+dGk4Z/EpuzAfBgNVHSMEGDAWgBQByx7i
    8J9Wbdnv2Lm+dGk4Z/EpuzAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0gA
    MEUCIQDeKBy+U7YbHIOld4L9zCRKEyIlav9bCNo3jETh+fjchAIgIOUTWhs2ylu8
    S99j/RYlcKpl9P8UeIRSIIrC4WCpEk4=
    -----END CERTIFICATE-----
    """

    func testLoadFromPEMDataSucceeds() {
        let data = Data(Self.pem.utf8)
        XCTAssertNotNil(CertificateLoader.load(from: data))
    }

    func testSHA256FingerprintIs32Bytes() throws {
        let certificate = try XCTUnwrap(CertificateLoader.load(from: Data(Self.pem.utf8)))
        let digest = CertificateFingerprint.sha256(of: certificate)
        XCTAssertEqual(digest.count, 32)
    }

    func testHexStringLengthIs64() throws {
        let certificate = try XCTUnwrap(CertificateLoader.load(from: Data(Self.pem.utf8)))
        let digest = CertificateFingerprint.sha256(of: certificate)
        let hex = CertificateFingerprint.hexString(digest)
        XCTAssertEqual(hex.count, 64)
        XCTAssertEqual(hex, hex.lowercased())
        XCTAssertTrue(hex.allSatisfy { $0.isHexDigit })
    }

    func testTwoLoadsOfSameCertProduceIdenticalFingerprint() throws {
        let data = Data(Self.pem.utf8)
        let first = try XCTUnwrap(CertificateLoader.load(from: data))
        let second = try XCTUnwrap(CertificateLoader.load(from: data))
        XCTAssertEqual(
            CertificateFingerprint.sha256(of: first),
            CertificateFingerprint.sha256(of: second)
        )
        XCTAssertEqual(
            CertificateFingerprint.hexString(CertificateFingerprint.sha256(of: first)),
            CertificateFingerprint.hexString(CertificateFingerprint.sha256(of: second))
        )
    }

    func testPemToDERStripsHeaders() throws {
        let pemData = Data(Self.pem.utf8)
        XCTAssertTrue(Self.pem.contains("-----BEGIN CERTIFICATE-----"))
        XCTAssertTrue(Self.pem.contains("-----END CERTIFICATE-----"))

        let der = try XCTUnwrap(CertificateLoader.pemToDER(pemData))
        XCTAssertFalse(der.isEmpty)
        XCTAssertFalse(der.starts(with: Data("-----".utf8)))
        if let text = String(data: der, encoding: .utf8) {
            XCTAssertFalse(text.contains("BEGIN CERTIFICATE"))
            XCTAssertFalse(text.contains("-----"))
        }

        let fromDER = try XCTUnwrap(CertificateLoader.load(from: der))
        let fromPEM = try XCTUnwrap(CertificateLoader.load(from: pemData))
        XCTAssertEqual(
            CertificateFingerprint.sha256(of: fromDER),
            CertificateFingerprint.sha256(of: fromPEM)
        )
    }
}
