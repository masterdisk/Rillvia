import AppKit
import Foundation
import XCTest
@testable import Rillvia

@MainActor
final class BrowserStoreSmartRoutingTests: XCTestCase {
    private enum TestLaunchError: Error {
        case unavailable
    }

    private let rillvia = InstalledBrowser(
        id: "com.rillvia.app",
        name: "Rillvia",
        version: "1.0",
        appURL: URL(fileURLWithPath: "/Applications/Rillvia.app")
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
                "BrowserStoreSmartRoutingTests-\(UUID().uuidString)"
            )
        repository = StateRepository(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testFreshStoreReconcilesAsDirect() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let store = makeStore(handler: handler)

        await store.activate()

        XCTAssertEqual(store.routingState, .direct)
        XCTAssertEqual(store.defaultBundleID, chrome.id)
        XCTAssertEqual(store.routingModeTitle, "Usual browser")
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testSmartActivationSeedsFallbackAndMarksItAsChosenBrowser() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let store = makeStore(handler: handler)

        await store.enableSmartRouting()

        XCTAssertEqual(
            store.routingState,
            .smartActive(chrome.reference)
        )
        XCTAssertEqual(store.defaultBundleID, chrome.id)
        XCTAssertEqual(store.routingModeTitle, "Sending links")
        XCTAssertEqual(handler.handlers, .same(application(for: rillvia)))
        XCTAssertEqual(store.message, "Links open in Google Chrome, unless a rule says otherwise.")
    }

    func testSmartExternalOwnershipPublishesSuspendedWithoutReclaiming() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
        let handler = makeHandler(handlers: .same(application(for: safari)))
        let store = makeStore(handler: handler)

        await store.activate()

