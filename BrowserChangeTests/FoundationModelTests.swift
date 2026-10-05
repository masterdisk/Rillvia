import Foundation
import XCTest
@testable import BrowserChange

final class FoundationModelTests: XCTestCase {
    private let browserChange = BrowserReference(bundleIdentifier: "com.browserchange.BrowserChange")
    private let safari = HandlerApplication(
        browser: BrowserReference(bundleIdentifier: "com.apple.Safari"),
        applicationURL: URL(fileURLWithPath: "/Applications/Safari.app")
    )
    private let firefox = HandlerApplication(
        browser: BrowserReference(bundleIdentifier: "org.mozilla.firefox"),
        applicationURL: URL(fileURLWithPath: "/Applications/Firefox.app")
    )

    func testHandlerOwnershipRecognizesOneExternalBrowser() {
        let handlers = HTTPHandlerSnapshot(http: safari, https: safari)

        XCTAssertEqual(
            handlers.ownership(browserChange: browserChange),
            .external(safari.browser)
        )
    }

    func testHandlerOwnershipRecognizesBrowserChange() {
        let application = HandlerApplication(
            browser: browserChange,
            applicationURL: URL(fileURLWithPath: "/Applications/BrowserChange.app")
        )

        XCTAssertEqual(
            HTTPHandlerSnapshot(http: application, https: application)
                .ownership(browserChange: browserChange),
            .browserChange
        )
    }

    func testHandlerOwnershipRecognizesSplitHandlers() {
        XCTAssertEqual(
            HTTPHandlerSnapshot(http: safari, https: firefox)
                .ownership(browserChange: browserChange),
            .split(http: safari, https: firefox)
        )
    }

    func testHandlerOwnershipRecognizesOneOrBothMissingHandlers() {
        XCTAssertEqual(
            HTTPHandlerSnapshot(http: safari, https: nil)
                .ownership(browserChange: browserChange),
            .missing(http: safari, https: nil)
        )
        XCTAssertEqual(
            HTTPHandlerSnapshot(http: nil, https: nil)
                .ownership(browserChange: browserChange),
            .missing(http: nil, https: nil)
        )
    }

    func testRoutingValuesRoundTripWithoutLosingStableBrowserReferences() throws {
        let fallback = BrowserReference(bundleIdentifier: "com.apple.Safari")
        let work = BrowserReference(bundleIdentifier: "com.google.Chrome")
        let rule = DomainRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            revision: 3,
            domain: "github.com",
            browser: work,
            isEnabled: true
        )
        let profile = RoutingProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            revision: 2,
            name: "Work",
            browser: work,
            isEnabled: true
        )
        let lease = BrowserLease(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            revision: 4,
            browser: fallback,
            startedAt: Date(timeIntervalSince1970: 1_799_999_100),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: fallback,
            domainRules: [rule],
            profiles: [profile],
            browserLease: lease
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(RoutingConfiguration.self, from: data)

        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(decoded.fallbackBrowser?.id, "com.apple.Safari")
    }

    func testPendingOperationCarriesAPreconditionedUndoReceipt() throws {
        let before = HTTPHandlerSnapshot(http: safari, https: safari)
        let desired = HTTPHandlerSnapshot(http: firefox, https: firefox)
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let receipt = HandlerUndoReceipt(
            operationID: operationID,
            issuedAt: Date(timeIntervalSince1970: 1_700_000_000),
            precondition: desired,
            restore: before
        )
        let journal = HandlerOperationJournal(
            pendingOperation: PendingHandlerOperation(
                id: operationID,
                startedAt: Date(timeIntervalSince1970: 1_699_999_999),
                desiredHandlers: desired,
                undoReceipt: receipt
            )
        )

        let data = try JSONEncoder().encode(journal)
        let decoded = try JSONDecoder().decode(HandlerOperationJournal.self, from: data)

        XCTAssertEqual(decoded, journal)
        XCTAssertEqual(decoded.pendingOperation?.undoReceipt.precondition, desired)
        XCTAssertEqual(decoded.pendingOperation?.undoReceipt.restore, before)
    }
}

@MainActor
final class BrowserStoreFoundationTests: XCTestCase {
    func testStoreUsesInjectedCatalogAndChangesEachSchemeIndependently() async throws {
        let safari = InstalledBrowser(
            id: "com.apple.Safari",
            name: "Safari",
            version: "26",
            appURL: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        let chrome = InstalledBrowser(
            id: "com.google.Chrome",
            name: "Google Chrome",
            version: "140",
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )
        let catalog = FakeBrowserCatalog(browsers: [safari, chrome])
        let handlers = FakeSystemBrowserHandler(
            handlers: .same(
                HandlerApplication(
                    browser: BrowserReference(bundleIdentifier: chrome.id),
                    applicationURL: chrome.appURL
                )
            ),
            applications: [
                safari.reference: safari.appURL,
                chrome.reference: chrome.appURL,
            ]
        )
        let repository = StateRepository(baseDirectory: temporaryDirectory())
        let store = BrowserStore(
            environment: AppEnvironment(
                browserCatalog: catalog,
                systemBrowserHandler: handlers,
                stateRepository: repository
            )
        )

        XCTAssertEqual(store.defaultBundleID, chrome.id)
        XCTAssertEqual(store.switchable.map(\.id), [chrome.id, safari.id])

        await store.makeDefault(safari)

        XCTAssertEqual(
            handlers.setCalls,
            [
                .init(browser: safari.reference, scheme: .https),
                .init(browser: safari.reference, scheme: .http),
            ]
        )
        XCTAssertEqual(store.defaultBundleID, safari.id)
        XCTAssertEqual(store.message, "Safari is now the default.")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserStoreFoundationTests-\(UUID().uuidString)")
    }
}
