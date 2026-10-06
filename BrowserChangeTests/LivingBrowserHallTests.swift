import Foundation
import XCTest
@testable import BrowserChange

final class LivingBrowserHallTests: XCTestCase {
    private let safari = InstalledBrowser(
        id: "com.apple.Safari",
        name: "Safari",
        version: "26.0",
        appURL: URL(fileURLWithPath: "/Applications/Safari.app")
    )
    private let chrome = InstalledBrowser(
        id: "com.google.Chrome",
        name: "Google Chrome",
        version: "140",
        appURL: URL(
            fileURLWithPath: "/Applications/Google Chrome.app"
        )
    )
    private let firefox = InstalledBrowser(
        id: "org.mozilla.firefox",
        name: "Firefox",
        version: "143",
        appURL: URL(
            fileURLWithPath: "/Applications/Firefox.app"
        )
    )

    func testHallIlluminatesInstalledBrowserEras() {
        let model = LivingBrowserHallModel.make(
            installedBrowsers: [safari, chrome, firefox],
            configuration: RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            ),
            defaultBundleID: chrome.id,
            now: Date(timeIntervalSince1970: 1_900_000_000)
        )

        XCTAssertEqual(
            model.eras.filter(\.isRepresented).map(\.name),
            [
                "Netscape Navigator",
                "Safari",
                "Chrome",
            ]
        )
        XCTAssertEqual(
            model.eras.first {
                $0.name == "Netscape Navigator"
            }?.representedBy,
            ["Firefox"]
        )
        XCTAssertFalse(
            try XCTUnwrap(
                model.eras.first {
                    $0.name == "Internet Explorer"
                }
            ).isRepresented
        )
    }

    func testHallShowsLiveVersionFallbackRulesAndLeaseFacts() throws {
        let lease = BrowserLease(
            browser: safari.reference,
            startedAt: Date(timeIntervalSince1970: 1_899_999_900),
            expiresAt: nil
        )
        let model = LivingBrowserHallModel.make(
            installedBrowsers: [safari, chrome],
            configuration: RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                domainRules: [
                    DomainRule(
                        domain: "example.com",
                        browser: safari.reference
                    ),
                    DomainRule(
                        domain: "disabled.example",
                        browser: safari.reference,
                        isEnabled: false
                    ),
                    DomainRule(
                        domain: "work.example",
                        browser: chrome.reference
                    ),
                ],
                browserLease: lease
            ),
            defaultBundleID: chrome.id,
            now: Date(timeIntervalSince1970: 1_900_000_000)
        )

        let safariFacts = try XCTUnwrap(
            model.browsers.first { $0.id == safari.id }
        )
        XCTAssertEqual(safariFacts.version, "26.0")
        XCTAssertEqual(safariFacts.enabledRuleCount, 1)
        XCTAssertTrue(safariFacts.hasActiveLease)
        XCTAssertEqual(
            safariFacts.status,
            ["Temporary browser"]
        )

        let chromeFacts = try XCTUnwrap(
            model.browsers.first { $0.id == chrome.id }
        )
        XCTAssertEqual(chromeFacts.version, "140")
        XCTAssertEqual(chromeFacts.enabledRuleCount, 1)
        XCTAssertFalse(chromeFacts.hasActiveLease)
        XCTAssertEqual(
            chromeFacts.status,
            ["Browser for sites with no rule"]
        )
    }

    func testHallCallsOutDirectDefaultWithoutColorOnlyState() throws {
        let model = LivingBrowserHallModel.make(
            installedBrowsers: [safari],
            configuration: .fresh,
            defaultBundleID: safari.id,
            now: Date(timeIntervalSince1970: 1_900_000_000)
        )

        XCTAssertEqual(
            try XCTUnwrap(model.browsers.first).status,
            ["Usual browser"]
        )
        XCTAssertTrue(model.todayLine.contains("1 browser installed"))
    }
}