        XCTAssertEqual(
            store.routingState,
            .smartSuspended(chrome.reference)
        )
        XCTAssertEqual(store.defaultBundleID, chrome.id)
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertTrue(store.routingModeDetail.contains("will not take it back"))
    }

    func testTurningOnPausedRulesResumesWithSavedFallback() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
        let handler = makeHandler(handlers: .same(application(for: safari)))
        let store = makeStore(handler: handler)
        await store.activate()

        await store.enableSmartRouting()

        XCTAssertEqual(store.routingState, .smartActive(chrome.reference))
        XCTAssertEqual(handler.handlers, .same(application(for: rillvia)))
        XCTAssertEqual(store.message, "Links open in Google Chrome, unless a rule says otherwise.")
    }

    func testTurningOffPausedRulesKeepsCurrentMacOSBrowser() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
        let handler = makeHandler(handlers: .same(application(for: safari)))
        let store = makeStore(handler: handler)
        await store.activate()

        await store.disableSmartRouting()

        XCTAssertEqual(store.routingState, .direct)
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(handler.handlers, .same(application(for: safari)))
        XCTAssertEqual(store.message, "Stopped. Safari is the usual browser.")
    }

    func testSuspendedSplitHandlersStillDisplayConfiguredFallback() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
        let handler = makeHandler(
            handlers: HTTPHandlerSnapshot(
                http: application(for: safari),
                https: application(for: rillvia)
            )
        )
        let store = makeStore(handler: handler)

        await store.activate()

        XCTAssertEqual(
            store.routingState,
            .smartSuspended(chrome.reference)
        )
        XCTAssertEqual(store.defaultBrowserName, "Google Chrome")
        XCTAssertEqual(store.defaultBundleID, chrome.id)
        XCTAssertNil(store.currentMacOSBrowser)
        XCTAssertEqual(store.currentMacOSBrowserName, "HTTP and HTTPS differ")
    }

    func testChoosingBrowserInSmartModeOnlyChangesFallback() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let store = makeStore(handler: handler)
        await store.enableSmartRouting()
        let activationCalls = handler.setCalls

        await store.makeDefault(safari)

        XCTAssertEqual(handler.setCalls, activationCalls)
        XCTAssertEqual(handler.handlers, .same(application(for: rillvia)))
        XCTAssertEqual(
            store.routingState,
            .smartActive(safari.reference)
        )
        XCTAssertEqual(store.defaultBundleID, safari.id)
        XCTAssertEqual(store.message, "Safari is now the browser used when no rule matches.")
    }

    func testChangingFallbackSignalsAQueuedURLRetry() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let store = makeStore(handler: handler)
        await store.enableSmartRouting()
        var retryWasRequested = false
        store.onRoutingAvailabilityChanged = {
            retryWasRequested = true
        }

        await store.makeDefault(safari)

        XCTAssertTrue(retryWasRequested)
    }

    func testDisablingSmartRoutingMakesFallbackTheDirectDefault() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let store = makeStore(handler: handler)
        await store.enableSmartRouting()

        await store.disableSmartRouting()

        XCTAssertEqual(handler.handlers, .same(application(for: chrome)))
        XCTAssertEqual(store.routingState, .direct)
        XCTAssertEqual(store.defaultBundleID, chrome.id)
        XCTAssertEqual(
            store.message,
            "Stopped. Google Chrome is the usual browser."
        )
    }

    func testIncomingWebURLDispatchesToFallbackWithoutPersistingURLData() async throws {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let launcher = FakeURLLauncher()
        let store = makeStore(handler: handler, launcher: launcher)
        let url = URL(
            string: "https://example.com/private/path?secret=value"
        )!
        await store.enableSmartRouting()

        let disposition = await store.routeIncomingURL(url)

        XCTAssertEqual(disposition, .consumed)
        XCTAssertEqual(
            launcher.calls,
            [.init(url: url, browser: chrome.reference)]
        )
        let persistedText = try persistedStateText()
        XCTAssertFalse(persistedText.contains("example.com"))
        XCTAssertFalse(persistedText.contains("private"))
        XCTAssertFalse(persistedText.contains("secret"))
    }

    func testUnsupportedIncomingURLIsRejectedAndNotLaunched() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let launcher = FakeURLLauncher()
        let store = makeStore(handler: handler, launcher: launcher)
        await store.enableSmartRouting()

        let disposition = await store.routeIncomingURL(
            URL(fileURLWithPath: "/tmp/private.txt")
        )

        XCTAssertEqual(disposition, .consumed)
        XCTAssertTrue(launcher.calls.isEmpty)
        XCTAssertEqual(
            store.message,
            "Rillvia only opens HTTP and HTTPS links."
        )
    }

    func testUnlaunchableFallbackStopsAndSurfacesRecoveryMessage() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let launcher = FakeURLLauncher()
        launcher.error = TestLaunchError.unavailable
        let store = makeStore(handler: handler, launcher: launcher)
        await store.enableSmartRouting()

        let disposition = await store.routeIncomingURL(
            URL(string: "https://example.com/retry")!
        )

        XCTAssertEqual(disposition, .retryLater)
        XCTAssertEqual(launcher.calls.count, 1)
        XCTAssertEqual(
            store.message,
            "Google Chrome could not open the link. Reinstall it or choose another browser."
        )
    }

    func testIncomingURLWhilePausedOpensInTheMacOSBrowserWithoutReclaiming() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let launcher = FakeURLLauncher()
        let store = makeStore(handler: handler, launcher: launcher)
        await store.enableSmartRouting()
        handler.handlers = .same(application(for: safari))
        let url = URL(string: "https://example.com/late-event")!

        let disposition = await store.routeIncomingURL(url)

        XCTAssertEqual(disposition, .consumed)
        XCTAssertEqual(launcher.calls, [.init(url: url, browser: safari.reference)])
        XCTAssertEqual(
            store.routingState,
            .smartSuspended(chrome.reference)
        )
        XCTAssertEqual(handler.setCalls.count, 2)
    }

    func testIncomingURLWithRulesOffOpensInTheMacOSBrowser() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let launcher = FakeURLLauncher()
        let store = makeStore(handler: handler, launcher: launcher)
        await store.activate()
        let url = URL(string: "https://example.com/direct")!

        let disposition = await store.routeIncomingURL(url)

        XCTAssertEqual(disposition, .consumed)
        XCTAssertEqual(launcher.calls, [.init(url: url, browser: chrome.reference)])
        XCTAssertEqual(store.routingState, .direct)
    }

    func testBrokenRuleBrowserFallsBackToOtherLinksInsteadOfHoldingTheQueue() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let launcher = FakeURLLauncher()
        let store = makeStore(handler: handler, launcher: launcher)
        await store.enableSmartRouting()
        XCTAssertNotNil(store.createRule(domain: "example.com", browser: safari.reference))
        launcher.failingBrowsers = [safari.reference]
        let url = URL(string: "https://example.com/report")!

        let disposition = await store.routeIncomingURL(url)

        XCTAssertEqual(disposition, .consumed)
        XCTAssertEqual(
            launcher.calls,
            [.init(url: url, browser: safari.reference), .init(url: url, browser: chrome.reference)]
        )
        XCTAssertEqual(store.message, "Safari could not open the link, so it opened in Google Chrome.")

        let repeated = await store.routeIncomingURL(url)

        XCTAssertEqual(repeated, .consumed)
        XCTAssertEqual(store.message, "Rillvia stopped a repeated link.")
    }

    private func makeStore(
        handler: FakeSystemBrowserHandler,
        launcher: FakeURLLauncher? = nil
    ) -> BrowserStore {
        let launcher = launcher ?? FakeURLLauncher()
        return BrowserStore(
            environment: AppEnvironment(
                browserCatalog: FakeBrowserCatalog(
                    browsers: [chrome, safari]
                ),
                systemBrowserHandler: handler,
                stateRepository: repository,
                urlLauncher: launcher
            )
        )
    }

    private func makeHandler(
        handlers: HTTPHandlerSnapshot
    ) -> FakeSystemBrowserHandler {
        FakeSystemBrowserHandler(
            handlers: handlers,
            applications: [
                rillvia.reference: rillvia.appURL,
                chrome.reference: chrome.appURL,
                safari.reference: safari.appURL,
            ]
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

    private func persistedStateText() throws -> String {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        )
        return try names.map { name in
            let url = directory.appendingPathComponent(name)
            return String(
                data: try Data(contentsOf: url),
                encoding: .utf8
            ) ?? ""
        }.joined(separator: "\n")
    }
}

