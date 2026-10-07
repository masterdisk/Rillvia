import Foundation
import XCTest
@testable import Rillvia

@MainActor
final class BrowserStoreTransactionTests: XCTestCase {
    private enum TestFailure: Error {
        case change
        case rollback
    }

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
    private let firefox = InstalledBrowser(
        id: "org.mozilla.firefox",
        name: "Firefox",
        version: "143",
        appURL: URL(fileURLWithPath: "/Applications/Firefox.app")
    )

    private var directory: URL!
    private var repository: StateRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserStoreTransactionTests-\(UUID().uuidString)"
            )
        repository = StateRepository(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testSuccessfulDirectSwitchEnablesUndoAndUndoRestoresBaseline() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let store = makeStore(handler: handler)

        await store.makeDefault(safari)

        XCTAssertEqual(store.defaultBundleID, safari.id)
        XCTAssertEqual(store.transactionStatus, .idle)
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.message, "Safari is now the default.")

        await store.undoLastBrowserSwitch()

        XCTAssertEqual(handler.handlers, .same(application(for: chrome)))
        XCTAssertEqual(store.defaultBundleID, chrome.id)
        XCTAssertEqual(store.transactionStatus, .idle)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.message, "Restored the previous web-link handlers.")
    }

    func testSplitHandlersExposePerSchemeHealthAndRepairUsesSelection() async {
        let handler = makeHandler(
            handlers: HTTPHandlerSnapshot(
                http: application(for: safari),
                https: application(for: chrome)
            )
        )
        let store = makeStore(handler: handler)

        XCTAssertEqual(
            store.handlerHealth.http,
            .external(application(for: safari))
        )
        XCTAssertEqual(
            store.handlerHealth.https,
            .external(application(for: chrome))
        )
        XCTAssertTrue(store.hasSplitHandlers)
        XCTAssertNil(store.defaultBundleID)

        store.selectBrowser(safari.id)
        await store.repairSelectedHandlers()

        XCTAssertEqual(handler.handlers, .same(application(for: safari)))
        XCTAssertFalse(store.hasSplitHandlers)
        XCTAssertEqual(store.defaultBundleID, safari.id)
        XCTAssertTrue(store.canUndo)
    }

    func testCancellationKeepsFriendlyMessageAfterSuccessfulRollback() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        handler.setErrorsByCall[1] = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError
        )
        let store = makeStore(handler: handler)

        await store.makeDefault(safari)

        XCTAssertEqual(handler.handlers, .same(application(for: chrome)))
        XCTAssertEqual(store.defaultBundleID, chrome.id)
        XCTAssertEqual(store.transactionStatus, .idle)
        XCTAssertEqual(store.message, "Left the default where it was.")
    }

    func testMissingBaselineExplainsHowToMakeSwitchingSafe() async {
        let handler = makeHandler(
            handlers: HTTPHandlerSnapshot(
                http: nil,
                https: application(for: chrome)
            )
        )
        let store = makeStore(handler: handler)

        await store.makeDefault(safari)

        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertEqual(store.transactionStatus, .idle)
        XCTAssertEqual(
            store.message,
            "Rillvia cannot safely change the HTTP handler because there is no current handler to restore. Set a default browser in System Settings, then try again."
        )
    }

    func testRollbackFailurePublishesDegradedTransactionState() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        handler.setErrorsByCall[1] = TestFailure.change
        handler.setErrorsByCall[2] = TestFailure.rollback
        let store = makeStore(handler: handler)

        await store.makeDefault(safari)

        XCTAssertEqual(store.transactionStatus, .degraded)
        XCTAssertTrue(store.hasSplitHandlers)
        XCTAssertEqual(
            store.message,
            "Rillvia could not restore both web-link handlers. Make HTTP and HTTPS match before trying again."
        )
    }

    func testUndoRefusesAnExternalChangeWithoutOverwritingIt() async {
        let handler = makeHandler(handlers: .same(application(for: chrome)))
        let store = makeStore(handler: handler)
        await store.makeDefault(safari)
        handler.handlers[.http] = application(for: firefox)

        store.refresh()
        XCTAssertFalse(store.canUndo)

        await store.undoLastBrowserSwitch()

        XCTAssertEqual(handler.handlers.http, application(for: firefox))
        XCTAssertEqual(handler.handlers.https, application(for: safari))
        XCTAssertEqual(
            store.message,
            "Undo is no longer available because the web-link handlers changed elsewhere."
        )
        XCTAssertFalse(store.canUndo)
    }

    func testActivationCompletesAnInterruptedVerifiedSwitch() async throws {
        let desired = HTTPHandlerSnapshot.same(application(for: safari))
        let baseline = HTTPHandlerSnapshot.same(application(for: chrome))
        let operationID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000031"
        )!
        let receipt = HandlerUndoReceipt(
            operationID: operationID,
            issuedAt: Date(timeIntervalSince1970: 1_800_000_000),
            precondition: desired,
            restore: baseline
        )
        try repository.saveHandlerJournal(
            HandlerOperationJournal(
                pendingOperation: PendingHandlerOperation(
                    id: operationID,
                    startedAt: Date(timeIntervalSince1970: 1_799_999_999),
                    kind: .direct,
                    desiredHandlers: desired,
                    undoReceipt: receipt,
                    completedSchemes: [.https, .http]
                )
            )
        )
        let handler = makeHandler(handlers: desired)
        let store = makeStore(handler: handler)

        await store.activate()

        XCTAssertEqual(store.defaultBundleID, safari.id)
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.transactionStatus, .idle)
        XCTAssertNil(try repository.loadHandlerJournal().pendingOperation)
    }

    private func makeStore(
        handler: FakeSystemBrowserHandler
    ) -> BrowserStore {
        BrowserStore(
            environment: AppEnvironment(
                browserCatalog: FakeBrowserCatalog(
                    browsers: [chrome, safari, firefox]
                ),
                systemBrowserHandler: handler,
                stateRepository: repository
            )
        )
    }

    private func makeHandler(
        handlers: HTTPHandlerSnapshot
    ) -> FakeSystemBrowserHandler {
        FakeSystemBrowserHandler(
            handlers: handlers,
            applications: [
                chrome.reference: chrome.appURL,
                safari.reference: safari.appURL,
                firefox.reference: firefox.appURL,
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
}
