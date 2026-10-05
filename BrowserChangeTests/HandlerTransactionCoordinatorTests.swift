import Foundation
import XCTest
@testable import BrowserChange

@MainActor
final class HandlerTransactionCoordinatorTests: XCTestCase {
    private enum TestFailure: Error {
        case change
        case rollback
    }

    private let browserChange = BrowserReference(
        bundleIdentifier: "com.browserchange.BrowserChange"
    )
    private let browserChangeApplication = HandlerApplication(
        browser: BrowserReference(
            bundleIdentifier: "com.browserchange.BrowserChange"
        ),
        applicationURL: URL(fileURLWithPath: "/Applications/BrowserChange.app")
    )
    private let chrome = HandlerApplication(
        browser: BrowserReference(bundleIdentifier: "com.google.Chrome"),
        applicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
    )
    private let safari = HandlerApplication(
        browser: BrowserReference(bundleIdentifier: "com.apple.Safari"),
        applicationURL: URL(fileURLWithPath: "/Applications/Safari.app")
    )
    private let firefox = HandlerApplication(
        browser: BrowserReference(bundleIdentifier: "org.mozilla.firefox"),
        applicationURL: URL(fileURLWithPath: "/Applications/Firefox.app")
    )
    private let operationID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000021"
    )!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var directory: URL!
    private var repository: StateRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "HandlerTransactionCoordinatorTests-\(UUID().uuidString)"
            )
        repository = StateRepository(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testDirectSwitchJournalsProgressVerifiesAndRetainsUndo() async throws {
        let handler = makeHandler(handlers: .same(chrome))
        var pendingBeforeMutation: PendingHandlerOperation?
        var progressBeforeHTTP: [WebScheme]?
        var inFlightBeforeHTTP: WebScheme?
        var journalReadError: Error?
        handler.beforeSet = { [repository] _, index in
            do {
                let pending = try repository?.loadHandlerJournal().pendingOperation
                if index == 0 {
                    pendingBeforeMutation = pending
                } else if index == 1 {
                    progressBeforeHTTP = pending?.completedSchemes
                    inFlightBeforeHTTP = pending?.inFlightScheme
                }
            } catch {
                journalReadError = error
            }
        }
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.switchDirect(to: safari.browser)

        XCTAssertNil(journalReadError)
        XCTAssertEqual(pendingBeforeMutation?.desiredHandlers, .same(safari))
        XCTAssertEqual(pendingBeforeMutation?.completedSchemes, [])
        XCTAssertEqual(pendingBeforeMutation?.inFlightScheme, .https)
        XCTAssertEqual(progressBeforeHTTP, [.https])
        XCTAssertEqual(inFlightBeforeHTTP, .http)
        XCTAssertEqual(
            handler.setCalls,
            [
                .init(browser: safari.browser, scheme: .https),
                .init(browser: safari.browser, scheme: .http),
            ]
        )
        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(handler.handlers, .same(safari))

        let journal = try repository.loadHandlerJournal()
        XCTAssertNil(journal.pendingOperation)
        XCTAssertEqual(journal.undoReceipt?.operationID, operationID)
        XCTAssertEqual(journal.undoReceipt?.precondition, .same(safari))
        XCTAssertEqual(journal.undoReceipt?.restore, .same(chrome))
        XCTAssertTrue(coordinator.canUndo(currentHandlers: handler.handlers))
    }

    func testHTTPFailureRollsBackCompletedHTTPSChange() async throws {
        let handler = makeHandler(handlers: .same(chrome))
        handler.setErrorsByCall[1] = TestFailure.change
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.switchDirect(to: safari.browser)

        XCTAssertEqual(outcome, .failed(.handlerChangeFailed))
        XCTAssertEqual(
            handler.setCalls,
            [
                .init(browser: safari.browser, scheme: .https),
                .init(browser: safari.browser, scheme: .http),
                .init(browser: chrome.browser, scheme: .https),
            ]
        )
        XCTAssertEqual(handler.handlers, .same(chrome))
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testReportedFailureAlsoRollsBackSchemeThatReachedDesiredState() async throws {
        let handler = makeHandler(handlers: .same(chrome))
        handler.setErrorsAfterMutationByCall[1] = TestFailure.change
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.switchDirect(to: safari.browser)

        XCTAssertEqual(outcome, .failed(.handlerChangeFailed))
        XCTAssertEqual(
            handler.setCalls,
            [
                .init(browser: safari.browser, scheme: .https),
                .init(browser: safari.browser, scheme: .http),
                .init(browser: chrome.browser, scheme: .http),
                .init(browser: chrome.browser, scheme: .https),
            ]
        )
        XCTAssertEqual(handler.handlers, .same(chrome))
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testVerificationMismatchRollsBackEveryOwnedChange() async throws {
        let handler = makeHandler(handlers: .same(chrome))
        handler.ignoredSetCallIndices = [1]
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.switchDirect(to: safari.browser)

        XCTAssertEqual(outcome, .failed(.verificationFailed))
        XCTAssertEqual(
            handler.setCalls,
            [
                .init(browser: safari.browser, scheme: .https),
                .init(browser: safari.browser, scheme: .http),
                .init(browser: chrome.browser, scheme: .https),
            ]
        )
        XCTAssertEqual(handler.handlers, .same(chrome))
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testExternalChangeDuringFailureIsNeverOverwritten() async throws {
        let handler = makeHandler(handlers: .same(chrome))
        handler.setErrorsByCall[1] = TestFailure.change
        handler.beforeSet = { [firefox] _, index in
            if index == 1 {
                handler.handlers[.https] = firefox
            }
        }
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.switchDirect(to: safari.browser)

        XCTAssertEqual(outcome, .degraded(.handlersChangedExternally))
        XCTAssertEqual(handler.setCalls.count, 2)
        XCTAssertEqual(handler.handlers.https, firefox)
        XCTAssertEqual(handler.handlers.http, chrome)
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testRollbackFailureRemainsPendingAndReportsDegradedState() async throws {
        let handler = makeHandler(handlers: .same(chrome))
        handler.setErrorsByCall[1] = TestFailure.change
        handler.setErrorsByCall[2] = TestFailure.rollback
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.switchDirect(to: safari.browser)

        XCTAssertEqual(outcome, .degraded(.rollbackFailed))
        XCTAssertEqual(handler.handlers.https, safari)
        XCTAssertEqual(handler.handlers.http, chrome)
        let pending = try repository.loadHandlerJournal().pendingOperation
        XCTAssertEqual(pending?.completedSchemes, [.https])
    }

    func testRecoveryCompletesPendingOperationAlreadyAtDesiredState() async throws {
        let handler = makeHandler(handlers: .same(safari))
        let receipt = makeReceipt(precondition: .same(safari), restore: .same(chrome))
        let pending = PendingHandlerOperation(
            id: operationID,
            startedAt: now,
            kind: .direct,
            desiredHandlers: .same(safari),
            undoReceipt: receipt,
            completedSchemes: [.https, .http]
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(pendingOperation: pending)
        )
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.recoverPendingOperation()

        XCTAssertEqual(outcome, .completedSwitch)
        XCTAssertTrue(handler.setCalls.isEmpty)
        let journal = try repository.loadHandlerJournal()
        XCTAssertNil(journal.pendingOperation)
        XCTAssertEqual(journal.undoReceipt, receipt)
    }

    func testSmartTransitionCompletionRecordsConfigurationHistory() async throws {
        let before = RoutingConfiguration(
            mode: .direct,
            fallbackBrowser: chrome.browser
        )
        let desired = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.browser
        )
        try repository.saveConfiguration(before)
        let handler = makeHandler(handlers: .same(chrome))
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.activateSmartRouting(
            configuration: desired
        )

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(try repository.loadConfiguration(), desired)
        let history = try repository.loadConfigurationHistory()
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.id, operationID)
        XCTAssertEqual(history.entries.first?.recordedAt, now)
        XCTAssertEqual(history.entries.first?.configuration, desired)
    }

    func testSmartTransitionFinalPersistenceFailureRollsBackImmediately() async throws {
        let before = RoutingConfiguration(
            mode: .direct,
            fallbackBrowser: chrome.browser
        )
        let desired = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.browser
        )
        try repository.saveConfiguration(before)
        let handler = makeHandler(handlers: .same(chrome))
        handler.afterSet = { [directory] _, index in
            guard index == 1, let directory else { return }
            let historyURL = directory.appendingPathComponent(
                "configuration-history.json"
            )
            try? Data(
                #"{"schemaVersion":999,"entries":[]}"#.utf8
            ).write(to: historyURL)
        }
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.activateSmartRouting(
            configuration: desired
        )

        XCTAssertEqual(outcome, .failed(.statePersistenceFailed))
        XCTAssertEqual(handler.handlers, .same(chrome))
        XCTAssertEqual(
            handler.setCalls,
            [
                .init(browser: browserChange, scheme: .https),
                .init(browser: browserChange, scheme: .http),
                .init(browser: chrome.browser, scheme: .http),
                .init(browser: chrome.browser, scheme: .https),
            ]
        )
        XCTAssertEqual(try repository.loadConfiguration(), before)
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testRestartRollsBackSmartTransitionWhenFinalPersistenceCannotComplete() async throws {
        let before = RoutingConfiguration(
            mode: .direct,
            fallbackBrowser: chrome.browser
        )
        let desired = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.browser
        )
        try repository.saveConfiguration(before)
        let pending = PendingHandlerOperation(
            id: operationID,
            startedAt: now,
            kind: .smartActivation,
            desiredHandlers: .same(browserChangeApplication),
            undoReceipt: makeReceipt(
                precondition: .same(browserChangeApplication),
                restore: .same(chrome)
            ),
            completedSchemes: [.https, .http],
            configurationBefore: before,
            configurationOnSuccess: desired
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(pendingOperation: pending)
        )
        try Data(
            #"{"schemaVersion":999,"entries":[]}"#.utf8
        ).write(
            to: directory.appendingPathComponent(
                "configuration-history.json"
            )
        )
        let handler = makeHandler(
            handlers: .same(browserChangeApplication)
        )
        let coordinator = makeCoordinator(handler: handler)

        let recovery = await coordinator.recoverPendingOperation()
        let restartedRecovery = await makeCoordinator(
            handler: handler
        ).recoverPendingOperation()

        XCTAssertEqual(recovery, .rolledBack)
        XCTAssertEqual(restartedRecovery, .nothingPending)
        XCTAssertEqual(handler.handlers, .same(chrome))
        XCTAssertEqual(
            handler.setCalls,
            [
                .init(browser: chrome.browser, scheme: .http),
                .init(browser: chrome.browser, scheme: .https),
            ]
        )
        XCTAssertEqual(try repository.loadConfiguration(), before)
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testRecoveryRecordsSuccessfulSmartConfigurationHistory() async throws {
        let before = RoutingConfiguration(
            mode: .direct,
            fallbackBrowser: chrome.browser
        )
        let desired = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.browser
        )
        try repository.saveConfiguration(before)
        let pending = PendingHandlerOperation(
            id: operationID,
            startedAt: now,
            kind: .smartActivation,
            desiredHandlers: .same(browserChangeApplication),
            undoReceipt: makeReceipt(
                precondition: .same(browserChangeApplication),
                restore: .same(chrome)
            ),
            completedSchemes: [.https, .http],
            configurationBefore: before,
            configurationOnSuccess: desired
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(pendingOperation: pending)
        )
        let coordinator = makeCoordinator(
            handler: makeHandler(handlers: .same(browserChangeApplication))
        )

        let outcome = await coordinator.recoverPendingOperation()

        XCTAssertEqual(outcome, .completedSwitch)
        XCTAssertEqual(try repository.loadConfiguration(), desired)
        let history = try repository.loadConfigurationHistory()
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.id, operationID)
        XCTAssertEqual(history.entries.first?.configuration, desired)
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testRecoveryDoesNotDuplicateSnapshotAfterCrashBeforeJournalClear() async throws {
        let before = RoutingConfiguration(
            mode: .direct,
            fallbackBrowser: chrome.browser
        )
        let desired = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.browser
        )
        try repository.saveConfigurationHistory(
            ConfigurationHistory(
                entries: [
                    ConfigurationHistoryEntry(
                        id: operationID,
                        recordedAt: now,
                        configuration: desired
                    ),
                ]
            )
        )
        try repository.saveConfiguration(desired)
        let pending = PendingHandlerOperation(
            id: operationID,
            startedAt: now,
            kind: .smartActivation,
            desiredHandlers: .same(browserChangeApplication),
            undoReceipt: makeReceipt(
                precondition: .same(browserChangeApplication),
                restore: .same(chrome)
            ),
            completedSchemes: [.https, .http],
            configurationBefore: before,
            configurationOnSuccess: desired
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(pendingOperation: pending)
        )
        let coordinator = makeCoordinator(
            handler: makeHandler(handlers: .same(browserChangeApplication))
        )

        let firstRecovery = await coordinator.recoverPendingOperation()
        let secondRecovery = await coordinator.recoverPendingOperation()

        XCTAssertEqual(firstRecovery, .completedSwitch)
        XCTAssertEqual(secondRecovery, .nothingPending)

        let history = try repository.loadConfigurationHistory()
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.id, operationID)
        XCTAssertEqual(history.entries.first?.configuration, desired)
    }

    func testRecoveryRestoresDirectSchemeThatWasInFlightAtCrash() async throws {
        let handler = makeHandler(
            handlers: HTTPHandlerSnapshot(http: chrome, https: safari)
        )
        let pending = PendingHandlerOperation(
            id: operationID,
            startedAt: now,
            kind: .direct,
            desiredHandlers: .same(safari),
            undoReceipt: makeReceipt(
                precondition: .same(safari),
                restore: .same(chrome)
            ),
            completedSchemes: [],
            inFlightScheme: .https
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(pendingOperation: pending)
        )
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.recoverPendingOperation()

        XCTAssertEqual(outcome, .rolledBack)
        XCTAssertEqual(
            handler.setCalls,
            [.init(browser: chrome.browser, scheme: .https)]
        )
        XCTAssertEqual(handler.handlers, .same(chrome))
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testRecoveryRestoresOnlySchemesRecordedAsOwned() async throws {
        let live = HTTPHandlerSnapshot(http: firefox, https: safari)
        let handler = makeHandler(handlers: live)
        let pending = PendingHandlerOperation(
            id: operationID,
            startedAt: now,
            kind: .direct,
            desiredHandlers: .same(safari),
            undoReceipt: makeReceipt(
                precondition: .same(safari),
                restore: .same(chrome)
            ),
            completedSchemes: [.https]
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(pendingOperation: pending)
        )
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.recoverPendingOperation()

        XCTAssertEqual(outcome, .rolledBack)
        XCTAssertEqual(
            handler.setCalls,
            [.init(browser: chrome.browser, scheme: .https)]
        )
        XCTAssertEqual(handler.handlers.http, firefox)
        XCTAssertEqual(handler.handlers.https, chrome)
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testRecoveryRestoresUndoSchemeThatWasInFlightAtCrash() async throws {
        let directReceipt = makeReceipt(
            precondition: .same(safari),
            restore: .same(chrome)
        )
        let undoOperation = PendingHandlerOperation(
            id: operationID,
            startedAt: now,
            kind: .undo,
            desiredHandlers: .same(chrome),
            undoReceipt: HandlerUndoReceipt(
                operationID: operationID,
                issuedAt: now,
                precondition: .same(chrome),
                restore: .same(safari)
            ),
            completedSchemes: [],
            inFlightScheme: .https
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(
                pendingOperation: undoOperation,
                undoReceipt: directReceipt
            )
        )
        let handler = makeHandler(
            handlers: HTTPHandlerSnapshot(http: safari, https: chrome)
        )
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.recoverPendingOperation()

        XCTAssertEqual(outcome, .rolledBack)
        XCTAssertEqual(
            handler.setCalls,
            [.init(browser: safari.browser, scheme: .https)]
        )
        XCTAssertEqual(handler.handlers, .same(safari))
        let journal = try repository.loadHandlerJournal()
        XCTAssertNil(journal.pendingOperation)
        XCTAssertEqual(journal.undoReceipt, directReceipt)
    }

    func testUndoRestoresReceiptSnapshotAndClearsReceipt() async throws {
        let handler = makeHandler(handlers: .same(safari))
        let receipt = makeReceipt(precondition: .same(safari), restore: .same(chrome))
        try repository.saveHandlerJournal(
            HandlerOperationJournal(undoReceipt: receipt)
        )
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.undo()

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(
            handler.setCalls,
            [
                .init(browser: chrome.browser, scheme: .https),
                .init(browser: chrome.browser, scheme: .http),
            ]
        )
        XCTAssertEqual(handler.handlers, .same(chrome))
        let journal = try repository.loadHandlerJournal()
        XCTAssertNil(journal.pendingOperation)
        XCTAssertNil(journal.undoReceipt)
    }

    func testUndoRefusesExternalHandlerChangeWithoutOverwritingIt() async throws {
        let handler = makeHandler(
            handlers: HTTPHandlerSnapshot(http: firefox, https: safari)
        )
        let receipt = makeReceipt(precondition: .same(safari), restore: .same(chrome))
        try repository.saveHandlerJournal(
            HandlerOperationJournal(undoReceipt: receipt)
        )
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.undo()

        XCTAssertEqual(outcome, .refused(.undoPreconditionFailed))
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(handler.handlers.http, firefox)
        XCTAssertEqual(handler.handlers.https, safari)
        XCTAssertNil(try repository.loadHandlerJournal().undoReceipt)
    }

    func testCancellationRollsBackAndRemainsCancellation() async throws {
        let handler = makeHandler(handlers: .same(chrome))
        handler.setErrorsByCall[1] = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError
        )
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.switchDirect(to: safari.browser)

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(handler.handlers, .same(chrome))
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    func testDirectSwitchResolvesTargetBeforeJournalingOrMutating() async throws {
        let handler = FakeSystemBrowserHandler(handlers: .same(chrome))
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.switchDirect(to: safari.browser)

        XCTAssertEqual(outcome, .failed(.targetUnavailable))
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(try repository.loadHandlerJournal(), .fresh)
    }

    func testDirectSwitchRefusesChangedSchemeWithMissingBaseline() async throws {
        let handler = makeHandler(
            handlers: HTTPHandlerSnapshot(http: nil, https: chrome)
        )
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.switchDirect(to: safari.browser)

        XCTAssertEqual(outcome, .failed(.missingBaseline(.http)))
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(try repository.loadHandlerJournal(), .fresh)
    }

    func testRecoveryLeavesPendingWhenOwnedSchemeHasMissingBaseline() async throws {
        let restore = HTTPHandlerSnapshot(http: nil, https: chrome)
        let pending = PendingHandlerOperation(
            id: operationID,
            startedAt: now,
            kind: .direct,
            desiredHandlers: .same(safari),
            undoReceipt: makeReceipt(
                precondition: .same(safari),
                restore: restore
            ),
            completedSchemes: [.http]
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(pendingOperation: pending)
        )
        let handler = makeHandler(
            handlers: HTTPHandlerSnapshot(http: safari, https: chrome)
        )
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.recoverPendingOperation()

        XCTAssertEqual(outcome, .degraded(.rollbackFailed))
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(
            try repository.loadHandlerJournal().pendingOperation,
            pending
        )
    }

    func testUndoRefusesChangedSchemeWithMissingRestoreBaseline() async throws {
        let receipt = makeReceipt(
            precondition: .same(safari),
            restore: HTTPHandlerSnapshot(http: nil, https: chrome)
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(undoReceipt: receipt)
        )
        let handler = makeHandler(handlers: .same(safari))
        let coordinator = makeCoordinator(handler: handler)

        let outcome = await coordinator.undo()

        XCTAssertEqual(outcome, .failed(.missingBaseline(.http)))
        XCTAssertTrue(handler.setCalls.isEmpty)
        let journal = try repository.loadHandlerJournal()
        XCTAssertNil(journal.pendingOperation)
        XCTAssertEqual(journal.undoReceipt, receipt)
    }

    private func makeHandler(
        handlers: HTTPHandlerSnapshot
    ) -> FakeSystemBrowserHandler {
        FakeSystemBrowserHandler(
            handlers: handlers,
            applications: [
                browserChangeApplication.browser:
                    browserChangeApplication.applicationURL,
                chrome.browser: chrome.applicationURL,
                safari.browser: safari.applicationURL,
                firefox.browser: firefox.applicationURL,
            ]
        )
    }

    private func makeCoordinator(
        handler: FakeSystemBrowserHandler
    ) -> HandlerTransactionCoordinator {
        HandlerTransactionCoordinator(
            systemHandler: handler,
            repository: repository,
            browserChange: browserChange,
            now: { [now] in now },
            makeOperationID: { [operationID] in operationID }
        )
    }

    private func makeReceipt(
        precondition: HTTPHandlerSnapshot,
        restore: HTTPHandlerSnapshot
    ) -> HandlerUndoReceipt {
        HandlerUndoReceipt(
            operationID: operationID,
            issuedAt: now,
            precondition: precondition,
            restore: restore
        )
    }
}