@MainActor
final class AppDelegateIncomingURLTests: XCTestCase {
    func testAppDelegateQueuesOpenEventsBeforeStoreAttachment() {
        let queue = IncomingURLQueue()
        let delegate = AppDelegate(incomingURLQueue: queue)
        let urls = [
            URL(string: "https://example.com/first")!,
            URL(string: "http://example.com/second")!,
        ]

        delegate.application(NSApplication.shared, open: urls)

        XCTAssertEqual(queue.pendingCount, 2)
    }
}

final class AppLaunchWindowPolicyTests: XCTestCase {
    func testNormalColdLaunchRequestsTheMainWindowOnce() {
        var policy = AppLaunchWindowPolicy()

        XCTAssertTrue(policy.finishLaunching())
        XCTAssertFalse(policy.finishLaunching())
    }

    func testURLColdLaunchSuppressesTheMainWindow() {
        var policy = AppLaunchWindowPolicy()

        policy.recordIncomingURLs()

        XCTAssertFalse(policy.finishLaunching())
    }

    func testURLReceivedAfterNormalLaunchDoesNotChangeInitialDecision() {
        var policy = AppLaunchWindowPolicy()

        XCTAssertTrue(policy.finishLaunching())
        policy.recordIncomingURLs()

        XCTAssertFalse(policy.finishLaunching())
        XCTAssertTrue(policy.shouldSuppressMainWindow)
        XCTAssertFalse(policy.shouldOpenOnReopen(hasVisibleWindows: false))
    }

    func testUserRequestClearsIncomingURLSuppression() {
        var policy = AppLaunchWindowPolicy()
        policy.recordIncomingURLs()
        let generation = policy.generation

        policy.allowWindowPresentation()

        XCTAssertFalse(policy.shouldSuppressMainWindow)
        XCTAssertTrue(policy.shouldOpenOnReopen(hasVisibleWindows: false))
        policy.finishHandlingIncomingURLs(generation: generation)
        XCTAssertFalse(policy.shouldSuppressMainWindow)
    }

    func testLinkReopenStaysClosedUntilTheURLDeadlinePasses() {
        var policy = AppLaunchWindowPolicy()

        XCTAssertEqual(
            policy.reopenAction(hasVisibleWindows: false),
            .openAfterURLDeadline
        )

        policy.recordIncomingURLs()

        XCTAssertEqual(
            policy.reopenAction(hasVisibleWindows: false),
            .keepClosed
        )
        XCTAssertEqual(
            policy.reopenAction(hasVisibleWindows: true),
            .keepClosed
        )
    }

    func testStaleURLHandlingDoesNotClearANewerSuppression() {
        var policy = AppLaunchWindowPolicy()
        policy.recordIncomingURLs()
        let first = policy.generation
        policy.recordIncomingURLs()

        policy.finishHandlingIncomingURLs(generation: first)

        XCTAssertTrue(policy.shouldSuppressMainWindow)
        XCTAssertFalse(policy.shouldOpenOnReopen(hasVisibleWindows: false))
    }
}
