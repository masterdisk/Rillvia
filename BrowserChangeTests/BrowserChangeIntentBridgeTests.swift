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

    func testAutomaticOpenAndLeaseUseSharedVerifiedSmartInvariant() async throws {
        struct Scenario {
            let name: String
            let configuration: RoutingConfiguration
            let handlers: HTTPHandlerSnapshot
            let hasPendingOperation: Bool
            let expected: Bool
        }
        let smart = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.reference,
            allowAutomationLeases: true
        )
        let scenarios = [
            Scenario(
                name: "active",
                configuration: smart,
                handlers: .same(application(browserChange)),
                hasPendingOperation: false,
                expected: true
            ),
            Scenario(
                name: "direct",
                configuration: RoutingConfiguration(
                    fallbackBrowser: chrome.reference,
                    allowAutomationLeases: true
                ),
                handlers: .same(application(chrome)),
                hasPendingOperation: false,
                expected: false
            ),
            Scenario(
                name: "suspended",
                configuration: smart,
                handlers: .same(application(safari)),
                hasPendingOperation: false,
                expected: false
            ),
            Scenario(
                name: "pending",
                configuration: smart,
                handlers: .same(application(browserChange)),
                hasPendingOperation: true,
                expected: false
            ),
            Scenario(
                name: "missing fallback",
                configuration: RoutingConfiguration(
                    mode: .smart,
                    allowAutomationLeases: true
                ),
                handlers: .same(application(browserChange)),
                hasPendingOperation: false,
                expected: false
            ),
            Scenario(
                name: "self fallback",
                configuration: RoutingConfiguration(
                    mode: .smart,
                    fallbackBrowser: browserChange.reference,
                    allowAutomationLeases: true
                ),
                handlers: .same(application(browserChange)),
                hasPendingOperation: false,
                expected: false
            ),
            Scenario(
                name: "unavailable fallback",
                configuration: RoutingConfiguration(
                    mode: .smart,
                    fallbackBrowser: missing.reference,
                    allowAutomationLeases: true
                ),
                handlers: .same(application(browserChange)),
                hasPendingOperation: false,
                expected: false
            ),
        ]

        for (index, scenario) in scenarios.enumerated() {
            try repository.saveConfiguration(scenario.configuration)
            handler.handlers = scenario.handlers
            let operationID = UUID()
            let pending = scenario.hasPendingOperation
                ? PendingHandlerOperation(
                    id: operationID,
                    startedAt: Date(timeIntervalSince1970: 1_900_000_000),
                    kind: .smartActivation,
                    desiredHandlers: .same(application(browserChange)),
                    undoReceipt: HandlerUndoReceipt(
                        operationID: operationID,
                        issuedAt: Date(timeIntervalSince1970: 1_900_000_000),
                        precondition: scenario.handlers,
                        restore: .same(application(chrome))
                    )
                )
                : nil
            try repository.saveHandlerJournal(
                HandlerOperationJournal(pendingOperation: pending)
            )
            let services = makeServices()
            let verified = try services.smartRoutingCoordinator
                .isVerifiedSmartRoutingActive()
            let url = try XCTUnwrap(
                URL(string: "https://example.com/parity-\(index)")
            )
            let automaticOpenAccepted =
                (try? await services.intentBridge.openLink(
                    url,
                    browserID: nil
                )) != nil
            let leaseAccepted =
                (try? services.intentBridge.startBrowserLease(
                    browserID: safari.id,
                    preset: .untilEnded
                )) != nil

            XCTAssertEqual(verified, scenario.expected, scenario.name)
            XCTAssertEqual(
                automaticOpenAccepted,
                verified,
                scenario.name
            )
            XCTAssertEqual(leaseAccepted, verified, scenario.name)
        }
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
            "Using the Work rule set."
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
            "Shortcuts can now switch browsers."
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
            "Using Safari for 15 minutes."
        )
        XCTAssertEqual(
            try repository.loadConfiguration().browserLease?.browser,
            safari.reference
        )
        XCTAssertEqual(
            try bridge.endBrowserLease(),
            "Stopped the temporary browser."
        )
        XCTAssertNil(try repository.loadConfiguration().browserLease)
        XCTAssertEqual(
            try bridge.endBrowserLease(),
            "No temporary browser is on."
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
            "Using Safari until you stop."
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
            "Using Safari again."
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

    func testPendingHandlerTransitionRejectsConfigurationMutationsBeforeRecovery() async throws {
        let work = RoutingProfile(name: "Work")
        let personal = RoutingProfile(name: "Personal")
        let pendingConfiguration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.reference,
            profiles: [work, personal],
            activeProfileID: work.id,
            allowAutomationLeases: true
        )
        try repository.saveConfiguration(pendingConfiguration)
        let operationID = UUID()
        try repository.saveHandlerJournal(
            HandlerOperationJournal(
                pendingOperation: PendingHandlerOperation(
                    id: operationID,
                    startedAt: Date(timeIntervalSince1970: 1_900_000_000),
                    kind: .smartActivation,
                    desiredHandlers: .same(application(browserChange)),
                    undoReceipt: HandlerUndoReceipt(
                        operationID: operationID,
                        issuedAt: Date(timeIntervalSince1970: 1_900_000_001),
                        precondition: .same(application(browserChange)),
                        restore: .same(application(chrome))
                    ),
                    completedSchemes: [.https, .http],
                    configurationBefore: .fresh,
                    configurationOnSuccess: pendingConfiguration
                )
            )
        )
        handler.handlers = .same(application(browserChange))
        let services = makeServices()

        XCTAssertThrowsError(
            try services.intentBridge.setAutomationLeasesAllowed(false)
        ) {
            XCTAssertEqual(
                $0 as? BrowserChangeAutomationError,
                .handlerTransitionInProgress
            )
        }
        XCTAssertThrowsError(
            try services.intentBridge.setRoutingProfile(personal.id)
        ) {
            XCTAssertEqual(
                $0 as? BrowserChangeAutomationError,
                .handlerTransitionInProgress
            )
        }
        XCTAssertEqual(
            try repository.loadConfiguration(),
            pendingConfiguration
        )
        XCTAssertTrue(
            try repository.loadConfigurationHistory().entries.isEmpty
        )

        _ = await services.smartRoutingCoordinator.reconcile()

        XCTAssertEqual(
            try repository.loadConfiguration(),
            pendingConfiguration,
            "Recovery must not silently overwrite a mutation reported as successful."
        )
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testConcurrentTransitionCannotOverwriteConsentOrProfileMutations() async throws {
        let work = RoutingProfile(name: "Work")
        let personal = RoutingProfile(name: "Personal")
        try repository.saveConfiguration(
            RoutingConfiguration(
                fallbackBrowser: chrome.reference,
                profiles: [work, personal],
                activeProfileID: work.id,
                allowAutomationLeases: true
            )
        )
        let services = makeServices()
        var mutationErrors: [BrowserChangeAutomationError?] = []
        handler.beforeSet = { [services] _, _ in
            do {
                if mutationErrors.isEmpty {
                    _ = try services.intentBridge
                        .setAutomationLeasesAllowed(false)
                } else {
                    _ = try services.intentBridge
                        .setRoutingProfile(personal.id)
                }
                mutationErrors.append(nil)
            } catch {
                mutationErrors.append(error as? BrowserChangeAutomationError)
            }
        }

        let outcome = await services.smartRoutingCoordinator.enable(
            fallback: chrome.reference
        )

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(
            mutationErrors,
            [.handlerTransitionInProgress, .handlerTransitionInProgress]
        )
        let completed = try repository.loadConfiguration()
        XCTAssertTrue(completed.allowAutomationLeases)
        XCTAssertEqual(completed.activeProfileID, work.id)
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            1
        )
    }

    func testDeniedColdRuntimeLeaseDoesNotReconcileExpiredState() throws {
        let expiredLease = BrowserLease(
            browser: safari.reference,
            startedAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )
        let original = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.reference,
            browserLease: expiredLease,
            allowAutomationLeases: false
        )
        try repository.saveConfiguration(original)
        handler.handlers = .same(application(browserChange))
        let runtime = BrowserChangeAppRuntime(
            environment: makeEnvironment(),
            browserChange: browserChange.reference,
            registerIntentBridge: { _ in }
        )

        XCTAssertThrowsError(
            try runtime.services.intentBridge.startBrowserLease(
                browserID: safari.id,
                preset: .untilEnded
            )
        )

        XCTAssertEqual(try repository.loadConfiguration(), original)
        XCTAssertTrue(
            try repository.loadConfigurationHistory().entries.isEmpty
        )
    }

    func testIntentMutationsPublishToStoreWithoutManualRefresh() async throws {
        let work = RoutingProfile(name: "Work")
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                profiles: [work],
                allowAutomationLeases: true
            )
        )
        handler.handlers = .same(application(browserChange))
        let runtime = BrowserChangeAppRuntime(
            environment: makeEnvironment(),
            browserChange: browserChange.reference,
            registerIntentBridge: { _ in }
        )
        let bridge = runtime.services.intentBridge
        let store = runtime.store

        _ = try bridge.startBrowserLease(
            browserID: safari.id,
            preset: .untilEnded
        )
        XCTAssertEqual(
            store.activeBrowserLease?.browser,
            safari.reference
        )

        _ = try bridge.endBrowserLease()
        XCTAssertNil(store.activeBrowserLease)

        _ = try await bridge.restorePreviousBrowser()
        XCTAssertEqual(
            store.activeBrowserLease?.browser,
            safari.reference
        )

        _ = try bridge.setRoutingProfile(work.id)
        XCTAssertEqual(store.routingConfiguration.activeProfileID, work.id)

        _ = try bridge.setAutomationLeasesAllowed(false)
        XCTAssertFalse(store.allowsAutomationLeases)
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
