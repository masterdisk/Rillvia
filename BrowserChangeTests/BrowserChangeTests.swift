import Foundation
import XCTest
@testable import BrowserChange

final class BrowserDirectoryTests: XCTestCase {
    func testKeepsAppsThatHandleBothSchemesAndDropsHelpers() {
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let helper = URL(fileURLWithPath: "/Applications/Google Chrome Helper.app")
        let preview = URL(fileURLWithPath: "/Applications/Preview.app")
        let web = [["http", "https"]]
        let facts: [URL: BundleFacts] = [
            safari: BundleFacts(bundleID: "com.apple.Safari", name: "Safari", version: "26.0", urlTypes: web),
            chrome: BundleFacts(bundleID: "com.google.Chrome", name: "Google Chrome", version: "140", urlTypes: web),
            helper: BundleFacts(bundleID: "com.google.Chrome.helper", name: "Google Chrome Helper", version: "140", urlTypes: web),
            preview: BundleFacts(bundleID: "com.apple.Preview", name: "Preview", version: "11", urlTypes: web),
        ]

        let browsers = BrowserDirectory.assemble(
            https: [safari, chrome, helper, preview],
            http: [safari, chrome, helper],
            facts: { facts[$0] },
            excluding: "com.browserchange.BrowserChange"
        )

        XCTAssertEqual(browsers.map(\.id), ["com.google.Chrome", "com.apple.Safari"])
    }

    func testFallsBackToHTTPSWhenHTTPLookupIsEmpty() {
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        let browsers = BrowserDirectory.assemble(
            https: [safari],
            http: [],
            facts: { _ in BundleFacts(bundleID: "com.apple.Safari", name: "Safari", version: "26", urlTypes: [["http", "https"]]) }
        )
        XCTAssertEqual(browsers.map(\.name), ["Safari"])
    }

    func testDedupesBundleIDs() {
        let first = URL(fileURLWithPath: "/Applications/Safari.app")
        let second = URL(fileURLWithPath: "/Users/me/Applications/Safari.app")
        let browsers = BrowserDirectory.assemble(
            https: [first, second],
            http: [first],
            facts: { _ in BundleFacts(bundleID: "com.apple.Safari", name: "Safari", version: "26", urlTypes: [["http", "https"]]) }
        )
        XCTAssertEqual(browsers.count, 1)
        XCTAssertEqual(browsers[0].appURL, first)
    }

    func testDropsTerminalsAndMixedSchemes() {
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let terminal = URL(fileURLWithPath: "/Applications/iTerm.app")
        let chat = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        let facts: [URL: BundleFacts] = [
            chrome: BundleFacts(
                bundleID: "com.google.Chrome",
                name: "Google Chrome",
                version: "140",
                urlTypes: [["http", "https"], ["google-chrome"]]
            ),
            terminal: BundleFacts(
                bundleID: "com.googlecode.iterm2",
                name: "iTerm2",
                version: "3",
                urlTypes: [["http", "https"], ["ssh"], ["telnet"]]
            ),
            chat: BundleFacts(
                bundleID: "com.openai.codex",
                name: "ChatGPT",
                version: "1",
                urlTypes: [["codex", "http", "https"]]
            ),
        ]
        let browsers = BrowserDirectory.assemble(
            https: [chrome, terminal, chat],
            http: [chrome, terminal, chat],
            facts: { facts[$0] }
        )
        XCTAssertEqual(browsers.map(\.name), ["Google Chrome"])
    }

    func testDropsBrowserSwitchUtilities() {
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let chooser = URL(fileURLWithPath: "/Users/me/Applications/Browser Switch.app")
        let facts: [URL: BundleFacts] = [
            chrome: BundleFacts(
                bundleID: "com.google.Chrome",
                name: "Google Chrome",
                version: "140",
                urlTypes: [["http", "https"]]
            ),
            chooser: BundleFacts(
                bundleID: "com.adamabernathy.browserswitch",
                name: "Browser Switch",
                version: "0.9.0",
                urlTypes: [["http", "https"]]
            ),
        ]
        let browsers = BrowserDirectory.assemble(
            https: [chrome, chooser],
            http: [chrome, chooser],
            facts: { facts[$0] }
        )
        XCTAssertEqual(browsers.map(\.name), ["Google Chrome"])
    }
}

final class BrowserLocationTests: XCTestCase {
    func testCacheCopiesAreNotUserFacing() {
        let cache = URL(fileURLWithPath: "/Users/me/Library/Caches/ms-playwright/chrome/Google Chrome for Testing.app")
        let apps = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        XCTAssertFalse(BrowserLocation.isUserFacing(cache))
        XCTAssertTrue(BrowserLocation.isUserFacing(apps))
    }

