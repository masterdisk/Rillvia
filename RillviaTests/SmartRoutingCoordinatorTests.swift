import Foundation
import XCTest
@testable import Rillvia

@MainActor
final class SmartRoutingCoordinatorTests: XCTestCase {
    private enum TestFailure: Error {
        case handlerChange
    }

    private let rillvia = HandlerApplication(
        browser: BrowserReference(
            bundleIdentifier: "com.rillvia.app"
        ),
        applicationURL: URL(
            fileURLWithPath: "/Applications/Rillvia.app"
        )
    )
    private let chrome = HandlerApplication(
        browser: BrowserReference(bundleIdentifier: "com.google.Chrome"),
        applicationURL: URL(
            fileURLWithPath: "/Applications/Google Chrome.app"
        )
    )
    private let safari = HandlerApplication(
        browser: BrowserReference(bundleIdentifier: "com.apple.Safari"),
        applicationURL: URL(fileURLWithPath: "/Applications/Safari.app")
    )

    private var directory: URL!
    private var repository: StateRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SmartRoutingCoordinatorTests-\(UUID().uuidString)"
            )
        repository = StateRepository(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testFreshConfigurationRemainsDirectWithoutMutatingHandlers() async {
        let handler = makeHandler(handlers: .same(chrome))
        let coordinator = makeCoordinator(handler: handler)

        let status = await coordinator.reconcile()

        XCTAssertEqual(status, .direct)
        XCTAssertEqual(coordinator.configuration, .fresh)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testActivationSeedsAgreedDirectHandlerAndPersistsSmartAfterOwnership() async throws {
        let handler = makeHandler(handlers: .same(chrome))
        var persistedModeBeforeEachMutation: [RoutingMode] = []
        var pendingKinds: [HandlerOperationKind?] = []
        handler.beforeSet = { [repository] _, _ in
            persistedModeBeforeEachMutation.append(
                (try? repository?.loadConfiguration().mode) ?? .smart
            )
            pendingKinds.append(
                try? repository?.loadHandlerJournal()
                    .pendingOperation?.kind
            )
        }
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.enable()

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(
            handler.setCalls,
            [
                .init(browser: rillvia.browser, scheme: .https),
                .init(browser: rillvia.browser, scheme: .http),
            ]
        )
        XCTAssertEqual(persistedModeBeforeEachMutation, [.direct, .direct])
        XCTAssertEqual(
            pendingKinds,
            [.smartActivation, .smartActivation]
        )
        XCTAssertEqual(handler.handlers, .same(rillvia))
        XCTAssertEqual(
            try repository.loadConfiguration(),
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.browser
            )
        )
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.map(
                \.configuration
            ),
            [
                RoutingConfiguration(
                    mode: .smart,
                    fallbackBrowser: chrome.browser
                ),
            ]
        )
        XCTAssertEqual(coordinator.status, .active(chrome.browser))
    }

    func testActivationPartialFailureRollsBackAndRemainsDirect() async throws {
        let handler = makeHandler(handlers: .same(chrome))
        handler.setErrorsByCall[1] = TestFailure.handlerChange
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.enable(fallback: chrome.browser)

        XCTAssertEqual(
            outcome,
            .failed(.handlerTransaction(.handlerChangeFailed))
        )
        XCTAssertEqual(handler.handlers, .same(chrome))
        XCTAssertEqual(try repository.loadConfiguration(), .fresh)
        XCTAssertEqual(coordinator.status, .direct)
    }

    func testActivationPreflightsFutureHistoryBeforeMutatingHandlers() async throws {
        let historyURL = directory.appendingPathComponent(
            "configuration-history.json"
        )
        let futureHistory = Data(
            #"{"schemaVersion":999,"entries":[]}"#.utf8
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try futureHistory.write(to: historyURL)
        let handler = makeHandler(handlers: .same(chrome))
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.enable(
            fallback: chrome.browser
        )

        XCTAssertEqual(
            outcome,
            .failed(.handlerTransaction(.statePersistenceFailed))
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(handler.handlers, .same(chrome))
        XCTAssertEqual(try repository.loadConfiguration(), .fresh)
        XCTAssertEqual(try Data(contentsOf: historyURL), futureHistory)
        XCTAssertEqual(try repository.loadHandlerJournal(), .fresh)
        XCTAssertEqual(coordinator.status, .direct)
    }

    func testActivationRejectsMissingAndSelfFallbackWithoutMutation() async {
        let missingHandler = makeHandler(handlers: .missing)
        let missingCoordinator = makeCoordinator(handler: missingHandler)
        let missingOutcome = await missingCoordinator.enable()

        XCTAssertEqual(
            missingOutcome,
            .failed(.missingFallback)
        )
        XCTAssertTrue(missingHandler.setCalls.isEmpty)

        let selfHandler = makeHandler(handlers: .same(chrome))
        let selfCoordinator = makeCoordinator(handler: selfHandler)
        let selfOutcome = await selfCoordinator.enable(
            fallback: rillvia.browser
        )

        XCTAssertEqual(
            selfOutcome,
            .failed(.selfFallback)
        )
        XCTAssertTrue(selfHandler.setCalls.isEmpty)
    }

    func testDeactivationMakesConfiguredFallbackDirectBeforePersistingDirect() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.browser
            )
        )
        let handler = makeHandler(handlers: .same(rillvia))
        var persistedModeBeforeEachMutation: [RoutingMode] = []
        handler.beforeSet = { [repository] _, _ in
            persistedModeBeforeEachMutation.append(
                (try? repository?.loadConfiguration().mode) ?? .direct
            )
        }
        let coordinator = makeCoordinator(handler: handler)
        _ = await coordinator.reconcile()

        let outcome = await coordinator.disable()

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(
            handler.setCalls,
            [
                .init(browser: chrome.browser, scheme: .https),
                .init(browser: chrome.browser, scheme: .http),
            ]
        )
        XCTAssertEqual(persistedModeBeforeEachMutation, [.smart, .smart])
        XCTAssertEqual(handler.handlers, .same(chrome))
        XCTAssertEqual(try repository.loadConfiguration().mode, .direct)
        XCTAssertEqual(coordinator.status, .direct)
    }

    func testConfiguredSmartWithExternalOwnershipIsSuspendedWithoutReclaiming() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.browser
            )
        )
        let handler = makeHandler(handlers: .same(safari))
        let coordinator = makeCoordinator(handler: handler)

        let status = await coordinator.reconcile()

        XCTAssertEqual(status, .suspended(chrome.browser))
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(handler.handlers, .same(safari))
    }

    func testChangingFallbackInSmartModeDoesNotMutateSystemHandlers() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.browser
            )
        )
        let handler = makeHandler(handlers: .same(rillvia))
        let coordinator = makeCoordinator(handler: handler)
        _ = await coordinator.reconcile()

        let outcome = coordinator.changeFallback(to: safari.browser)

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(handler.handlers, .same(rillvia))
        XCTAssertEqual(
            try repository.loadConfiguration().fallbackBrowser,
            safari.browser
        )
        XCTAssertEqual(coordinator.status, .active(safari.browser))
    }

    func testSmartModeTransitionsNeverCarryAStaleBrowserLease() async throws {
        let lease = BrowserLease(
            browser: safari.browser,
            startedAt: Date(timeIntervalSince1970: 1_900_000_000),
            expiresAt: nil
        )
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.browser,
                browserLease: lease
            )
        )
        let handler = makeHandler(handlers: .same(rillvia))
        let coordinator = makeCoordinator(handler: handler)
        _ = await coordinator.reconcile()

        let disableOutcome = await coordinator.disable()
        XCTAssertEqual(disableOutcome, .succeeded)
        XCTAssertNil(
            try repository.loadConfiguration().browserLease,
            "Leaving Smart Routing must discard its temporary override."
        )

        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .direct,
                fallbackBrowser: chrome.browser,
                browserLease: lease
            )
        )
        let enableOutcome = await coordinator.enable(
            fallback: chrome.browser
        )
        XCTAssertEqual(enableOutcome, .succeeded)
        XCTAssertNil(
            try repository.loadConfiguration().browserLease,
            "Entering Smart Routing must not reactivate stale state."
        )
    }

    func testRecoveryCommitsSmartConfigurationOnlyAfterDesiredHandlersVerify() async throws {
        let desiredConfiguration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.browser
        )
        let operationID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000041"
        )!
        let pending = PendingHandlerOperation(
            id: operationID,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            kind: .smartActivation,
            desiredHandlers: .same(rillvia),
            undoReceipt: HandlerUndoReceipt(
                operationID: operationID,
                issuedAt: Date(timeIntervalSince1970: 1_800_000_001),
                precondition: .same(rillvia),
                restore: .same(chrome)
            ),
            completedSchemes: [.https, .http],
            configurationBefore: .fresh,
            configurationOnSuccess: desiredConfiguration
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(pendingOperation: pending)
        )
        let handler = makeHandler(handlers: .same(rillvia))
        let coordinator = makeCoordinator(handler: handler)

        let status = await coordinator.reconcile()

        XCTAssertEqual(status, .active(chrome.browser))
        XCTAssertEqual(
            try repository.loadConfiguration(),
            desiredConfiguration
        )
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    private func makeHandler(
        handlers: HTTPHandlerSnapshot
    ) -> FakeSystemBrowserHandler {
        FakeSystemBrowserHandler(
            handlers: handlers,
            applications: [
                rillvia.browser: rillvia.applicationURL,
                chrome.browser: chrome.applicationURL,
                safari.browser: safari.applicationURL,
            ]
        )
    }

    private func makeCoordinator(
        handler: FakeSystemBrowserHandler
    ) -> SmartRoutingCoordinator {
        let transactionCoordinator = HandlerTransactionCoordinator(
            systemHandler: handler,
            repository: repository,
            rillvia: rillvia.browser
        )
        return SmartRoutingCoordinator(
            systemHandler: handler,
            repository: repository,
            transactionCoordinator: transactionCoordinator,
            rillvia: rillvia.browser
        )
    }
}
