import Foundation
import XCTest
@testable import BrowserChange

final class AirlockParserTests: XCTestCase {
    func testExtractsMultipleWebLinksDeduplicatesAndRejectsUnsafeSchemes() throws {
        let parser = AirlockParser(maxTextLength: 1_000, maxURLCount: 10)
        let result = parser.parse(
            text: """
            First: https://example.com/a.
            Duplicate: https://example.com/a
            Second: http://docs.example.com/path?x=1
            Unsafe: javascript://example.com/steal and file:///tmp/private
            """
        )

        XCTAssertEqual(
            result.items.map(\.originalText),
            [
                "https://example.com/a",
                "http://docs.example.com/path?x=1",
            ]
        )
        XCTAssertEqual(result.rejectedCandidateCount, 2)
        XCTAssertFalse(result.wasTextTruncated)
        XCTAssertFalse(result.wasURLLimitReached)
    }

    func testAcceptsPublicURLAndDropURLsWhileEnforcingCountLimit() throws {
        let parser = AirlockParser(maxTextLength: 1_000, maxURLCount: 2)
        let result = parser.parse(
            urls: [
                try XCTUnwrap(URL(string: "https://one.example/path")),
                try XCTUnwrap(URL(string: "file:///tmp/private")),
                try XCTUnwrap(URL(string: "https://two.example/path")),
                try XCTUnwrap(URL(string: "https://three.example/path")),
            ]
        )

        XCTAssertEqual(
            result.items.map(\.normalized.host),
            ["one.example", "two.example"]
        )
        XCTAssertEqual(result.rejectedCandidateCount, 1)
        XCTAssertTrue(result.wasURLLimitReached)
    }

    func testRiskWarningsAreDeterministicAndDoNotRewriteOriginal() throws {
        let original = "http://user:pass@127.0.0.1/path?utm_source=mail&fbclid=abc"
        let item = try XCTUnwrap(
            AirlockParser().parse(text: original).items.first
        )

        XCTAssertEqual(item.originalText, original)
        XCTAssertEqual(item.normalized.originalURL.absoluteString, original)
        XCTAssertEqual(
            item.warnings,
            [
                .plainHTTP,
                .embeddedCredentials,
                .ipLiteral,
                .trackingParameters(["fbclid", "utm_source"]),
            ]
        )
    }

    func testWarnsForIDNAndTruncatesOversizedInputBeforeParsing() throws {
        let parser = AirlockParser(maxTextLength: 35, maxURLCount: 10)
        let result = parser.parse(
            text: "https://xn--bcher-kva.example/ then ignored https://example.com"
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].warnings, [.idnOrPunycode])
        XCTAssertTrue(result.wasTextTruncated)
    }

    func testPreservesValidTerminalParenthesisInDetectedURL() throws {
        let original = "https://en.wikipedia.org/wiki/Function_(mathematics)"
        let result = AirlockParser().parse(text: "Read \(original)")

        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(item.originalText, original)
        XCTAssertEqual(
            item.normalized.originalURL.absoluteString,
            original
        )
    }

    func testDiscardsURLIntersectingTextLimitInsteadOfStagingPrefix() {
        let prefix = "Read "
        let original = "https://example.com/a-long-path"
        let parser = AirlockParser(
            maxTextLength: prefix.count + 20,
            maxURLCount: 10
        )

        let result = parser.parse(text: prefix + original)

        XCTAssertTrue(result.wasTextTruncated)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.rejectedCandidateCount, 1)
    }

    func testPreservesCompleteURLThatEndsAtTextLimit() throws {
        let original = "https://example.com/complete"
        let parser = AirlockParser(
            maxTextLength: original.count,
            maxURLCount: 10
        )

        let result = parser.parse(text: original + " ignored")

        XCTAssertEqual(
            try XCTUnwrap(result.items.first).originalText,
            original
        )
        XCTAssertTrue(result.wasTextTruncated)
    }
}