    func testNestedHandlerUsesTheHostAppName() {
        let router = URL(fileURLWithPath: "/Users/me/Applications/Browser Switch.app/Contents/Resources/BrowserSwitchRouter.app")
        XCTAssertEqual(
            ContainingApp.hostApplication(for: router)?.lastPathComponent,
            "Browser Switch.app"
        )
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        XCTAssertNil(ContainingApp.hostApplication(for: safari))
    }
}

final class BrowserOrderTests: XCTestCase {
    func testDefaultComesFirstAndLynxStaysLast() {
        let chrome = InstalledBrowser(id: "com.google.Chrome", name: "Google Chrome", version: "1", appURL: URL(fileURLWithPath: "/Chrome.app"))
        let safari = InstalledBrowser(id: "com.apple.Safari", name: "Safari", version: "1", appURL: URL(fileURLWithPath: "/Safari.app"))
        let ordered = BrowserOrder.shelf([chrome, ImaginaryBrowser.lynx, safari], defaultID: safari.id)
        XCTAssertEqual(ordered.map(\.name), ["Safari", "Google Chrome", "Lynx"])
    }
}

final class QuietHoursTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    func testWeekdayAfternoonIsWork() {
        let date = DateComponents(calendar: calendar, year: 2026, month: 10, day: 7, hour: 15).date!
        XCTAssertEqual(QuietHours.phase(at: date, calendar: calendar), .work)
    }

    func testEveningAndSundayArePersonal() {
        let evening = DateComponents(calendar: calendar, year: 2026, month: 10, day: 7, hour: 20).date!
        let sunday = DateComponents(calendar: calendar, year: 2026, month: 10, day: 4, hour: 11).date!
        XCTAssertEqual(QuietHours.phase(at: evening, calendar: calendar), .personal)
        XCTAssertEqual(QuietHours.phase(at: sunday, calendar: calendar), .personal)
    }
}

final class PreviewBoardTests: XCTestCase {
    func testRoutesUseInstalledBrowsers() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let browsers = [
            InstalledBrowser(id: "com.apple.Safari", name: "Safari", version: "26", appURL: URL(fileURLWithPath: "/Safari.app")),
            InstalledBrowser(id: "com.google.Chrome", name: "Google Chrome", version: "140", appURL: URL(fileURLWithPath: "/Chrome.app")),
            InstalledBrowser(id: "org.mozilla.firefox", name: "Firefox", version: "143", appURL: URL(fileURLWithPath: "/Firefox.app")),
        ]
        let now = DateComponents(calendar: calendar, year: 2026, month: 10, day: 7, hour: 15).date!
        let board = PreviewBoard.make(browsers: browsers, defaultID: "com.apple.Safari", now: now, calendar: calendar)

        XCTAssertEqual(board.routes.first { $0.id == "github" }?.browserName, "Firefox")
        XCTAssertEqual(board.routes.first { $0.id == "apple" }?.browserName, "Safari")
        XCTAssertEqual(board.profiles.first { $0.id == "work" }?.browserName, "Google Chrome")
        XCTAssertEqual(board.profiles.first { $0.id == "work" }?.suggestedNow, true)
        XCTAssertTrue(board.nowLine.contains("Google Chrome"))
    }
}

final class EasterEggTests: XCTestCase {
    func testTitleOpensOnTheFifthQuickTap() {
        var gate = TapGate(threshold: 5, interval: 1.5)
        let start = Date(timeIntervalSince1970: 1_000)
        for index in 0..<4 {
            XCTAssertFalse(gate.tap(at: start.addingTimeInterval(Double(index) * 0.2)))
        }
        XCTAssertTrue(gate.tap(at: start.addingTimeInterval(0.8)))
    }

    func testSlowTapsDoNotAccumulate() {
        var gate = TapGate(threshold: 5, interval: 1.5)
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(gate.tap(at: start))
        XCTAssertFalse(gate.tap(at: start.addingTimeInterval(3)))
    }

    func testLynxSequence() {
        var sequence = CharacterSequence(target: "lynx", gap: 1.2)
        let start = Date(timeIntervalSince1970: 2_000)
        XCTAssertFalse(sequence.consume("l", at: start))
        XCTAssertFalse(sequence.consume("y", at: start.addingTimeInterval(0.1)))
        XCTAssertFalse(sequence.consume("n", at: start.addingTimeInterval(0.2)))
        XCTAssertTrue(sequence.consume("X", at: start.addingTimeInterval(0.3)))
    }

    func testCancelledChangeStaysPut() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        XCTAssertEqual(DefaultBrowserFailure.message(for: error), "Left the default where it was.")
    }
}
