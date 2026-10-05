import Foundation
import XCTest
@testable import BrowserChange

@MainActor
final class BrowserChangeIntentBridgeTests: XCTestCase {
    private let browserChange = InstalledBrowser(
        id: "com.browserchange.BrowserChange",
        name: "BrowserChange",
        version: "1",
        appURL: URL(fileURLWithPath: "/Applications/BrowserChange.app")
    )
    private let chrome = InstalledBrowser(
        id: "com.google.Chrome",
        name: "Google Chrome",
        version: "140",
        appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
    )
    private let safari = InstalledBrowser(
        id: "com.apple.Safari",
        name: "Safari",
        version: "26",
        appURL: URL(fileURLWithPath: "/Applications/Safari.app")
    )
    private let missing = InstalledBrowser(
        id: "com.example.Missing",
        name: "Missing Browser",
        version: "1",
        appURL: URL(fileURLWithPath: "/Applications/Missing.app")
    )
    private let imaginary = InstalledBrowser(
        id: "org.example.imaginary",
        name: "Imaginary Browser",
        version: "1",
        appURL: URL(fileURLWithPath: "/Applications/Imaginary.app"),
        isImaginary: true
    )

    private var directory: URL!
    private var repository: StateRepository!
    private var handler: FakeSystemBrowserHandler!
    private var launcher: FakeURLLauncher!
    private var catalog: FakeBrowserCatalog!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserChangeIntentBridgeTests-\(UUID().uuidString)"
            )
        repository = StateRepository(baseDirectory: directory)
        handler = FakeSystemBrowserHandler(
            handlers: .same(application(chrome)),
            applications: [
                browserChange.reference: browserChange.appURL,
                chrome.reference: chrome.appURL,
                safari.reference: safari.appURL,
            ]
        )
        launcher = FakeURLLauncher()
        catalog = FakeBrowserCatalog(
            browsers: [
                browserChange,
                missing,
                safari,
                imaginary,
                chrome,
            ]
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testQueriesReturnOnlyCurrentExternalBrowsersAndEnabledProfiles() throws {
        let enabled = RoutingProfile(name: "Work")
        let disabled = RoutingProfile(name: "Deleted")
        try repository.saveConfiguration(
            RoutingConfiguration(
                profiles: [
                    enabled,
                    RoutingProfile(
                        id: disabled.id,
                        name: disabled.name,
                        isEnabled: false
                    ),
                ]
            )
        )
        let bridge = makeBridge()

        XCTAssertEqual(
            try bridge.availableBrowsers().map(\.id),
            [chrome.id, safari.id]
        )
        XCTAssertEqual(
            try bridge.availableProfiles(),
            [
                AutomationRoutingProfile(
                    id: enabled.id,
                    name: enabled.name
                ),
            ]
        )

        catalog.browsers.removeAll { $0.id == safari.id }
        var configuration = try repository.loadConfiguration()
        configuration.profiles.removeAll { $0.id == enabled.id }
        try repository.saveConfiguration(configuration)

        XCTAssertEqual(
            try bridge.availableBrowsers().map(\.id),
            [chrome.id]
        )
        XCTAssertTrue(try bridge.availableProfiles().isEmpty)
    }

    func testExplicitOpenWorksInDirectModeWithoutChangingHandlers() async throws {
        try repository.saveConfiguration(.fresh)
        let bridge = makeBridge()
        let url = try XCTUnwrap(
            URL(string: "https://example.com/private?secret=value")
        )

        let message = try await bridge.openLink(
            url,
            browserID: safari.id
        )

        XCTAssertEqual(message, "Opened the link in Safari.")
        XCTAssertEqual(
            launcher.calls,
            [.init(url: url, browser: safari.reference)]
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(try repository.loadConfiguration().mode, .direct)
        XCTAssertFalse(try persistedText().contains("/private"))
        XCTAssertFalse(try persistedText().contains("secret=value"))
    }

    func testAutomaticOpenRequiresVerifiedSmartModeAndUsesRoutingEngine() async throws {
        let profileID = UUID()
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.reference,
            domainRules: [
                DomainRule(
                    domain: "example.com",
                    browser: safari.reference,
                    profileID: profileID
                ),
            ],
            profiles: [
                RoutingProfile(id: profileID, name: "Work"),
            ],
            activeProfileID: profileID
        )
        try repository.saveConfiguration(configuration)
        let bridge = makeBridge()
        let url = try XCTUnwrap(URL(string: "https://example.com/private"))

        await XCTAssertThrowsErrorAsync(
            try await bridge.openLink(url, browserID: nil),
            equals: .smartRoutingUnavailable
        )
        XCTAssertTrue(launcher.calls.isEmpty)

        handler.handlers = .same(application(browserChange))
        let message = try await bridge.openLink(url, browserID: nil)

        XCTAssertEqual(message, "Opened the link in Safari.")
        XCTAssertEqual(
            launcher.calls,
            [.init(url: url, browser: safari.reference)]
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testOpenLinkReportsUnsupportedSelfAndMissingTargets() async throws {
        let bridge = makeBridge()
        let webURL = try XCTUnwrap(URL(string: "https://example.com"))
        let fileURL = URL(fileURLWithPath: "/tmp/private")

        await XCTAssertThrowsErrorAsync(
            try await bridge.openLink(fileURL, browserID: safari.id),
            equals: .unsupportedURL
        )
        await XCTAssertThrowsErrorAsync(
            try await bridge.openLink(
                webURL,
                browserID: browserChange.id
            ),
            equals: .selfTarget
        )
        await XCTAssertThrowsErrorAsync(
            try await bridge.openLink(webURL, browserID: missing.id),
            equals: .browserUnavailable
        )

        XCTAssertTrue(launcher.calls.isEmpty)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testSetProfilePersistsSnapshotAndRejectsUnavailableProfile() throws {
        let work = RoutingProfile(name: "Work")
        let disabled = RoutingProfile(name: "Disabled", isEnabled: false)
        try repository.saveConfiguration(
            RoutingConfiguration(
                profiles: [work, disabled]
            )
        )
        let bridge = makeBridge()

        XCTAssertEqual(
            try bridge.setRoutingProfile(work.id),
            "Using the Work routing profile."
        )
        XCTAssertEqual(
            try repository.loadConfiguration().activeProfileID,
            work.id
        )
        XCTAssertEqual(
            try repository.loadConfiguration().mode,
            .direct
        )
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            1
        )
        XCTAssertThrowsError(
            try bridge.setRoutingProfile(disabled.id)
        ) {
            XCTAssertEqual(
                $0 as? BrowserChangeAutomationError,
                .profileUnavailable
            )
        }
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            1
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testAutomationLeasePermissionCanBePersistedWithoutChangingMode() throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
        let bridge = makeBridge()

        XCTAssertEqual(
            try bridge.setAutomationLeasesAllowed(true),
            "Shortcuts may now start browser leases."
        )

        let saved = try repository.loadConfiguration()
        XCTAssertEqual(saved.mode, .smart)
        XCTAssertTrue(saved.allowAutomationLeases)
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            1
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testStartLeaseDeniesBeforeAnyMutationWhenPermissionIsOff() async throws {
        let expiredLease = BrowserLease(
            browser: safari.reference,
            startedAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )
        let original = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.reference,
            browserLease: expiredLease
        )
        try repository.saveConfiguration(original)
        handler.handlers = .same(application(browserChange))
        let bridge = makeBridge()

        await XCTAssertThrowsErrorAsync(
            try bridge.startBrowserLease(
                browserID: safari.id,
                preset: .fifteenMinutes
            ),
            equals: .automationLeasePermissionDisabled
        )

        XCTAssertEqual(try repository.loadConfiguration(), original)
        XCTAssertTrue(
            try repository.loadConfigurationHistory().entries.isEmpty
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testStartLeaseRejectsDirectSuspendedAndInvalidTargetsWithoutWrites() async throws {
        let bridge = makeBridge()
        try repository.saveConfiguration(
            RoutingConfiguration(allowAutomationLeases: true)
        )

        await XCTAssertThrowsErrorAsync(
            try bridge.startBrowserLease(
                browserID: safari.id,
                preset: .thirtyMinutes
            ),
            equals: .smartRoutingUnavailable
        )
        XCTAssertEqual(try repository.loadConfiguration().mode, .direct)
        XCTAssertTrue(
            try repository.loadConfigurationHistory().entries.isEmpty
        )

        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                allowAutomationLeases: true
            )
        )
        await XCTAssertThrowsErrorAsync(
            try bridge.startBrowserLease(
                browserID: safari.id,
                preset: .thirtyMinutes
            ),
            equals: .smartRoutingUnavailable
        )

        handler.handlers = .same(application(browserChange))
        await XCTAssertThrowsErrorAsync(
            try bridge.startBrowserLease(
                browserID: browserChange.id,
                preset: .thirtyMinutes
            ),
            equals: .selfTarget
        )
        await XCTAssertThrowsErrorAsync(
            try bridge.startBrowserLease(
                browserID: missing.id,
                preset: .thirtyMinutes
            ),
            equals: .browserUnavailable
        )

        XCTAssertNil(try repository.loadConfiguration().browserLease)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testStartAndEndLeaseAreActionableIdempotentAndNeverWriteHandlers() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                allowAutomationLeases: true
            )
        )
        handler.handlers = .same(application(browserChange))
        let bridge = makeBridge()

        XCTAssertEqual(
            try bridge.startBrowserLease(
                browserID: safari.id,
                preset: .fifteenMinutes
            ),
            "Borrowing Safari for 15 minutes."
        )
        XCTAssertEqual(
            try repository.loadConfiguration().browserLease?.browser,
            safari.reference
        )
        XCTAssertEqual(
            try bridge.endBrowserLease(),
            "Ended the browser lease."
        )
        XCTAssertNil(try repository.loadConfiguration().browserLease)
        XCTAssertEqual(
            try bridge.endBrowserLease(),
            "No browser lease is active."
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testUntilEndedLeaseHasNaturalActionableResult() throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                allowAutomationLeases: true
            )
        )
        handler.handlers = .same(application(browserChange))

        XCTAssertEqual(
            try makeBridge().startBrowserLease(
                browserID: safari.id,
                preset: .untilEnded
            ),
            "Borrowing Safari until ended."
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testRestorePrefersLeaseUndoWithoutWritingHandlers() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                allowAutomationLeases: true
            )
        )
        handler.handlers = .same(application(browserChange))
        let bridge = makeBridge()
        _ = try bridge.startBrowserLease(
            browserID: safari.id,
            preset: .untilEnded
        )
        _ = try bridge.startBrowserLease(
            browserID: chrome.id,
            preset: .untilEnded
        )

        let message = try await bridge.restorePreviousBrowser()
        XCTAssertEqual(
            message,
            "Restored the previous Safari browser lease."
        )

        XCTAssertEqual(
            try repository.loadConfiguration().browserLease?.browser,
            safari.reference
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testRestoreFallsBackToSafeDirectHandlerUndoAndReportsNoneAvailable() async throws {
        let services = makeServices()
        let switchOutcome = await services.transactionCoordinator
            .switchDirect(to: safari.reference)
        XCTAssertEqual(
            switchOutcome,
            .succeeded
        )

        let restoreMessage = try await services.intentBridge
            .restorePreviousBrowser()
        XCTAssertEqual(
            restoreMessage,
            "Restored the previous web-link handlers."
        )
        XCTAssertEqual(handler.handlers, .same(application(chrome)))
        XCTAssertEqual(
            handler.setCalls,
            [
                .init(browser: safari.reference, scheme: .https),
                .init(browser: safari.reference, scheme: .http),
                .init(browser: chrome.reference, scheme: .https),
                .init(browser: chrome.reference, scheme: .http),
            ]
        )

        await XCTAssertThrowsErrorAsync(
            try await services.intentBridge.restorePreviousBrowser(),
            equals: .noUndoAvailable
        )
    }

    func testStoreAndIntentBridgeShareLeaseUndoState() throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                allowAutomationLeases: true
            )
        )
        handler.handlers = .same(application(browserChange))
        let services = makeServices()
        let store = BrowserStore(services: services)

        _ = try services.intentBridge.startBrowserLease(
            browserID: safari.id,
            preset: .untilEnded
        )
        store.refresh()

        XCTAssertEqual(
            store.activeBrowserLease?.browser,
            safari.reference
        )
        XCTAssertTrue(store.canUndoLease)
        XCTAssertTrue(store.undoBrowserLeaseChange())
        XCTAssertNil(try repository.loadConfiguration().browserLease)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testStorePersistsAutomationLeasePermissionThroughSharedBridge() throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
        let services = makeServices()
        let store = BrowserStore(services: services)

        XCTAssertFalse(store.allowsAutomationLeases)
        XCTAssertTrue(store.setAutomationLeasesAllowed(true))

        XCTAssertTrue(store.allowsAutomationLeases)
        XCTAssertTrue(
            try repository.loadConfiguration()
                .allowAutomationLeases
        )
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            1
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testAppRuntimeRegistersTheSameBridgeUsedByItsStore() {
        var registeredBridge: BrowserChangeIntentBridge?
        let runtime = BrowserChangeAppRuntime(
            environment: makeEnvironment(),
            browserChange: browserChange.reference
        ) {
            registeredBridge = $0
        }

        XCTAssertTrue(
            registeredBridge === runtime.services.intentBridge
        )
        XCTAssertEqual(
            runtime.store.routingConfiguration,
            runtime.services.smartRoutingCoordinator.configuration
        )
    }

    private func makeBridge() -> BrowserChangeIntentBridge {
        makeServices().intentBridge
    }

    private func makeServices() -> BrowserChangeServices {
        BrowserChangeServices(
            environment: makeEnvironment(),
            browserChange: browserChange.reference
        )
    }

    private func makeEnvironment() -> AppEnvironment {
        AppEnvironment(
            browserCatalog: catalog,
            systemBrowserHandler: handler,
            stateRepository: repository,
            urlLauncher: launcher,
            leaseScheduler: FakeIntentLeaseScheduler()
        )
    }

    private func application(
        _ browser: InstalledBrowser
    ) -> HandlerApplication {
        HandlerApplication(
            browser: browser.reference,
            applicationURL: browser.appURL
        )
    }

    private func persistedText() throws -> String {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ""
        }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
    }
}

@MainActor
private final class FakeIntentLeaseScheduler: BrowserLeaseScheduling {
    func schedule(at deadline: Date, action: @escaping () -> Void) {}
    func cancel() {}
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    equals expected: BrowserChangeAutomationError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error.", file: file, line: line)
    } catch {
        XCTAssertEqual(
            error as? BrowserChangeAutomationError,
            expected,
            file: file,
            line: line
        )
    }
}
