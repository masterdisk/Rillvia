import Foundation
import XCTest
@testable import BrowserChange

final class URLNormalizerTests: XCTestCase {
    func testNormalizesHostCasingTrailingDotAndIDNWithoutRewritingOriginalURL() throws {
        let original = try XCTUnwrap(
            URL(string: "HTTPS://XN--BCHER-KVA.Example./private?token=keep")
        )

        let normalized = try URLNormalizer.normalize(original)

        XCTAssertEqual(normalized.host, "xn--bcher-kva.example")
        XCTAssertEqual(normalized.scheme, .https)
        XCTAssertEqual(normalized.originalURL, original)
        XCTAssertTrue(normalized.isIDN)
    }

    func testUnicodeHostNormalizesToLowercaseASCII() throws {
        let normalized = try URLNormalizer.normalize(
            XCTUnwrap(URL(string: "https://BÜCHER.example/path"))
        )

        XCTAssertEqual(normalized.host, "xn--bcher-kva.example")
        XCTAssertTrue(normalized.host.unicodeScalars.allSatisfy(\.isASCII))
    }

    func testRejectsUnsupportedMissingAndMalformedHosts() {
        let rejected = [
            URL(fileURLWithPath: "/tmp/private"),
            URL(string: "https:///missing-host")!,
            URL(string: "https://example..com/path")!,
            URL(string: "https://example.com../path")!,
        ]

        for url in rejected {
            XCTAssertThrowsError(try URLNormalizer.normalize(url), "\(url)")
        }
    }

    func testNormalizeHostAcceptsBareHostsAndPastedWebURLs() throws {
        XCTAssertEqual(
            try URLNormalizer.normalizeHost("example.com"),
            "example.com"
        )
        XCTAssertEqual(
            try URLNormalizer.normalizeHost("  HTTPS://News.Example.com/path?q=1  "),
            "news.example.com"
        )
        XCTAssertEqual(
            try URLNormalizer.normalizeHost("example.com/docs"),
            "example.com"
        )
        XCTAssertThrowsError(try URLNormalizer.normalizeHost("   "))
        XCTAssertThrowsError(try URLNormalizer.normalizeHost("not a domain"))
    }

    func testDomainMatchingUsesLabelsInsteadOfRawSuffixes() {
        XCTAssertTrue(
            URLNormalizer.host(
                "shop.docs.example.com",
                matches: "example.com",
                scope: .includeSubdomains
            )
        )
        XCTAssertFalse(
            URLNormalizer.host(
                "notexample.com",
                matches: "example.com",
                scope: .includeSubdomains
            )
        )
        XCTAssertFalse(
            URLNormalizer.host(
                "docs.example.com",
                matches: "example.com",
                scope: .exactHost
            )
        )
    }
}
