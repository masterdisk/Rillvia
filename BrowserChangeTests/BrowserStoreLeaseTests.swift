import Foundation
import XCTest
@testable import BrowserChange

@MainActor
final class BrowserStoreLeaseTests: XCTestCase {
    private let browserChange = InstalledBrowser(
        id: "com.browserchange.BrowserChange",
        name: "BrowserChange",
        version: "1",
        appURL: URL(
            fileURLWithPath: "/Applications/BrowserChange.app"
        )
    )
    private let chrome = InstalledBrowser(
        id: "com.google.Chrome",
        name: "Google Chrome",
        version: "140",
        appURL: URL(
            fileURLWithPath: "/Applications/Google Chrome.app"
        )
    )
    private let safari = InstalledBrowser(
        id: "com.apple.Safari",
        name: "Safari",
        version: "26",
        appURL: URL(fileURLWithPath: "/Applications/Safari.app")
    )
    private var directory: URL!
    private var repository: StateRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserStoreLeaseTests-\(UUID().uuidString)"
            )
        repository = StateRepository(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testBorrowPublishesCountdownEndAndUndoWithoutHandlerWrites() async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try saveSmartConfiguration()
        let handler = makeHandler()
        let scheduler = StoreFakeBrowserLeaseScheduler()
        let store = makeStore(
            handler: handler,
            scheduler: scheduler,
            now: { now }
        )
        await store.activate()

        XCTAssertTrue(
            store.borrowBrowser(safari, for: .fifteenMinutes)
        )
        XCTAssertEqual(
            store.activeBrowserLease?.browser,
            safari.reference
        )
        XCTAssertEqual(store.activeLeaseBrowser?.name, "Safari")
        XCTAssertEqual(
            store.activeLeaseRemainingText,
            "15:00 remaining"
        )
        XCTAssertTrue(store.canUndoLease)
        XCTAssertTrue(store.endBrowserLease())
        XCTAssertNil(store.activeBrowserLease)
        XCTAssertTrue(store.canUndoLease)
        XCTAssertTrue(store.undoBrowserLeaseChange())
        XCTAssertEqual(
            store.activeBrowserLease?.browser,
            safari.reference
        )
        XCTAssertFalse(store.canUndoLease)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testEveryConfigurationMutationWithdrawsStaleLeaseUndo() async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try saveSmartConfiguration()
        let handler = makeHandler()
        let store = makeStore(
            handler: handler,
            scheduler: StoreFakeBrowserLeaseScheduler(),
            now: { now }
        )
        await store.activate()

        XCTAssertTrue(
            store.borrowBrowser(safari, for: .untilEnded)
        )
        XCTAssertTrue(store.canUndoLease)
        XCTAssertNotNil(
            store.createRule(
                domain: "example.com",
                browser: chrome.reference
            )
        )
        XCTAssertFalse(store.canUndoLease)

        XCTAssertTrue(
            store.borrowBrowser(safari, for: .untilEnded)
        )
        XCTAssertTrue(store.canUndoLease)
        XCTAssertNotNil(store.createProfile(named: "Work"))
        XCTAssertFalse(store.canUndoLease)

        XCTAssertTrue(
            store.borrowBrowser(safari, for: .untilEnded)
        )
        XCTAssertTrue(store.canUndoLease)
        XCTAssertTrue(store.setAutomationLeasesAllowed(true))
        XCTAssertFalse(store.canUndoLease)

        XCTAssertTrue(
            store.borrowBrowser(safari, for: .untilEnded)
        )
        XCTAssertTrue(store.canUndoLease)
        await store.makeDefault(safari)
        XCTAssertFalse(store.canUndoLease)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testIncomingURLReconcilesExactExpiryBeforeRoutingWithoutDroppingURL() async throws {
        var now = Date(timeIntervalSince1970: 1_900_000_000)
        try saveSmartConfiguration()
        let handler = makeHandler()
        let scheduler = StoreFakeBrowserLeaseScheduler()
        let launcher = FakeURLLauncher()
        let store = makeStore(
            handler: handler,
            scheduler: scheduler,
            launcher: launcher,
            now: { now }
        )
        await store.activate()
        XCTAssertTrue(
            store.borrowBrowser(safari, for: .fifteenMinutes)
        )
        now = try XCTUnwrap(store.activeBrowserLease?.expiresAt)
        let url = try XCTUnwrap(
            URL(string: "https://example.com/at-expiry")
        )

        let disposition = await store.routeIncomingURL(url)

        XCTAssertEqual(disposition, .consumed)
        XCTAssertNil(store.activeBrowserLease)
        XCTAssertEqual(
            launcher.calls,
            [.init(url: url, browser: chrome.reference)]
        )
        XCTAssertFalse(store.canUndoLease)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testAirlockRouteAlsoReconcilesExpiryBeforeDecision() async throws {
        var now = Date(timeIntervalSince1970: 1_900_000_000)
        try saveSmartConfiguration()
        let handler = makeHandler()
        let launcher = FakeURLLauncher()
        let store = makeStore(
            handler: handler,
            scheduler: StoreFakeBrowserLeaseScheduler(),
            launcher: launcher,
            now: { now }
        )
        await store.activate()
        XCTAssertTrue(
            store.borrowBrowser(safari, for: .fifteenMinutes)
        )
        store.stageAirlock(text: "https://example.com/airlock-expiry")
        let item = try XCTUnwrap(store.airlockResult.items.first)
        now = try XCTUnwrap(store.activeBrowserLease?.expiresAt)

        let outcome = await store.openAirlockNow(item)

        XCTAssertEqual(outcome, .opened(chrome.reference))
        XCTAssertNil(store.activeBrowserLease)
        XCTAssertEqual(
            launcher.calls,
            [
                .init(
                    url: item.normalized.originalURL,
                    browser: chrome.reference
                ),
            ]
        )
    }

    func testUnavailableLeaseTargetFallsThroughAndSurfacesHealthMessage() async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                browserLease: BrowserLease(
                    browser: safari.reference,
                    startedAt: now,
                    expiresAt: nil
                )
            )
        )
        let handler = FakeSystemBrowserHandler(
            handlers: .same(application(for: browserChange)),
            applications: [
                browserChange.reference: browserChange.appURL,
                chrome.reference: chrome.appURL,
            ]
        )
        let launcher = FakeURLLauncher()
        let store = makeStore(
            handler: handler,
            scheduler: StoreFakeBrowserLeaseScheduler(),
            launcher: launcher,
            browsers: [chrome],
            now: { now }
        )
        await store.activate()
        let url = try XCTUnwrap(
            URL(string: "https://example.com/uninstalled")
        )

        let disposition = await store.routeIncomingURL(url)

        XCTAssertEqual(disposition, .consumed)
        XCTAssertEqual(
            launcher.calls,
            [.init(url: url, browser: chrome.reference)]
        )
        XCTAssertEqual(
            store.message,
            "That browser is unavailable, so the temporary switch is paused. Rules and Google Chrome still apply."
        )
        XCTAssertNotNil(store.activeBrowserLease)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testSchedulerExpiryUpdatesStoreWithoutLaunchingOrOfferingUndo() async throws {
        var now = Date(timeIntervalSince1970: 1_900_000_000)
        try saveSmartConfiguration()
        let handler = makeHandler()
        let launcher = FakeURLLauncher()
        let scheduler = StoreFakeBrowserLeaseScheduler()
        let store = makeStore(
            handler: handler,
            scheduler: scheduler,
            launcher: launcher,
            now: { now }
        )
        await store.activate()
        XCTAssertTrue(
            store.borrowBrowser(safari, for: .fifteenMinutes)
        )
        now = try XCTUnwrap(scheduler.deadline)

        scheduler.fire()

        XCTAssertNil(store.activeBrowserLease)
        XCTAssertFalse(store.canUndoLease)
        XCTAssertTrue(launcher.calls.isEmpty)
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(
            store.message,
            "The temporary browser ended. Rules and Google Chrome are in use again."
        )
    }

    func testBorrowIsUnavailableUnlessSmartRoutingIsVerifiedActive() {
        let directHandler = FakeSystemBrowserHandler(
            handlers: .same(application(for: chrome)),
            applications: applications
        )
        let direct = makeStore(
            handler: directHandler,
            scheduler: StoreFakeBrowserLeaseScheduler()
        )

        XCTAssertFalse(
            direct.borrowBrowser(safari, for: .fifteenMinutes)
        )
        XCTAssertTrue(direct.borrowableBrowsers.isEmpty)
        XCTAssertNil(direct.activeBrowserLease)
        XCTAssertEqual(
            direct.message,
            "You can use another browser for a while only while Linkpick is sending links."
        )
        XCTAssertTrue(directHandler.setCalls.isEmpty)
    }

    private var applications: [BrowserReference: URL] {
        [
            browserChange.reference: browserChange.appURL,
            chrome.reference: chrome.appURL,
            safari.reference: safari.appURL,
        ]
    }

    private func saveSmartConfiguration() throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
    }

    private func makeHandler() -> FakeSystemBrowserHandler {
        FakeSystemBrowserHandler(
            handlers: .same(application(for: browserChange)),
            applications: applications
        )
    }

    private func makeStore(
        handler: FakeSystemBrowserHandler,
        scheduler: StoreFakeBrowserLeaseScheduler,
        launcher: FakeURLLauncher? = nil,
        browsers: [InstalledBrowser]? = nil,
        now: @escaping () -> Date = Date.init
    ) -> BrowserStore {
        BrowserStore(
            environment: AppEnvironment(
                browserCatalog: FakeBrowserCatalog(
                    browsers: browsers ?? [chrome, safari]
                ),
                systemBrowserHandler: handler,
                stateRepository: repository,
                urlLauncher: launcher ?? FakeURLLauncher(),
                now: now,
                leaseScheduler: scheduler
            )
        )
    }

    private func application(
        for browser: InstalledBrowser
    ) -> HandlerApplication {
        HandlerApplication(
            browser: browser.reference,
            applicationURL: browser.appURL
        )
    }
}

@MainActor
private final class StoreFakeBrowserLeaseScheduler:
    BrowserLeaseScheduling
{
    private(set) var deadline: Date?
    private var action: (() -> Void)?

    func schedule(at deadline: Date, action: @escaping () -> Void) {
        self.deadline = deadline
        self.action = action
    }

    func cancel() {
        deadline = nil
        action = nil
    }

    func fire() {
        let action = action
        deadline = nil
        self.action = nil
        action?()
    }
}
