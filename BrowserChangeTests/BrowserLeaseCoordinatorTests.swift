import Foundation
import XCTest
@testable import BrowserChange

@MainActor
final class BrowserLeaseCoordinatorTests: XCTestCase {
    private let browserChange = HandlerApplication(
        browser: BrowserReference(
            bundleIdentifier: "com.browserchange.BrowserChange"
        ),
        applicationURL: URL(
            fileURLWithPath: "/Applications/BrowserChange.app"
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
        applicationURL: URL(
            fileURLWithPath: "/Applications/Safari.app"
        )
    )
    private let firefox = HandlerApplication(
        browser: BrowserReference(bundleIdentifier: "org.mozilla.firefox"),
        applicationURL: URL(
            fileURLWithPath: "/Applications/Firefox.app"
        )
    )

    private var directory: URL!
    private var repository: StateRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserLeaseCoordinatorTests-\(UUID().uuidString)"
            )
        repository = StateRepository(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPresetsPersistDeadlinesSnapshotsAndRescheduleWithoutHandlerWrites() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try saveActiveSmartConfiguration()
        let handler = makeHandler(handlers: .same(browserChange))
        let scheduler = FakeBrowserLeaseScheduler()
        let coordinator = makeCoordinator(
            handler: handler,
            scheduler: scheduler,
            now: { now }
        )

        for (index, preset, interval) in [
            (1, BrowserLeasePreset.fifteenMinutes, 15 * 60.0),
            (2, .thirtyMinutes, 30 * 60.0),
            (3, .sixtyMinutes, 60 * 60.0),
        ] {
            XCTAssertEqual(
                coordinator.startLease(
                    to: safari.browser,
                    preset: preset
                ),
                .succeeded
            )
            let lease = try XCTUnwrap(
                repository.loadConfiguration().browserLease
            )
            XCTAssertEqual(lease.revision, index)
            XCTAssertEqual(lease.startedAt, now)
            XCTAssertEqual(
                lease.expiresAt,
                now.addingTimeInterval(interval)
            )
            XCTAssertEqual(scheduler.deadline, lease.expiresAt)
        }

        XCTAssertEqual(
            coordinator.startLease(
                to: firefox.browser,
                preset: .untilEnded
            ),
            .succeeded
        )
        let untilEnded = try XCTUnwrap(
            repository.loadConfiguration().browserLease
        )
        XCTAssertEqual(untilEnded.revision, 4)
        XCTAssertNil(untilEnded.expiresAt)
        XCTAssertNil(scheduler.deadline)
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            4
        )
        XCTAssertEqual(scheduler.scheduleCount, 3)
        XCTAssertEqual(scheduler.cancelCount, 3)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testStartRejectsDirectSuspendedDegradedTransitioningAndInvalidTargets() throws {
        let scheduler = FakeBrowserLeaseScheduler()

        let directHandler = makeHandler(handlers: .same(browserChange))
        let direct = makeCoordinator(
            handler: directHandler,
            scheduler: scheduler
        )
        XCTAssertEqual(
            direct.startLease(
                to: safari.browser,
                preset: .fifteenMinutes
            ),
            .failed(.smartRoutingUnavailable)
        )

        try saveActiveSmartConfiguration()
        let suspendedHandler = makeHandler(handlers: .same(chrome))
        let suspended = makeCoordinator(
            handler: suspendedHandler,
            scheduler: scheduler
        )
        XCTAssertEqual(
            suspended.startLease(
                to: safari.browser,
                preset: .fifteenMinutes
            ),
            .failed(.smartRoutingUnavailable)
        )

        try repository.saveConfiguration(
            RoutingConfiguration(mode: .smart)
        )
        let degradedHandler = makeHandler(handlers: .same(browserChange))
        let degraded = makeCoordinator(
            handler: degradedHandler,
            scheduler: scheduler
        )
        XCTAssertEqual(
            degraded.startLease(
                to: safari.browser,
                preset: .fifteenMinutes
            ),
            .failed(.smartRoutingUnavailable)
        )

        try saveActiveSmartConfiguration()
        try repository.saveHandlerJournal(
            HandlerOperationJournal(
                pendingOperation: pendingOperation()
            )
        )
        let transitioning = makeCoordinator(
            handler: degradedHandler,
            scheduler: scheduler
        )
        XCTAssertEqual(
            transitioning.startLease(
                to: safari.browser,
                preset: .fifteenMinutes
            ),
            .failed(.smartRoutingUnavailable)
        )

        try repository.saveHandlerJournal(.fresh)
        XCTAssertEqual(
            transitioning.startLease(
                to: browserChange.browser,
                preset: .fifteenMinutes
            ),
            .failed(.selfTarget)
        )
        let missing = BrowserReference(
            bundleIdentifier: "com.example.Missing"
        )
        XCTAssertEqual(
            transitioning.startLease(
                to: missing,
                preset: .fifteenMinutes
            ),
            .failed(.targetUnavailable(missing))
        )

        XCTAssertTrue(directHandler.setCalls.isEmpty)
        XCTAssertTrue(suspendedHandler.setCalls.isEmpty)
        XCTAssertTrue(degradedHandler.setCalls.isEmpty)
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            0
        )
    }

    func testExactBoundaryExpiryIsIdempotentCreatesNoUndoAndDoesNotWriteHandlers() throws {
        var now = Date(timeIntervalSince1970: 1_900_000_000)
        try saveActiveSmartConfiguration()
        let handler = makeHandler(handlers: .same(browserChange))
        let scheduler = FakeBrowserLeaseScheduler()
        let coordinator = makeCoordinator(
            handler: handler,
            scheduler: scheduler,
            now: { now }
        )
        XCTAssertEqual(
            coordinator.startLease(
                to: safari.browser,
                preset: .fifteenMinutes
            ),
            .succeeded
        )
        let expiry = try XCTUnwrap(
            repository.loadConfiguration().browserLease?.expiresAt
        )
        now = expiry

        scheduler.fire()
        let historyCount = try repository
            .loadConfigurationHistory().entries.count
        let second = coordinator.reconcile()

        XCTAssertNil(try repository.loadConfiguration().browserLease)
        XCTAssertEqual(
            second,
            BrowserLeaseReconciliation(
                didExpire: false,
                issue: nil
            )
        )
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            historyCount
        )
        XCTAssertFalse(coordinator.canUndo)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testUndoReconcilesExactExpiryBeforeDelayedSchedulerCallback() throws {
        var now = Date(timeIntervalSince1970: 1_900_000_000)
        try saveActiveSmartConfiguration()
        let handler = makeHandler(handlers: .same(browserChange))
        let scheduler = FakeBrowserLeaseScheduler()
        let coordinator = makeCoordinator(
            handler: handler,
            scheduler: scheduler,
            now: { now }
        )
        XCTAssertEqual(
            coordinator.startLease(
                to: safari.browser,
                preset: .fifteenMinutes
            ),
            .succeeded
        )
        XCTAssertEqual(
            coordinator.startLease(
                to: firefox.browser,
                preset: .fifteenMinutes
            ),
            .succeeded
        )
        now = try XCTUnwrap(
            repository.loadConfiguration().browserLease?.expiresAt
        )
        XCTAssertNotNil(
            scheduler.deadline,
            "The scheduler callback must still be pending at the boundary."
        )

        XCTAssertFalse(
            coordinator.canUndo,
            "Undo must stop being offered at the exact expiry boundary."
        )
        XCTAssertEqual(
            coordinator.undo(),
            .failed(.noUndoReceipt)
        )

        XCTAssertNil(try repository.loadConfiguration().browserLease)
        XCTAssertFalse(coordinator.canUndo)
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            3,
            "Undo must reconcile expiry, not restore the expired prior lease."
        )
        XCTAssertNil(scheduler.deadline)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testColdReconcileRemovesPersistedExpiredLeaseAndKeepsUnavailableLease() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let expired = BrowserLease(
            browser: safari.browser,
            startedAt: now.addingTimeInterval(-901),
            expiresAt: now
        )
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.browser,
                browserLease: expired
            )
        )
        let handler = makeHandler(handlers: .same(browserChange))
        let scheduler = FakeBrowserLeaseScheduler()
        let coordinator = makeCoordinator(
            handler: handler,
            scheduler: scheduler,
            now: { now }
        )

        XCTAssertEqual(
            coordinator.reconcile(),
            BrowserLeaseReconciliation(
                didExpire: true,
                issue: nil
            )
        )
        XCTAssertNil(try repository.loadConfiguration().browserLease)

        let missing = BrowserReference(
            bundleIdentifier: "com.example.Missing"
        )
        var configuration = try repository.loadConfiguration()
        configuration.browserLease = BrowserLease(
            browser: missing,
            startedAt: now,
            expiresAt: now.addingTimeInterval(900)
        )
        try repository.saveConfiguration(configuration)

        XCTAssertEqual(
            coordinator.reconcile(),
            BrowserLeaseReconciliation(
                didExpire: false,
                issue: .targetUnavailable(missing)
            )
        )
        XCTAssertEqual(
            try repository.loadConfiguration().browserLease?.browser,
            missing
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testColdReconcilePurgesLeaseOutsideSmartMode() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .direct,
                fallbackBrowser: chrome.browser,
                browserLease: BrowserLease(
                    browser: safari.browser,
                    startedAt: now,
                    expiresAt: nil
                )
            )
        )
        let handler = makeHandler(handlers: .same(chrome))
        let coordinator = makeCoordinator(
            handler: handler,
            scheduler: FakeBrowserLeaseScheduler(),
            now: { now }
        )

        _ = coordinator.reconcile()

        XCTAssertNil(try repository.loadConfiguration().browserLease)
        XCTAssertFalse(coordinator.canUndo)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testReplaceEndAndUndoRestoreOnlyWhenFullPreconditionMatches() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try saveActiveSmartConfiguration()
        let handler = makeHandler(handlers: .same(browserChange))
        let scheduler = FakeBrowserLeaseScheduler()
        let coordinator = makeCoordinator(
            handler: handler,
            scheduler: scheduler,
            now: { now }
        )
        XCTAssertEqual(
            coordinator.startLease(
                to: safari.browser,
                preset: .fifteenMinutes
            ),
            .succeeded
        )
        let first = try XCTUnwrap(
            repository.loadConfiguration().browserLease
        )
        XCTAssertEqual(
            coordinator.startLease(
                to: firefox.browser,
                preset: .untilEnded
            ),
            .succeeded
        )

        XCTAssertEqual(coordinator.undo(), .succeeded)
        XCTAssertEqual(
            try repository.loadConfiguration().browserLease,
            first
        )

        XCTAssertEqual(coordinator.endLease(), .succeeded)
        XCTAssertNil(try repository.loadConfiguration().browserLease)
        XCTAssertEqual(coordinator.undo(), .succeeded)
        XCTAssertEqual(
            try repository.loadConfiguration().browserLease,
            first
        )

        XCTAssertEqual(coordinator.endLease(), .succeeded)
        var laterConfiguration = try repository.loadConfiguration()
        laterConfiguration.domainRules.append(
            DomainRule(
                domain: "later.example",
                browser: chrome.browser
            )
        )
        try repository.saveConfiguration(laterConfiguration)

        XCTAssertEqual(
            coordinator.undo(),
            .failed(.undoPreconditionFailed)
        )
        XCTAssertEqual(
            try repository.loadConfiguration(),
            laterConfiguration
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testUndoStaysInvalidAfterConfigurationDivergesAndReturns() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try saveActiveSmartConfiguration()
        let handler = makeHandler(handlers: .same(browserChange))
        let coordinator = makeCoordinator(
            handler: handler,
            scheduler: FakeBrowserLeaseScheduler(),
            now: { now }
        )
        XCTAssertEqual(
            coordinator.startLease(
                to: safari.browser,
                preset: .untilEnded
            ),
            .succeeded
        )
        let receiptPrecondition = try repository.loadConfiguration()
        var later = receiptPrecondition
        later.domainRules.append(
            DomainRule(domain: "later.example", browser: chrome.browser)
        )
        try repository.saveConfiguration(later)
        _ = coordinator.reconcile()

        try repository.saveConfiguration(receiptPrecondition)
        _ = coordinator.reconcile()

        XCTAssertFalse(coordinator.canUndo)
        XCTAssertEqual(
            coordinator.undo(),
            .failed(.noUndoReceipt)
        )
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testCountdownFormattingIsDeterministic() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        XCTAssertEqual(
            BrowserLeaseFormatting.remainingText(
                for: BrowserLease(
                    browser: safari.browser,
                    startedAt: now,
                    expiresAt: now.addingTimeInterval(900)
                ),
                at: now
            ),
            "15:00 remaining"
        )
        XCTAssertEqual(
            BrowserLeaseFormatting.remainingText(
                for: BrowserLease(
                    browser: safari.browser,
                    startedAt: now,
                    expiresAt: nil
                ),
                at: now
            ),
            "Until you stop"
        )
        XCTAssertEqual(
            BrowserLeasePreset.fifteenMinutes.actionTitle(
                browserName: "Safari"
            ),
            "Use Safari for 15 minutes"
        )
        XCTAssertEqual(
            BrowserLeasePreset.untilEnded.actionTitle(
                browserName: "Safari"
            ),
            "Use Safari until you stop"
        )
        XCTAssertEqual(
            BrowserLeasePreset.untilEnded.activeDescription(
                browserName: "Safari"
            ),
            "Using Safari until you stop"
        )
    }

    private func saveActiveSmartConfiguration() throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.browser
            )
        )
    }

    private func makeHandler(
        handlers: HTTPHandlerSnapshot
    ) -> FakeSystemBrowserHandler {
        FakeSystemBrowserHandler(
            handlers: handlers,
            applications: [
                browserChange.browser: browserChange.applicationURL,
                chrome.browser: chrome.applicationURL,
                safari.browser: safari.applicationURL,
                firefox.browser: firefox.applicationURL,
            ]
        )
    }

    private func makeCoordinator(
        handler: FakeSystemBrowserHandler,
        scheduler: FakeBrowserLeaseScheduler,
        now: @escaping () -> Date = Date.init
    ) -> BrowserLeaseCoordinator {
        let transactionCoordinator = HandlerTransactionCoordinator(
            systemHandler: handler,
            repository: repository,
            browserChange: browserChange.browser
        )
        let smartRoutingCoordinator = SmartRoutingCoordinator(
            systemHandler: handler,
            repository: repository,
            transactionCoordinator: transactionCoordinator,
            browserChange: browserChange.browser
        )
        return BrowserLeaseCoordinator(
            systemHandler: handler,
            repository: repository,
            browserChange: browserChange.browser,
            smartRoutingCoordinator: smartRoutingCoordinator,
            scheduler: scheduler,
            now: now
        )
    }

    private func pendingOperation() -> PendingHandlerOperation {
        let id = UUID()
        return PendingHandlerOperation(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_900_000_000),
            kind: .smartDeactivation,
            desiredHandlers: .same(chrome),
            undoReceipt: HandlerUndoReceipt(
                operationID: id,
                issuedAt: Date(timeIntervalSince1970: 1_900_000_000),
                precondition: .same(chrome),
                restore: .same(browserChange)
            )
        )
    }
}

@MainActor
private final class FakeBrowserLeaseScheduler: BrowserLeaseScheduling {
    private(set) var deadline: Date?
    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0
    private var action: (() -> Void)?

    func schedule(at deadline: Date, action: @escaping () -> Void) {
        self.deadline = deadline
        self.action = action
        scheduleCount += 1
    }

    func cancel() {
        deadline = nil
        action = nil
        cancelCount += 1
    }

    func fire() {
        let action = action
        deadline = nil
        self.action = nil
        action?()
    }
}
